import Foundation

/// Groups shown in the "Add gauge" picker.
enum MetricCategory: String, CaseIterable, Identifiable {
    case hybrid = "Hybrid & EV"
    case engine = "Engine"
    case temperatures = "Temperatures"
    case fuel = "Fuel & Air"
    case electrical = "Electrical"

    var id: String { rawValue }
}

/// How a tile draws its value.
enum GaugeStyle: String, CaseIterable, Codable, Identifiable {
    case ring, arc, bar, digital, graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ring: return "Ring"
        case .arc: return "Arc"
        case .bar: return "Bar"
        case .digital: return "Digital"
        case .graph: return "Graph"
        }
    }
}

/// Every stat the app can show. Raw values are saved in layouts, so don't rename them.
enum MetricID: String, CaseIterable, Codable, Identifiable {
    case hybridBattery, driveMode, evShare, batteryUsed
    case fuelLevel, fuelRate, maf, manifoldPressure
    case coolant, intakeAir, ambient
    case voltage
    case rpm, throttle, load, runTime

    var id: String { rawValue }
    var info: MetricInfo { MetricCatalog.info(for: self) }
}

struct MetricInfo {
    let id: MetricID
    let name: String
    let unit: String
    let category: MetricCategory
    /// Standard OBD-II mode 01 PID, or nil when the app works the value out itself.
    let pid: UInt8?
    /// PIDs that must be read for this stat to have a value.
    let requires: [UInt8]
    let range: ClosedRange<Double>
    let decimals: Int
    /// Fast stats are read every cycle; slow ones take turns.
    let fast: Bool
    let styles: [GaugeStyle]
    let decode: ([UInt8]) -> Double?
    let detail: String

    var label: String { name.uppercased() }

    func fraction(_ value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        if id == .driveMode { return value >= 0.5 ? "EV" : "ENGINE" }
        return String(format: "%.\(decimals)f", value)
    }
}

enum MetricCatalog {
    private static func percent(_ d: [UInt8]) -> Double? {
        d.count >= 1 ? Double(d[0]) * 100 / 255 : nil
    }

    private static func fahrenheit(_ d: [UInt8]) -> Double? {
        d.count >= 1 ? (Double(d[0]) - 40) * 9 / 5 + 32 : nil
    }

    private static func word(_ d: [UInt8]) -> Double? {
        d.count >= 2 ? Double(d[0]) * 256 + Double(d[1]) : nil
    }

    private static let derived: ([UInt8]) -> Double? = { _ in nil }

