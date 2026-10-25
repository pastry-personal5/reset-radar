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
}

struct SettingsRootView: View {
    let models: OwnerFlowModels?
    let rebuildCollector: @MainActor () async -> Void
    @State private var selection = SettingsSection.general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Text(section.rawValue).tag(section)
            }
            .navigationTitle("Settings")
        } detail: {
            if let models { detail(models) } else { ProgressView("Starting collector…") }
        }
        .frame(minWidth: 1300, minHeight: 800)
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
        Form {
            Toggle(
                "Launch at login",
                isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
            LabeledContent("Registration", value: String(describing: model.state))
            if let error = model.errorMessage {
                Text(error)
                    .wrapsInMainPane()
                    .foregroundStyle(.red)
            }
            Section("Signing and Keychain") {
                Text(recovery.recoveryCopy).wrapsInMainPane()
                Button("Retry") { Task { await recovery.refresh() } }
            }
        }
        .padding()
        .navigationTitle("General")
        .task { await recovery.refresh() }
    }
}

private struct SourcesSettingsView: View {
    @ObservedObject var model: SourceSetupViewModel
    let rebuildCollector: @MainActor () async -> Void
    @State private var firstCodexHome = ""
    @State private var secondCodexHome = ""
    @State private var showRestoreConfirmation = false
    @State private var showRemovalConfirmation = false
    @State private var removalCandidate: AccountMetadata?

