import ResetRadarApplication
import ResetRadarDomain
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case sources = "Sources"
    case relay = "Relay & Pairing"
    case diagnostics = "Diagnostics"
    case about = "About"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .sources: "externaldrive"
        case .relay: "network"
        case .diagnostics: "waveform.path.ecg"
        case .about: "info.circle"
        }
    }
}

struct SettingsRootView: View {
    let models: OwnerFlowModels?
    @ObservedObject var messages: GlobalMessageCenter
    let rebuildCollector: @MainActor () async -> Void
    @State private var selection = SettingsSection.general

    private let headerHeight: CGFloat = 60
    private let messagesHeight: CGFloat = 180

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    Text(selection.rawValue)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .frame(height: headerHeight)
                    Group {
                        if let models {
                            detail(models)
                        } else {
                            ProgressView("Starting collector…")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: max(0, geometry.size.height - headerHeight - messagesHeight))
                    .clipped()
                    GlobalMessagesPane(messages: messages)
                        .frame(height: messagesHeight, alignment: .bottom)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 1300, minHeight: 800)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(selection == section ? Color.white : Color.primary)
                .background(
                    selection == section ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func detail(_ models: OwnerFlowModels) -> some View {
        switch selection {
        case .general: GeneralSettingsView(model: models.general, recovery: models.recovery)
        case .sources:
            SourcesSettingsView(model: models.sources, rebuildCollector: rebuildCollector)
        case .relay:
            RelaySettingsView(
                relay: models.relay, pairing: models.pairing, devices: models.devices)
        case .diagnostics: DiagnosticsSettingsView(model: models.diagnostics)
        case .about: AboutSettingsView()
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: LoginItemViewModel
    @ObservedObject var recovery: RecoveryViewModel

    var body: some View {
        SettingsCardColumn {
            SettingsCard(title: "Launch at login") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
                LabeledContent("Registration", value: String(describing: model.state))
            }
            SettingsCard(title: "Signing and Keychain") {
                Text(recovery.recoveryCopy).wrapsInMainPane()
                Button("Retry") { Task { await recovery.refresh() } }
            }
        }
        .navigationTitle("General")
        .task { await recovery.refresh() }
    }
}

private struct RelaySettingsView: View {
    @ObservedObject var relay: RelaySetupViewModel
    @ObservedObject var pairing: PairingViewModel
    @ObservedObject var devices: DevicesViewModel
    @State private var showCopyWarning = false
    @State private var showDestroyConfirmation = false

    var body: some View {
        SettingsCardColumn {
            relaySetup
            pairingSetup
            pairedDevices
        }
        .navigationTitle("Relay & Pairing")
        .task { await devices.refresh() }
        .onAppear { pairing.pairingViewAppeared() }
        .onDisappear { pairing.pairingViewDisappeared() }
        .confirmationDialog(
            "Copying exposes pairing credentials to the system clipboard.",
            isPresented: $showCopyWarning
        ) {
            Button("Copy") { pairing.copyWithWarningConfirmed() }
        }
        .confirmationDialog(
            "Destroy remote relay data and local relay secrets?",
            isPresented: $showDestroyConfirmation
        ) {
            Button("Destroy Relay", role: .destructive) {
                Task { await devices.destroyRelay(confirmed: true) }
            }
        }
    }

    private var relaySetup: some View {
        SettingsCard(title: "Relay setup") {
            TextField("https://name.account.workers.dev", text: $relay.origin)
                .textFieldStyle(.roundedBorder)
            Button("Prepare Relay") { Task { await relay.prepare() } }
            if let write = relay.writeDigest {
                LabeledContent("WRITE_TOKEN_DIGEST", value: write).textSelection(.enabled)
            }
            if let admin = relay.adminDigest {
                LabeledContent("ADMIN_TOKEN_DIGEST", value: admin).textSelection(.enabled)
            }
            if relay.isPending { Button("Activate Relay") { Task { await relay.activate() } } }
        }
    }

    private var pairingSetup: some View {
        SettingsCard(title: "Pair a reader") {
            TextField("Device name", text: $pairing.deviceName)
                .textFieldStyle(.roundedBorder)
            Button("Create QR Pairing Code") { Task { await pairing.begin() } }
            if let encoded = pairing.encodedPackage {
                PairingCodeView(encoded: encoded)
                if let code = pairing.confirmationCode {
                    LabeledContent("Confirmation code", value: code)
                }
                Button("Copy pairing package…") { showCopyWarning = true }
            }
        }
    }

    private var pairedDevices: some View {
        SettingsCard(title: "Paired devices") {
            Button("Refresh") { Task { await devices.refresh() } }
            ForEach(devices.roster, id: \.readerID) { entry in
                HStack {
                    Text(entry.name ?? "Unknown reader")
                    Spacer()
                    Button("Revoke") { Task { await devices.revokeReader(entry.readerID) } }
                }
            }
            Button("Destroy Relay…", role: .destructive) { showDestroyConfirmation = true }
        }
    }
}

private struct PairingCodeView: View {
    let encoded: String

    var body: some View {
        Image(nsImage: QRCode.image(for: encoded))
            .interpolation(.none)
            .resizable()
            .frame(width: 180, height: 180)
            .accessibilityLabel("Pairing QR code")
    }
}

private struct DiagnosticsSettingsView: View {
    @ObservedObject var model: DiagnosticsViewModel

    var body: some View {
        SettingsCardColumn {
            SettingsCard(title: "Troubleshooting log folder") {
                Text(MacBuildFlavor.current.logDirectory.path)
                    .textSelection(.enabled)
                    .font(.system(.callout, design: .monospaced))
                    .wrapsInMainPane()
            }
            SettingsCard(title: "Diagnostic events") {
                if model.events.isEmpty {
                    Text("No diagnostic events.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.events.indices, id: \.self) { index in
                            Text(model.events[index].category.rawValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .task { await model.refresh() }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        SettingsCardColumn {
            SettingsCard(title: "Reset Radar") {
                Text("Personal allowance monitoring for Codex and Claude Code.")
            }
            SettingsCard(title: "License") {
                Text("Apache License 2.0")
            }
        }
        .navigationTitle("About")
    }
}

extension View {
    func wrapsInMainPane() -> some View {
        multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
