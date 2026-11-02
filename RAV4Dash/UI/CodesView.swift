import SwiftUI

struct CodesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                if model.source == .none {
                    Section {
                        Text("Connect the adapter to read trouble codes.")
                            .foregroundStyle(Theme.label)
                    }
                    .listRowBackground(Theme.panel)
                } else if let codes = model.codes {
                    Section {
                        LabeledContent("Check engine light") {
                            Text(codes.milOn ? "On" : "Off")
                                .foregroundStyle(codes.milOn ? Theme.warn : Theme.ev)
                        }
                        LabeledContent("Last scan", value: codes.date.formatted(date: .omitted, time: .shortened))
                        if model.source == .demo {
                            Text("Demo mode: sample result").font(.caption).foregroundStyle(Theme.warn)
                        }
                    }
                    .listRowBackground(Theme.panel)

                    Section("Stored codes") {
                        codeList(codes.stored)
                    }
                    .listRowBackground(Theme.panel)

                    Section("Pending codes") {
                        codeList(codes.pending)
                    }
                    .listRowBackground(Theme.panel)

                    if model.source == .obd {
                        Section {
                            Button("Clear codes…", role: .destructive) { confirmClear = true }
                        } footer: {
                            Text("Clearing turns off the check engine light and resets the emissions readiness checks. Only clear codes after the problem is fixed.")
                        }
                        .listRowBackground(Theme.panel)
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading codes…").foregroundStyle(Theme.label)
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Trouble Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Re-scan") { model.refreshCodes() }
                        .disabled(model.source == .none || model.isReadingCodes)
                }
            }
            .confirmationDialog("Clear all trouble codes?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear codes", role: .destructive) { model.clearCodes() }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.refreshCodes() }
    }

    @ViewBuilder
    private func codeList(_ list: [String]) -> some View {
        if list.isEmpty {
            Text("None").foregroundStyle(Theme.label)
        } else {
            ForEach(list, id: \.self) { code in
                HStack {
                    Text(code).font(.system(.body, design: .monospaced).weight(.semibold))
                    Spacer()
                    if let url = URL(string: "https://www.google.com/search?q=\(code)+Toyota+RAV4") {
                        Link("Look up", destination: url)
                    }
                }
            }
        }
    }
}
