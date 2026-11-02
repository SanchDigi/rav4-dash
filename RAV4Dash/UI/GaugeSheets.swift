import SwiftUI

/// Pick a stat to add to the current layout.
struct AddGaugeSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(MetricCategory.allCases) { category in
                    Section(category.rawValue) {
                        ForEach(MetricCatalog.all.filter { $0.category == category }, id: \.id) { info in
                            NavigationLink {
                                TileSettingsView(tile: Tile(metric: info.id, style: info.styles[0], size: .small),
                                                 isNew: true) { tile in
                                    model.addTile(tile)
                                    dismiss()
                                }
                            } label: {
                                row(info)
                            }
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Add Gauge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ info: MetricInfo) -> some View {
        let inUse = model.currentLayout.tiles.contains { $0.metric == info.id }
        let supported = model.isSupported(info.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).foregroundStyle(supported ? Theme.text : Theme.faint)
                Text(info.detail).font(.caption).foregroundStyle(Theme.label).lineLimit(2)
            }
            Spacer()
            if !supported {
                Text("NOT REPORTED").techLabel(Theme.faint, size: 11)
            } else if inUse {
                Text("IN USE").techLabel(Theme.ev, size: 11)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Style, size and alert settings for one tile. Used for both adding and editing.
struct TileSettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var tile: Tile
    @State private var warnAbove: Bool
    @State private var aboveValue: Double
    @State private var warnBelow: Bool
    @State private var belowValue: Double
    private let isNew: Bool
    private let onSave: (Tile) -> Void

    init(tile: Tile, isNew: Bool, onSave: @escaping (Tile) -> Void) {
        let info = tile.metric.info
        let span = info.range.upperBound - info.range.lowerBound
        _tile = State(initialValue: tile)
        _warnAbove = State(initialValue: tile.alertAbove != nil)
        _aboveValue = State(initialValue: tile.alertAbove ?? (info.range.upperBound - span * 0.1).rounded())
        _warnBelow = State(initialValue: tile.alertBelow != nil)
        _belowValue = State(initialValue: tile.alertBelow ?? (info.range.lowerBound + span * 0.1).rounded())
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        let info = tile.metric.info
        Form {
            Section {
                TileView(tile: tile,
                         value: model.values[tile.metric],
                         history: model.history[tile.metric] ?? [],
                         supported: model.isSupported(tile.metric),
                         caption: model.caption(for: tile))
                    .frame(maxWidth: tile.size == .small ? 220 : .infinity)
                    .frame(height: tile.size == .large ? 260 : 170)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text(info.detail)
            }

            if info.styles.count > 1 {
                Section("Style") {
                    Picker("Style", selection: $tile.style) {
                        ForEach(info.styles) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Theme.panel)
            }

            Section("Size") {
                Picker("Size", selection: $tile.size) {
                    ForEach(TileSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Theme.panel)

            if tile.metric != .driveMode {
                Section {
                    Toggle("Warn above", isOn: $warnAbove)
                    if warnAbove { valueField($aboveValue, unit: info.unit) }
                    Toggle("Warn below", isOn: $warnBelow)
                    if warnBelow { valueField($belowValue, unit: info.unit) }
                } header: {
                    Text("Alert")
                } footer: {
                    Text("The tile turns red and your phone buzzes. In CarPlay a warning pops up.")
                }
                .listRowBackground(Theme.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .tint(Theme.accent)
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") { save() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func valueField(_ value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text("Limit").foregroundStyle(Theme.label)
            TextField("Value", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(Theme.label)
        }
    }

    private func save() {
        var result = tile
        result.alertAbove = warnAbove ? aboveValue : nil
        result.alertBelow = warnBelow ? belowValue : nil
        onSave(result)
        dismiss()
    }
}

/// Rename, add, delete and reorder layouts.
struct LayoutsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($model.layouts) { $layout in
                        HStack {
                            TextField("Name", text: $layout.name)
                            Text("\(layout.tiles.count) gauges")
                                .font(.caption)
                                .foregroundStyle(Theme.label)
                        }
                    }
                    .onDelete { model.deleteLayouts(at: $0) }
                    .onMove { model.moveLayouts(from: $0, to: $1) }
                } footer: {
                    Text("Tap a name to rename it. Swipe left to delete. Tap Edit to reorder.")
                }
                .listRowBackground(Theme.panel)

                Section {
                    Button("Add layout") { model.addLayout() }
                    Button("Reset to default layouts", role: .destructive) { confirmReset = true }
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Replace all layouts with the defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset layouts", role: .destructive) { model.resetLayouts() }
            }
        }
        .preferredColorScheme(.dark)
    }
}
