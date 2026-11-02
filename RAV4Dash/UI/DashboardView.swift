import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @State private var showConnect = false
    @State private var showCodes = false
    @State private var showAdd = false
    @State private var showLayouts = false
    @State private var editingTile: Tile?

    private let spacing: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let columns = landscape ? 4 : 2
            let barHeight: CGFloat = landscape ? 44 : 100
            let colWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let rowHeight = landscape
                ? max((geo.size.height - barHeight - spacing * 2) / 2, 120)
                : colWidth * 0.9

            VStack(spacing: spacing) {
                TopBar(landscape: landscape,
                       showConnect: $showConnect,
                       showCodes: $showCodes,
                       showAdd: $showAdd,
                       showLayouts: $showLayouts)
                    .frame(height: barHeight)

                ScrollView(.vertical, showsIndicators: false) {
                    TileGrid(tiles: model.currentLayout.tiles,
                             columns: columns,
                             rowHeight: rowHeight,
                             spacing: spacing,
                             onEditTile: { editingTile = $0 })
                    if model.isEditing {
                        Button {
                            showAdd = true
                        } label: {
                            Label("ADD GAUGE", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ChipButtonStyle())
                        .padding(.top, spacing)
                    }
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                    model.draggingTileID = nil
                    return true
                }
            }
        }
        .padding(16)
        .background(Theme.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onChange(of: model.isEditing) { _, editing in
            if !editing { model.draggingTileID = nil }
        }
        .sheet(isPresented: $showConnect) {
            ConnectView(obd: model.obd).environmentObject(model)
        }
        .sheet(isPresented: $showCodes) {
            CodesView().environmentObject(model)
        }
        .sheet(isPresented: $showAdd) {
            AddGaugeSheet().environmentObject(model)
        }
        .sheet(isPresented: $showLayouts) {
            LayoutsSheet().environmentObject(model)
        }
        .sheet(item: $editingTile) { tile in
            NavigationStack {
                TileSettingsView(tile: tile, isNew: false) { updated in
                    model.updateTile(updated)
                }
            }
            .environmentObject(model)
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    let landscape: Bool
    @Binding var showConnect: Bool
    @Binding var showCodes: Bool
    @Binding var showAdd: Bool
    @Binding var showLayouts: Bool

    var body: some View {
        if landscape {
            HStack(spacing: 12) {
                ConnectionPill(obd: model.obd) { showConnect = true }
                Spacer(minLength: 8)
                LayoutTabs()
                Spacer(minLength: 8)
                actions
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ConnectionPill(obd: model.obd) { showConnect = true }
                    Spacer(minLength: 8)
                    actions
                }
                LayoutTabs()
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if model.isEditing {
                Button { showLayouts = true } label: { Text("LAYOUTS") }
                    .buttonStyle(ChipButtonStyle())
                Button { model.isEditing = false } label: { Text("DONE") }
                    .buttonStyle(ChipButtonStyle(filled: true))
            } else {
                Button { showCodes = true } label: { codesLabel }
                    .buttonStyle(ChipButtonStyle())
                    .accessibilityLabel("Trouble codes")
                Button { withAnimation { model.isEditing = true } } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 20)
                }
                .buttonStyle(ChipButtonStyle())
                .accessibilityLabel("Edit layout")
            }
        }
    }

    @ViewBuilder
    private var codesLabel: some View {
        if let codes = model.codes {
            let count = codes.stored.count + codes.pending.count
            HStack(spacing: 6) {
                Image(systemName: count == 0 && !codes.milOn ? "checkmark" : "exclamationmark.triangle.fill")
                    .foregroundStyle(count == 0 && !codes.milOn ? Theme.ev : Theme.warn)
                Text("\(count) CODES")
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "stethoscope")
                Text("CODES")
            }
        }
    }
}

struct ConnectionPill: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var obd: OBDSession
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.tech(14))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.tech(14))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Theme.panel))
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if model.source == .demo { return "DEMO MODE" }
        switch obd.state {
        case .connected: return (obd.adapterName ?? "ADAPTER").uppercased()
        case .connecting, .initializing: return "CONNECTING…"
        case .scanning: return "SEARCHING…"
        case .bluetoothOff: return "BLUETOOTH OFF"
        case .unauthorized: return "ALLOW BLUETOOTH"
        case .failed: return "TAP TO RETRY"
        case .idle: return "CONNECT ADAPTER"
        }
    }

    private var detail: String? {
        guard model.source != .demo, obd.state.isConnected else { return nil }
        return obd.readsPerSecond > 0 ? String(format: "%.0f/S", obd.readsPerSecond) : "LIVE"
    }

    private var icon: String {
        model.source == .demo ? "play.circle.fill" : "antenna.radiowaves.left.and.right"
    }

    private var color: Color {
        if model.source == .demo { return Theme.warn }
        switch obd.state {
        case .connected: return Theme.ev
        case .failed, .bluetoothOff, .unauthorized: return Theme.danger
        default: return Theme.accent
        }
    }
}

struct LayoutTabs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.layouts) { layout in
                    let selected = layout.id == model.selectedLayoutID
                    Button {
                        withAnimation { model.selectedLayoutID = layout.id }
                    } label: {
                        Text(layout.name.uppercased())
                            .font(.tech(15))
                            .tracking(1.6)
                            .foregroundStyle(selected ? Theme.onAccent : Theme.label)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Capsule().fill(selected ? Theme.accent : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
}
