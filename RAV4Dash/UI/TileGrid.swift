import SwiftUI
import UniformTypeIdentifiers

/// Lays tiles out on a grid where tiles can span 1 or 2 columns and rows.
struct TileGrid: View {
    @EnvironmentObject var model: AppModel
    let tiles: [Tile]
    let columns: Int
    let rowHeight: CGFloat
    var spacing: CGFloat = 12
    var onEditTile: (Tile) -> Void = { _ in }

    var body: some View {
        let packed = GridPacker.pack(tiles.map(\.size), columns: columns)
        let rows = max(packed.rows, 1)
        let height = rowHeight * CGFloat(rows) + spacing * CGFloat(rows - 1)

        GeometryReader { geo in
            let colWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    let slot = packed.slots[index]
                    let w = colWidth * CGFloat(slot.width) + spacing * CGFloat(slot.width - 1)
                    let h = rowHeight * CGFloat(slot.height) + spacing * CGFloat(slot.height - 1)
                    TileCell(tile: tile, onEdit: { onEditTile(tile) })
                        .frame(width: w, height: h)
                        .offset(x: CGFloat(slot.col) * (colWidth + spacing),
                                y: CGFloat(slot.row) * (rowHeight + spacing))
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .topLeading)
        }
        .frame(height: height)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tiles)
    }
}

/// A tile plus its edit-mode controls.
struct TileCell: View {
    @EnvironmentObject var model: AppModel
    let tile: Tile
    var onEdit: () -> Void

    var body: some View {
        let base = TileView(tile: tile,
                            value: model.values[tile.metric],
                            history: model.history[tile.metric] ?? [],
                            alerting: model.activeAlerts.contains(tile.metric),
                            supported: model.isSupported(tile.metric),
                            caption: model.caption(for: tile))

        if model.isEditing {
            base
                .opacity(model.draggingTileID == tile.id ? 0.35 : 0.85)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation { model.removeTile(tile.id) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.lineStrong))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove \(tile.metric.info.name)")
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        withAnimation { model.cycleSize(tile.id) }
                    } label: {
                        Text(tile.size.title)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.panelRaised))
                            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(4)
                    .accessibilityLabel("Change size, now \(tile.size.title)")
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { onEdit() }
                .onDrag {
                    model.draggingTileID = tile.id
                    return NSItemProvider(object: tile.id.uuidString as NSString)
                }
                .onDrop(of: [UTType.text], delegate: TileDropDelegate(targetID: tile.id, model: model))
        } else {
            base
        }
    }
}

struct TileDropDelegate: DropDelegate {
    let targetID: UUID
    let model: AppModel

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            withAnimation { model.moveDraggedTile(onto: targetID) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { model.draggingTileID = nil }
        return true
    }
}
