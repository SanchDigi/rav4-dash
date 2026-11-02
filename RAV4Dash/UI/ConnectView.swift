import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var obd: OBDSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow
                }
                .listRowBackground(Theme.panel)

                if obd.state.isConnected {
                    Section("Connection") {
                        LabeledContent("Adapter", value: obd.adapterName ?? "—")
                        LabeledContent("Chip", value: obd.elmVersion ?? "—")
                        LabeledContent("Car protocol", value: obd.protocolName ?? "—")
                        LabeledContent("Sensors reported", value: "\(obd.supportedPIDs.count)")
                        LabeledContent("Reads per second", value: String(format: "%.1f", obd.readsPerSecond))
                    }
                    .listRowBackground(Theme.panel)

                    Section {
                        Button("Disconnect and forget adapter", role: .destructive) { obd.disconnect() }
                    }
                    .listRowBackground(Theme.panel)
                } else {
                    Section {
                        if obd.adapters.isEmpty {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Looking for adapters…").foregroundStyle(Theme.label)
                            }
                        }
                        ForEach(obd.adapters) { adapter in
                            Button {
                                obd.connect(to: adapter.id)
                            } label: {
                                AdapterRow(adapter: adapter)
                            }
                        }
                    } header: {
                        Text("Nearby Bluetooth devices")
                    } footer: {
                        Text("Plug the Veepeak into the OBD-II port under the steering wheel and turn the RAV4 on (READY). Then tap the adapter here. You don't need to pair it in iPhone Settings.")
                    }
                    .listRowBackground(Theme.panel)
                }

                Section {
                    if model.source == .demo {
                        Button("Stop demo mode") { model.stopDemo() }
                    } else {
                        Button("Try demo mode (no car needed)") {
                            model.startDemo()
                            dismiss()
                        }
                    }
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("OBD Adapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !obd.state.isConnected { obd.startScan() }
        }
        .onDisappear { obd.stopScan() }
    }

    private var statusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: statusIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.headline)
                if let statusDetail {
                    Text(statusDetail).font(.subheadline).foregroundStyle(Theme.label)
                }
            }
            Spacer()
            if case .initializing = obd.state { ProgressView() }
            if case .connecting = obd.state { ProgressView() }
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: String {
        switch obd.state {
        case .connected: return "Connected"
        case .connecting(let name): return "Connecting to \(name)"
        case .initializing: return "Setting up"
        case .scanning: return "Searching"
        case .idle: return "Not connected"
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth not allowed"
        case .failed: return "Couldn't connect"
        }
    }

    private var statusDetail: String? {
        switch obd.state {
        case .initializing(let step): return step
        case .failed(let message): return message
        case .unauthorized: return "Allow Bluetooth for RAV4 Dash in iPhone Settings."
        case .bluetoothOff: return "Turn on Bluetooth in Control Center."
        case .connecting: return "Waiting for the adapter. Is the car on?"
        default: return nil
        }
    }

    private var statusIcon: String {
        switch obd.state {
        case .connected: return "checkmark.circle.fill"
        case .failed, .bluetoothOff, .unauthorized: return "exclamationmark.triangle.fill"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        switch obd.state {
        case .connected: return Theme.ev
        case .failed, .bluetoothOff, .unauthorized: return Theme.danger
        default: return Theme.accent
        }
    }
}

struct AdapterRow: View {
    let adapter: DiscoveredAdapter

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(adapter.name).foregroundStyle(Theme.text)
                if adapter.looksLikeOBD {
                    Text("Looks like an OBD adapter").font(.caption).foregroundStyle(Theme.ev)
                }
            }
            Spacer()
            SignalBars(rssi: adapter.rssi)
            Text("\(adapter.rssi) dBm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.label)
        }
        .frame(minHeight: 44)
    }
}

struct SignalBars: View {
    let rssi: Int

    var body: some View {
        let level = rssi > -60 ? 4 : rssi > -70 ? 3 : rssi > -80 ? 2 : 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Theme.accent : Theme.lineStrong)
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityLabel("Signal \(level) of 4")
    }
}