    static let all: [MetricInfo] = [
        MetricInfo(id: .hybridBattery, name: "Hybrid Battery", unit: "%", category: .hybrid,
                   pid: 0x5B, requires: [0x5B], range: 0...100, decimals: 0, fast: false,
                   styles: [.ring, .arc, .bar, .digital, .graph], decode: percent,
                   detail: "Charge left in the hybrid battery (PID 5B). Some cars don't report it."),
        MetricInfo(id: .driveMode, name: "Drive Mode", unit: "", category: .hybrid,
                   pid: nil, requires: [0x0C], range: 0...1, decimals: 0, fast: true,
                   styles: [.digital], decode: derived,
                   detail: "EV when the gas engine is off, ENGINE when it's running."),
        MetricInfo(id: .evShare, name: "EV Share", unit: "%", category: .hybrid,
                   pid: nil, requires: [0x0C], range: 0...100, decimals: 0, fast: true,
                   styles: [.ring, .arc, .bar, .digital], decode: derived,
                   detail: "Share of this trip driven with the engine off."),
        MetricInfo(id: .batteryUsed, name: "Battery Used", unit: "%", category: .hybrid,
                   pid: nil, requires: [0x5B], range: 0...100, decimals: 0, fast: false,
                   styles: [.digital, .bar, .ring], decode: derived,
                   detail: "Hybrid battery used since this trip started."),

        MetricInfo(id: .fuelLevel, name: "Fuel Level", unit: "%", category: .fuel,
                   pid: 0x2F, requires: [0x2F], range: 0...100, decimals: 0, fast: false,
                   styles: [.bar, .ring, .arc, .digital], decode: percent,
                   detail: "Fuel tank level."),
        MetricInfo(id: .fuelRate, name: "Fuel Rate", unit: "gal/h", category: .fuel,
                   pid: 0x5E, requires: [0x5E], range: 0...3, decimals: 2, fast: true,
                   styles: [.digital, .graph, .arc, .bar], decode: { d in word(d).map { $0 / 20 * 0.264172 } },
                   detail: "How fast the engine is burning fuel right now."),
        MetricInfo(id: .maf, name: "Air Flow", unit: "g/s", category: .fuel,
                   pid: 0x10, requires: [0x10], range: 0...120, decimals: 1, fast: true,
                   styles: [.graph, .digital, .arc, .bar], decode: { d in word(d).map { $0 / 100 } },
                   detail: "Mass air flow into the engine."),
        MetricInfo(id: .manifoldPressure, name: "Manifold Pressure", unit: "psi", category: .fuel,
                   pid: 0x0B, requires: [0x0B], range: 0...16, decimals: 1, fast: true,
                   styles: [.arc, .digital, .graph, .bar], decode: { d in d.first.map { Double($0) * 0.145038 } },
                   detail: "Intake manifold absolute pressure."),

        MetricInfo(id: .coolant, name: "Coolant", unit: "°F", category: .temperatures,
                   pid: 0x05, requires: [0x05], range: 100...260, decimals: 0, fast: false,
                   styles: [.bar, .arc, .ring, .digital, .graph], decode: fahrenheit,
                   detail: "Engine coolant temperature."),
        MetricInfo(id: .intakeAir, name: "Intake Air", unit: "°F", category: .temperatures,
                   pid: 0x0F, requires: [0x0F], range: 0...160, decimals: 0, fast: false,
                   styles: [.digital, .bar, .arc, .graph], decode: fahrenheit,
                   detail: "Air temperature entering the engine."),
        MetricInfo(id: .ambient, name: "Outside", unit: "°F", category: .temperatures,
                   pid: 0x46, requires: [0x46], range: -20...120, decimals: 0, fast: false,
                   styles: [.digital, .bar, .arc], decode: fahrenheit,
                   detail: "Outside air temperature."),

        MetricInfo(id: .voltage, name: "12V Battery", unit: "V", category: .electrical,
                   pid: 0x42, requires: [0x42], range: 10...16, decimals: 1, fast: false,
                   styles: [.graph, .digital, .arc, .bar], decode: { d in word(d).map { $0 / 1000 } },
                   detail: "12-volt system voltage."),

        MetricInfo(id: .rpm, name: "Engine RPM", unit: "rpm", category: .engine,
                   pid: 0x0C, requires: [0x0C], range: 0...6000, decimals: 0, fast: true,
                   styles: [.ring, .arc, .bar, .digital, .graph], decode: { d in word(d).map { $0 / 4 } },
                   detail: "Gas engine speed. 0 when running on electric."),
        MetricInfo(id: .throttle, name: "Throttle", unit: "%", category: .engine,
                   pid: 0x11, requires: [0x11], range: 0...100, decimals: 0, fast: true,
                   styles: [.bar, .ring, .arc, .digital, .graph], decode: percent,
                   detail: "Throttle position."),
        MetricInfo(id: .load, name: "Engine Load", unit: "%", category: .engine,
                   pid: 0x04, requires: [0x04], range: 0...100, decimals: 0, fast: true,
                   styles: [.bar, .ring, .arc, .digital, .graph], decode: percent,
                   detail: "Calculated engine load."),
        MetricInfo(id: .runTime, name: "Engine Run Time", unit: "min", category: .engine,
                   pid: 0x1F, requires: [0x1F], range: 0...120, decimals: 0, fast: false,
                   styles: [.digital], decode: { d in word(d).map { $0 / 60 } },
                   detail: "Minutes since the engine started.")
    ]

    private static let byID: [MetricID: MetricInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func info(for id: MetricID) -> MetricInfo {
        guard let info = byID[id] else { fatalError("Missing catalog entry for \(id)") }
        return info
    }

    /// True if any stat that reads this PID wants frequent updates.
    static func isFast(_ pid: UInt8) -> Bool {
        all.contains { $0.pid == pid && $0.fast }
    }

    /// Metrics decoded directly from this PID's reply.
    static func metrics(forPID pid: UInt8) -> [MetricInfo] {
        all.filter { $0.pid == pid }
    }
}
