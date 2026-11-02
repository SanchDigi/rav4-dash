import SwiftUI
import UIKit
import Combine

struct AlertEvent: Identifiable, Equatable {
    let id = UUID()
    let metric: MetricID
    let message: String
}

/// Shared state for the iPhone screen and CarPlay: live values, layouts, trip stats and alerts.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Source { case none, demo, obd }

    @Published private(set) var values: [MetricID: Double] = [:]
    @Published private(set) var history: [MetricID: [Double]] = [:]
    @Published var layouts: [DashLayout] { didSet { saveLayouts() } }
    @Published var selectedLayoutID: UUID {
        didSet { UserDefaults.standard.set(selectedLayoutID.uuidString, forKey: Keys.selected) }
    }
    @Published var isEditing = false
    @Published var draggingTileID: UUID?
    @Published private(set) var source: Source = .none
    @Published private(set) var activeAlerts: Set<MetricID> = []
    @Published private(set) var latestAlert: AlertEvent?
    @Published private(set) var codes: DTCReport?
    @Published private(set) var isReadingCodes = false
    @Published private(set) var tripStartBattery: Double?
    @Published private(set) var evSeconds: Double = 0
    @Published private(set) var engineSeconds: Double = 0

    let obd = OBDSession()
    private let demo = DemoSource()
    private var lastRPMDate: Date?
    private var lastHistoryDate: [MetricID: Date] = [:]
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let layouts = "layouts.v1"
        static let selected = "layouts.selected"
    }

    private static let historyLimit = 600       // points kept per stat
    private static let historyInterval = 1.0    // seconds between points

    private init() {
        let loaded = Self.loadLayouts()
        layouts = loaded
        let saved = UserDefaults.standard.string(forKey: Keys.selected).flatMap { UUID(uuidString: $0) }
        selectedLayoutID = loaded.first(where: { $0.id == saved })?.id ?? loaded[0].id

        obd.pidProvider = { [weak self] cycle in self?.pidsToPoll(cycle: cycle) ?? [] }
        obd.onReading = { [weak self] pid, data in self?.handleReading(pid: pid, data: data) }
        demo.onValue = { [weak self] metric, value in self?.ingest(metric, value) }
        obd.$state
            .removeDuplicates()
            .sink { [weak self] state in self?.obdStateChanged(state) }
            .store(in: &cancellables)
    }

    // MARK: - Layouts

    var currentLayout: DashLayout {
        layouts.first(where: { $0.id == selectedLayoutID }) ?? layouts[0]
    }

    private func mutateCurrent(_ change: (inout DashLayout) -> Void) {
        guard let i = layouts.firstIndex(where: { $0.id == selectedLayoutID }) else { return }
        change(&layouts[i])
    }

    func addTile(_ tile: Tile) {
        mutateCurrent { $0.tiles.append(tile) }
    }

    func updateTile(_ tile: Tile) {
        mutateCurrent { layout in
            if let i = layout.tiles.firstIndex(where: { $0.id == tile.id }) { layout.tiles[i] = tile }
        }
    }

    func removeTile(_ id: UUID) {
        mutateCurrent { $0.tiles.removeAll { $0.id == id } }
        activeAlerts = activeAlerts.filter { metric in currentLayout.tiles.contains { $0.metric == metric } }
    }

    func cycleSize(_ id: UUID) {
        mutateCurrent { layout in
            if let i = layout.tiles.firstIndex(where: { $0.id == id }) { layout.tiles[i].size = layout.tiles[i].size.next }
        }
    }

    func moveDraggedTile(onto targetID: UUID) {
        guard let dragID = draggingTileID, dragID != targetID else { return }
        mutateCurrent { layout in
            guard let from = layout.tiles.firstIndex(where: { $0.id == dragID }),
                  let to = layout.tiles.firstIndex(where: { $0.id == targetID }) else { return }
            let tile = layout.tiles.remove(at: from)
            layout.tiles.insert(tile, at: to)
        }
    }

    func addLayout() {
        let layout = DashLayout(name: "Layout \(layouts.count + 1)", tiles: [
            Tile(metric: .hybridBattery, style: .ring, size: .large)
        ])
        layouts.append(layout)
        selectedLayoutID = layout.id
    }

    func deleteLayouts(at offsets: IndexSet) {
        guard layouts.count - offsets.count >= 1 else { return }
        layouts.remove(atOffsets: offsets)
        if !layouts.contains(where: { $0.id == selectedLayoutID }) { selectedLayoutID = layouts[0].id }
    }

    func moveLayouts(from source: IndexSet, to destination: Int) {
        layouts.move(fromOffsets: source, toOffset: destination)
    }

    func resetLayouts() {
        layouts = DashLayout.defaults
        selectedLayoutID = layouts[0].id
    }

    private static func loadLayouts() -> [DashLayout] {
        if let data = UserDefaults.standard.data(forKey: Keys.layouts),
           let saved = try? JSONDecoder().decode([DashLayout].self, from: data),
           !saved.isEmpty {
            return saved
        }
        return DashLayout.defaults
    }

    private func saveLayouts() {
        if let data = try? JSONEncoder().encode(layouts) {
            UserDefaults.standard.set(data, forKey: Keys.layouts)
        }
    }

    // MARK: - Data sources

    func startDemo() {
        if obd.state.isConnected { obd.disconnect() }
        resetTrip()
        source = .demo
        demo.start()
    }

    func stopDemo() {
        demo.stop()
        if source == .demo {
            source = .none
            values = [:]
        }
    }

    private func obdStateChanged(_ state: OBDSession.State) {
        if state.isConnected {
            demo.stop()
            resetTrip()
            source = .obd
        } else if source == .obd {
            source = .none
            values = [:]
        }
    }

    private func resetTrip() {
        values = [:]
        history = [:]
        lastHistoryDate = [:]
        tripStartBattery = nil
        evSeconds = 0
        engineSeconds = 0
        lastRPMDate = nil
        activeAlerts = []
    }

    /// PIDs to read this cycle: fast ones every time, slow ones one at a time.
    func pidsToPoll(cycle: Int) -> [UInt8] {
        let supported = obd.supportedPIDs
        var metrics = Set(currentLayout.tiles.map(\.metric))
        metrics.insert(.rpm)            // drives EV / engine tracking
        metrics.insert(.hybridBattery)  // needed for "battery used"
        var fast: [UInt8] = []
        var slow: [UInt8] = []
        for metric in metrics {
            for pid in metric.info.requires where supported.isEmpty || supported.contains(pid) {
                if MetricCatalog.isFast(pid) {
                    if !fast.contains(pid) { fast.append(pid) }
                } else if !slow.contains(pid) {
                    slow.append(pid)
                }
            }
        }
        fast.sort()
        slow.sort()
        var out = fast
        if !slow.isEmpty { out.append(slow[cycle % slow.count]) }
        return out
    }

    private func handleReading(pid: UInt8, data: [UInt8]) {
        for info in MetricCatalog.metrics(forPID: pid) {
            if let value = info.decode(data) { ingest(info.id, value) }
        }
    }

    // MARK: - Values

    func ingest(_ metric: MetricID, _ value: Double) {
        store(metric, value)
        switch metric {
        case .rpm:
            updateDriveMode(rpm: value)
        case .hybridBattery:
            if tripStartBattery == nil { tripStartBattery = value }
            if let start = tripStartBattery { store(.batteryUsed, max(0, start - value)) }
        default:
            break
        }
    }

    private func store(_ metric: MetricID, _ value: Double) {
        values[metric] = value
        let now = Date()
        if now.timeIntervalSince(lastHistoryDate[metric] ?? .distantPast) >= Self.historyInterval {
            lastHistoryDate[metric] = now
            var points = history[metric] ?? []
            points.append(value)
            if points.count > Self.historyLimit { points.removeFirst(points.count - Self.historyLimit) }
            history[metric] = points
        }
        checkAlerts(metric, value)
    }

    private func updateDriveMode(rpm: Double) {
        let engineRunning = rpm > 300
        let now = Date()
        if let last = lastRPMDate {
            let dt = min(now.timeIntervalSince(last), 5)
            if engineRunning { engineSeconds += dt } else { evSeconds += dt }
        }
        lastRPMDate = now
        store(.driveMode, engineRunning ? 0 : 1)
        let total = evSeconds + engineSeconds
        if total > 0 { store(.evShare, evSeconds / total * 100) }
    }

    func isSupported(_ metric: MetricID) -> Bool {
        guard source == .obd, !obd.supportedPIDs.isEmpty else { return true }
        return metric.info.requires.allSatisfy { obd.supportedPIDs.contains($0) }
    }

    /// Small line under large tiles.
    func caption(for tile: Tile) -> String? {
        switch tile.metric {
        case .hybridBattery:
            guard let start = tripStartBattery else { return nil }
            let used = values[.batteryUsed] ?? 0
            return "START \(Int(start.rounded()))% · USED \(Int(used.rounded()))%"
        case .evShare:
            return "EV \(Int(evSeconds / 60)) MIN · ENGINE \(Int(engineSeconds / 60)) MIN"
        default:
            let points = history[tile.metric] ?? []
            guard let lo = points.min(), let hi = points.max() else { return nil }
            let info = tile.metric.info
            return "MIN \(info.format(lo)) · MAX \(info.format(hi))"
        }
    }

    // MARK: - Alerts

    private func checkAlerts(_ metric: MetricID, _ value: Double) {
        let rule = currentLayout.tiles.first { $0.metric == metric && ($0.alertAbove != nil || $0.alertBelow != nil) }
        guard let rule else {
            if activeAlerts.contains(metric) { activeAlerts.remove(metric) }
            return
        }
        let high = rule.alertAbove.map { value > $0 } ?? false
        let low = rule.alertBelow.map { value < $0 } ?? false
        if high || low {
            guard !activeAlerts.contains(metric) else { return }
            activeAlerts.insert(metric)
            let info = metric.info
            latestAlert = AlertEvent(metric: metric,
                                     message: "\(info.name) \(high ? "High" : "Low") · \(info.format(value)) \(info.unit)")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else if activeAlerts.contains(metric) {
            activeAlerts.remove(metric)
        }
    }

    // MARK: - Trouble codes

    func refreshCodes() {
        guard !isReadingCodes else { return }
        if source == .demo {
            codes = DTCReport(milOn: false, stored: [], pending: [], date: Date())
            return
        }
        isReadingCodes = true
        Task {
            if let report = await obd.readTroubleCodes() { codes = report }
            isReadingCodes = false
        }
    }

    func clearCodes() {
        guard source == .obd, !isReadingCodes else { return }
        isReadingCodes = true
        Task {
            _ = await obd.clearTroubleCodes()
            isReadingCodes = false
            refreshCodes()
        }
    }
}
