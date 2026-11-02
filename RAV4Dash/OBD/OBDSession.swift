import Foundation
import Combine
import CoreBluetooth

struct DiscoveredAdapter: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var looksLikeOBD: Bool
}

enum OBDError: Error {
    case notConnected
    case busy
    case timeout
}

/// Talks to a Bluetooth LE ELM327 adapter (like the Veepeak OBDCheck BLE):
/// finds it, connects, sets it up, then reads PIDs in a loop.
/// CoreBluetooth calls back on the main queue, so all state lives on the main actor.
@MainActor
final class OBDSession: NSObject, ObservableObject {
    enum State: Equatable {
        case bluetoothOff
        case unauthorized
        case idle
        case scanning
        case connecting(String)
        case initializing(String)
        case connected
        case failed(String)

        var isConnected: Bool { self == .connected }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var adapters: [DiscoveredAdapter] = []
    @Published private(set) var adapterName: String?
    @Published private(set) var elmVersion: String?
    @Published private(set) var protocolName: String?
    @Published private(set) var supportedPIDs: Set<UInt8> = []
    @Published private(set) var readsPerSecond: Double = 0

    /// Which PIDs to read on a given poll cycle.
    var pidProvider: ((Int) -> [UInt8])?
    /// Called with the data bytes of each successful mode 01 reply.
    var onReading: ((UInt8, [UInt8]) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var servicesLeft = 0
    private var rxBuffer = ""
    private var pending: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var jobs: [() async -> Void] = []
    private var wantsScan = false
    private var userDisconnected = false
    private var initStarted = false

    private static let savedKey = "obd.lastAdapter"

    /// Services used by common BLE OBD adapters, tried first.
    private static let preferredServices: [CBUUID] = [
        CBUUID(string: "FFF0"),
        CBUUID(string: "FFE0"),
        CBUUID(string: "18F0"),
        CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    ]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public controls

    var hasSavedAdapter: Bool {
        UserDefaults.standard.string(forKey: Self.savedKey) != nil
    }

    func startScan() {
        wantsScan = true
        guard central.state == .poweredOn else { return }
        guard !central.isScanning else { return }
        adapters.removeAll()
        if case .idle = state { state = .scanning }
        if case .failed = state { state = .scanning }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        wantsScan = false
        if central.isScanning { central.stopScan() }
        if state == .scanning { state = .idle }
    }

    func connect(to id: UUID) {
        let known = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let p = known else { return }
        stopScan()
        if let old = peripheral, old.identifier != p.identifier {
            central.cancelPeripheralConnection(old)
        }
        userDisconnected = false
        peripheral = p
        peripherals[p.identifier] = p
        p.delegate = self
        adapterName = p.name ?? "OBD adapter"
        state = .connecting(adapterName ?? "adapter")
        central.connect(p, options: nil)
    }

    func disconnect() {
        userDisconnected = true
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        teardown(newState: .idle)
    }

    /// Reads check-engine status plus stored and pending codes.
    func readTroubleCodes() async -> DTCReport? {
        guard state.isConnected else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<DTCReport?, Never>) in
            jobs.append { [weak self] in
                let report = await self?.performReadCodes()
                cont.resume(returning: report)
            }
        }
    }