    var body: some View {
        Form {
            Section("Codex") {
                TextField("First CODEX_HOME folder", text: $firstCodexHome)
                TextField("Second CODEX_HOME folder (optional)", text: $secondCodexHome)
                TextField("Optional codex executable", text: $model.codexExecutable)
                Button("Discover Codex") {
                    model.codexHomes = [firstCodexHome, secondCodexHome]
                    Task { await model.discoverCodex() }
                }
            }
            Section("Claude Code") {
                Button("Preview guided status-line setup") {
                    Task { await model.discoverClaudeCode() }
                }
                Button("Restore prior status-line setting") { showRestoreConfirmation = true }
            }
            ForEach(model.options, id: \.id) { option in
                VStack(alignment: .leading) {
                    Text(option.launch.executablePath).wrapsInMainPane()
                    ForEach(option.launch.environment, id: \.key) { value in
                        Text("\(value.key.rawValue)=\(value.value)")
                            .font(.caption.monospaced())
                            .wrapsInMainPane()
                    }
                    Button("Preview") { Task { await model.prepare(option) } }
                }
            }
            if let preview = model.preview {
                Section("Confirm exact change") {
                    Text(preview.launch.executablePath)
                        .font(.body.monospaced())
                        .wrapsInMainPane()
                    if let status = preview.statusLine {
                        Text("Settings: \(status.settingsPath)").wrapsInMainPane()
                        Text("Helper: \(status.helperPath)").wrapsInMainPane()
                    }
                    Button("Confirm and Apply") {
                        Task {
                            if await model.confirmPreview() { await rebuildCollector() }
                        }
                    }
                }
            }
            if !model.configuredAccounts.isEmpty {
                Section("Configured sources") {
                    ForEach(model.configuredAccounts, id: \.id) { account in
                        ConfiguredSourceRow(
                            account: account, model: model,
                            remove: {
                                removalCandidate = account
                                showRemovalConfirmation = true
                            })
                    }
                }
            }
            if let message = model.message {
                Text(message)
                    .wrapsInMainPane()
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Sources")
        .task { await model.loadConfiguredAccounts() }
        .confirmationDialog(
            "Restore the prior Claude Code status-line setting?",
            isPresented: $showRestoreConfirmation
        ) {
            Button("Restore", role: .destructive) {
                Task {
                    if await model.restoreClaudeCode(confirmed: true) {
                        await rebuildCollector()
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove this configured source?",
            isPresented: $showRemovalConfirmation,
            presenting: removalCandidate
        ) { account in
            Button("Remove", role: .destructive) {
                Task {
                    if await model.remove(account.id, product: account.product, confirmed: true) {
                        await rebuildCollector()
                    }
                    removalCandidate = nil
                }
            }
        } message: { account in
            Text(
                "Removing \(account.effectiveDisplayLabel) stops its local source. "
                    + "It does not change relay data."
            )
        }
    }
}

private struct ConfiguredSourceRow: View {
    let account: AccountMetadata
    @ObservedObject var model: SourceSetupViewModel
    let remove: () -> Void
    @State private var alias: String

    init(account: AccountMetadata, model: SourceSetupViewModel, remove: @escaping () -> Void) {
        self.account = account
        self.model = model
        self.remove = remove
        _alias = State(initialValue: account.alias?.value ?? "")
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(account.effectiveDisplayLabel)
                Spacer()
                Text(account.product == .codex ? "Codex" : "Claude Code")
                    .foregroundStyle(.secondary)
                Button("Remove", role: .destructive, action: remove)
            }
            HStack {
                TextField("Alias", text: $alias)
                Button("Save Alias") {
                    Task { await model.updateAlias(accountID: account.id, input: alias) }
                }
            }
        }
    }
}

private struct RelaySettingsView: View {
    @ObservedObject var relay: RelaySetupViewModel
    @ObservedObject var pairing: PairingViewModel
    @ObservedObject var devices: DevicesViewModel
    @State private var showCopyWarning = false
    @State private var showDestroyConfirmation = false

    var body: some View {
        Form {
            relaySetup
            pairingSetup
            pairedDevices
        }
        .padding()
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
        Section("Relay setup") {
            TextField("https://name.account.workers.dev", text: $relay.origin)
            Button("Prepare Relay") { Task { await relay.prepare() } }
            if let write = relay.writeDigest {
                LabeledContent("WRITE_TOKEN_DIGEST", value: write).textSelection(.enabled)
            }
            if let admin = relay.adminDigest {
                LabeledContent("ADMIN_TOKEN_DIGEST", value: admin).textSelection(.enabled)
            }
            if relay.isPending { Button("Activate Relay") { Task { await relay.activate() } } }
            if let message = relay.message {
                Text(message)
                    .wrapsInMainPane()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pairingSetup: some View {
        Section("Pair a reader") {
            TextField("Device name", text: $pairing.deviceName)
            Button("Create QR Pairing Code") { Task { await pairing.begin() } }
            if let encoded = pairing.encodedPackage {
                PairingCodeView(encoded: encoded)
                if let code = pairing.confirmationCode {
                    LabeledContent("Confirmation code", value: code)
                }
                Button("Copy pairing package…") { showCopyWarning = true }
            }
            if let message = pairing.message {
                Text(message)
                    .wrapsInMainPane()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pairedDevices: some View {
        Section("Paired devices") {
            Button("Refresh") { Task { await devices.refresh() } }
            ForEach(devices.roster, id: \.readerID) { entry in
                HStack {
                    Text(entry.name ?? "Unknown reader")
                    Spacer()
                    Button("Revoke") { Task { await devices.revokeReader(entry.readerID) } }
                }
            }
            Button("Destroy Relay…", role: .destructive) { showDestroyConfirmation = true }
            if let message = devices.message {
                Text(message)
                    .wrapsInMainPane()
                    .foregroundStyle(.secondary)
            }
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
        List(model.events, id: \.self) { event in Text(event.category.rawValue) }
            .navigationTitle("Diagnostics")
            .task { await model.refresh() }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        Form {
            Text("Reset Radar")
            Text("Personal allowance monitoring for Codex and Claude Code.")
            Text("Apache License 2.0")
        }
        .padding()
        .navigationTitle("About")
    }
}

extension View {
    fileprivate func wrapsInMainPane() -> some View {
        multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
