import Foundation

enum TileSize: String, Codable, CaseIterable, Identifiable {
    case small, wide, large

    var id: String { rawValue }
    var columns: Int { self == .small ? 1 : 2 }
    var rows: Int { self == .large ? 2 : 1 }

    var title: String {
        switch self {
        case .small: return "1×1"
        case .wide: return "2×1"
        case .large: return "2×2"
        }
    }

    var next: TileSize {
        switch self {
        case .small: return .wide
        case .wide: return .large
        case .large: return .small
        }
    }
}

struct Tile: Codable, Identifiable, Equatable {
    var id = UUID()
    var metric: MetricID
    var style: GaugeStyle
    var size: TileSize
    var alertAbove: Double?
    var alertBelow: Double?
}

struct DashLayout: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var tiles: [Tile]
}

extension DashLayout {
    static var defaults: [DashLayout] {
        [
            DashLayout(name: "Drive", tiles: [
                Tile(metric: .hybridBattery, style: .ring, size: .large),
                Tile(metric: .fuelLevel, style: .bar, size: .small),
                Tile(metric: .evShare, style: .bar, size: .small),
                Tile(metric: .coolant, style: .bar, size: .small, alertAbove: 230),
                Tile(metric: .voltage, style: .graph, size: .small, alertBelow: 11.8),
                Tile(metric: .driveMode, style: .digital, size: .small),
                Tile(metric: .ambient, style: .digital, size: .small),
                Tile(metric: .throttle, style: .digital, size: .small),
                Tile(metric: .fuelRate, style: .digital, size: .small)
            ]),
            DashLayout(name: "Efficiency", tiles: [
                Tile(metric: .hybridBattery, style: .graph, size: .wide),
                Tile(metric: .evShare, style: .ring, size: .small),
                Tile(metric: .driveMode, style: .digital, size: .small),
                Tile(metric: .fuelRate, style: .graph, size: .wide),
                Tile(metric: .batteryUsed, style: .digital, size: .small),
                Tile(metric: .fuelLevel, style: .arc, size: .small)
            ]),
            DashLayout(name: "Engine", tiles: [
                Tile(metric: .rpm, style: .ring, size: .large),
                Tile(metric: .coolant, style: .arc, size: .small, alertAbove: 230),
                Tile(metric: .load, style: .bar, size: .small),
                Tile(metric: .throttle, style: .bar, size: .small),
                Tile(metric: .intakeAir, style: .digital, size: .small),
                Tile(metric: .maf, style: .graph, size: .wide),
                Tile(metric: .runTime, style: .digital, size: .small),
                Tile(metric: .manifoldPressure, style: .digital, size: .small)
            ])
        ]
    }
}

/// Where a tile sits on the dashboard grid.
struct GridSlot: Equatable {
    let col: Int
    let row: Int
    let width: Int
    let height: Int
}

enum GridPacker {
    /// Places tiles in order, each in the first free spot that fits (top to bottom, left to right).
    static func pack(_ sizes: [TileSize], columns: Int) -> (slots: [GridSlot], rows: Int) {
        let columns = max(columns, 1)
        var taken = Set<Int>()   // row * columns + col
        var slots: [GridSlot] = []
        var rowCount = 0

        func fits(_ col: Int, _ row: Int, _ w: Int, _ h: Int) -> Bool {
            for r in row..<(row + h) {
                for c in col..<(col + w) where taken.contains(r * columns + c) {
                    return false
                }
            }
            return true
        }

        for size in sizes {
            let w = min(size.columns, columns)
            let h = size.rows
            var row = 0
            var placed = false
            while !placed {
                for col in 0...(columns - w) where fits(col, row, w, h) {
                    for r in row..<(row + h) {
                        for c in col..<(col + w) { taken.insert(r * columns + c) }
                    }
                    slots.append(GridSlot(col: col, row: row, width: w, height: h))
                    rowCount = max(rowCount, row + h)
                    placed = true
                    break
                }
                row += 1
            }
        }
        return (slots, rowCount)
    }
}