    /// Clears stored codes and turns off the check engine light (mode 04).
    func clearTroubleCodes() async -> Bool {
        guard state.isConnected else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            jobs.append { [weak self] in
                guard let self else { cont.resume(returning: false); return }
                let reply = try? await self.send("04", timeout: 6)
                cont.resume(returning: reply?.contains("44") ?? false)
            }
        }
    }

    // MARK: - Commands

    /// Sends one command and waits for the ">" prompt.
    func send(_ command: String, timeout: TimeInterval = 2.5) async throws -> String {
        guard let p = peripheral, let w = writeChar else { throw OBDError.notConnected }
        guard pending == nil else { throw OBDError.busy }
        rxBuffer = ""
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            pending = cont
            p.writeValue(Data((command + "\r").utf8), for: w, type: writeType)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(OBDError.timeout))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let cont = pending else { return }
        pending = nil
        if case .failure = result { rxBuffer = "" }
        cont.resume(with: result)
    }

    private func handleIncoming(_ data: Data) {
        let clean = Data(data.filter { $0 != 0 })
        guard let text = String(data: clean, encoding: .ascii) ?? String(data: clean, encoding: .utf8) else { return }
        rxBuffer += text
        if let idx = rxBuffer.firstIndex(of: ">") {
            let reply = String(rxBuffer[..<idx])
            rxBuffer = String(rxBuffer[rxBuffer.index(after: idx)...])
            finish(.success(reply))
        }
    }

    // MARK: - Setup and polling

    private func initializeAdapter() async {
        do {
            state = .initializing("Resetting adapter")
            let reset = try await send("ATZ", timeout: 4)
            elmVersion = ELMParser.lines(reset).first { $0.uppercased().contains("ELM") }
            for command in ["ATE0", "ATL0", "ATS0", "ATH0", "ATAT1", "ATSP0"] {
                _ = try? await send(command)
            }

            state = .initializing("Talking to the car")
            let first = try await send("0100", timeout: 12)
            var supported = ELMParser.supportedPIDs(first, base: 0x00)
            if supported.isEmpty {
                state = .failed("No reply from the car. Make sure it's on (READY), then try again.")
                return
            }

            state = .initializing("Reading supported sensors")
            var base: UInt8 = 0x20
            while supported.contains(base) && base <= 0xC0 {
                if let more = try? await send("01" + ELMParser.hex2(base), timeout: 3) {
                    supported.formUnion(ELMParser.supportedPIDs(more, base: base))
                }
                base &+= 0x20
            }
            supportedPIDs = supported

            if let dp = try? await send("ATDP") {
                protocolName = ELMParser.lines(dp).first?.replacingOccurrences(of: "AUTO, ", with: "")
            }
            state = .connected
            startPolling()
        } catch {
            state = .failed("The adapter didn't answer. Unplug it, plug it back in, and try again.")
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var cycle = 0
            var reads = 0
            var windowStart = Date()
            var timeouts = 0
            while !Task.isCancelled {
                guard let self else { return }

                while !self.jobs.isEmpty {
                    let job = self.jobs.removeFirst()
                    await job()
                }

                let pids = self.pidProvider?(cycle) ?? []
                if pids.isEmpty {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }

                for pid in pids {
                    if Task.isCancelled { return }
                    do {
                        let raw = try await self.send("01" + ELMParser.hex2(pid))
                        timeouts = 0
                        if let data = ELMParser.mode01Data(raw, pid: pid) {
                            self.onReading?(pid, data)
                            reads += 1
                        }
                    } catch OBDError.timeout {
                        timeouts += 1
                        if timeouts >= 4 {
                            self.handleLostLink()
                            return
                        }
                    } catch OBDError.notConnected {
                        return
                    } catch {
                        continue
                    }
                }

                cycle += 1
                let elapsed = Date().timeIntervalSince(windowStart)
                if elapsed >= 2 {
                    self.readsPerSecond = Double(reads) / elapsed
                    reads = 0
                    windowStart = Date()
                }
            }
        }
    }

    private func performReadCodes() async -> DTCReport? {
        do {
            let status = try await send("0101")
            // Any ECU can turn on the check engine light, so check every reply.
            let milOn = ELMParser.allMode01Data(status, pid: 0x01).contains { ($0.first ?? 0) & 0x80 != 0 }
            let stored = try await send("03", timeout: 4)
            let pendingReply = try await send("07", timeout: 4)
            return DTCReport(milOn: milOn,
                             stored: ELMParser.troubleCodes(stored, responseByte: 0x43),
                             pending: ELMParser.troubleCodes(pendingReply, responseByte: 0x47),
                             date: Date())
        } catch {
            return nil
        }
    }

    private func handleLostLink() {
        state = .failed("Lost contact with the adapter. Reconnecting…")
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    private func teardown(newState: State) {
        pollTask?.cancel()
        pollTask = nil
        finish(.failure(OBDError.notConnected))
        writeChar = nil
        notifyChar = nil
        initStarted = false
        supportedPIDs = []
        protocolName = nil
        readsPerSecond = 0
        state = newState
        let leftover = jobs
        jobs = []
        if !leftover.isEmpty {
            Task { for job in leftover { await job() } }
        }
    }

    // MARK: - CoreBluetooth events (already on the main queue)

    private func bluetoothStateChanged() {
        switch central.state {
        case .poweredOn:
            if state == .bluetoothOff || state == .unauthorized { state = .idle }
            if peripheral == nil,
               let saved = UserDefaults.standard.string(forKey: Self.savedKey),
               let id = UUID(uuidString: saved) {
                connect(to: id)
            } else if wantsScan {
                startScan()
            }
        case .unauthorized:
            state = .unauthorized
        case .poweredOff:
            teardown(newState: .bluetoothOff)
        default:
            break
        }
    }

    private func discovered(_ p: CBPeripheral, name: String?, rssi: Int) {
        guard let name, !name.isEmpty, rssi < 0 else { return }
        peripherals[p.identifier] = p
        if let i = adapters.firstIndex(where: { $0.id == p.identifier }) {
            adapters[i].rssi = rssi
            adapters[i].name = name
            return
        }
        let upper = name.uppercased()
        let hints = ["OBD", "ELM", "VEEPEAK", "VLINK", "V-LINK", "CHECK", "VGATE", "SCAN"]
        let looksLikeOBD = hints.contains { upper.contains($0) }
        adapters.append(DiscoveredAdapter(id: p.identifier, name: name, rssi: rssi, looksLikeOBD: looksLikeOBD))
        adapters.sort { ($0.looksLikeOBD ? 1 : 0, $0.rssi) > ($1.looksLikeOBD ? 1 : 0, $1.rssi) }
    }

    private func didConnect(_ p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedKey)
        adapterName = p.name ?? adapterName
        state = .initializing("Opening adapter")
        p.discoverServices(nil)
    }

    private func didDiscoverServices(_ p: CBPeripheral) {
        let services = p.services ?? []
        servicesLeft = services.count
        if services.isEmpty {
            state = .failed("This doesn't look like an OBD adapter.")
            central.cancelPeripheralConnection(p)
            return
        }
        for s in services { p.discoverCharacteristics(nil, for: s) }
    }

    private func didDiscoverCharacteristics(_ p: CBPeripheral) {
        servicesLeft -= 1
        guard servicesLeft <= 0 else { return }
        let services = (p.services ?? []).sorted { a, b in
            (Self.preferredServices.firstIndex(of: a.uuid) ?? 99) < (Self.preferredServices.firstIndex(of: b.uuid) ?? 99)
        }
        for s in services {
            let chars = s.characteristics ?? []
            let notify = chars.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
            let write = chars.first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
            if let notify, let write {
                notifyChar = notify
                writeChar = write
                writeType = write.properties.contains(.write) ? .withResponse : .withoutResponse
                p.setNotifyValue(true, for: notify)
                return
            }
        }
        state = .failed("This doesn't look like an OBD adapter.")
        central.cancelPeripheralConnection(p)
    }

    private func notificationsReady(_ characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == notifyChar else { return }
        if error != nil || !characteristic.isNotifying {
            state = .failed("Couldn't open the adapter. Try again.")
            return
        }
        guard !initStarted else { return }
        initStarted = true
        Task { await self.initializeAdapter() }
    }

    private func didDisconnect(_ p: CBPeripheral) {
        // Ignore an old adapter dropping off after switching to a different one.
        guard p.identifier == peripheral?.identifier else { return }
        let byUser = userDisconnected
        teardown(newState: byUser ? .idle : .connecting(adapterName ?? "adapter"))
        guard !byUser else { return }
        // Waits quietly and reconnects when the adapter is back (for example, next time the car starts).
        central.connect(p, options: nil)
    }
}

extension OBDSession: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { self.bluetoothStateChanged() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let rssi = RSSI.intValue
        MainActor.assumeIsolated { self.discovered(peripheral, name: name, rssi: rssi) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { self.didConnect(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { self.state = .failed("Couldn't connect. Make sure the adapter is plugged in.") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { self.didDisconnect(peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { self.didDiscoverServices(peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated { self.didDiscoverCharacteristics(peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { self.notificationsReady(characteristic, error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        MainActor.assumeIsolated { self.handleIncoming(value) }
    }
}
