import AppKit
import ResetRadarApplication
import ResetRadarDomain
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case sources = "Sources"
    case relay = "Relay & Pairing"
    case about = "About"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .sources: "externaldrive"
        case .relay: "network"
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
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
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
        case .general:
            GeneralSettingsView(model: models.general, recovery: models.recovery, home: models.home)
        case .sources:
            SourcesSettingsView(
                model: models.sources, home: models.home,
                rebuildCollector: rebuildCollector)
        case .relay:
            RelaySettingsView(
                relay: models.relay, pairing: models.pairing, devices: models.devices,
                rebuildCollector: rebuildCollector)
        case .about: AboutSettingsView()
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: LoginItemViewModel
    @ObservedObject var recovery: RecoveryViewModel
    @ObservedObject var home: HomeViewModel
    @State private var showingLoginInfo = false

    var body: some View {
        SettingsCardColumn {
            SettingsCard(title: "Launch at login") {
                HStack {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
                    Button {
                        showingLoginInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About Launch at Login")
                    .accessibilityHint("Explains automatic collection after sign in")
                    .popover(isPresented: $showingLoginInfo, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                "Reset Radar can open automatically when you sign in so allowance "
                                    + "collection and reset monitoring can continue. This toggle "
                                    + "controls that feature."
                            )
                            .frame(width: 300, alignment: .leading)
                            Button("Close") { showingLoginInfo = false }
                                .keyboardShortcut(.cancelAction)
                        }
                        .padding()
                    }
                }
            }
            SettingsCard(title: "Signing and Keychain") {
                Text(recovery.recoveryCopy).wrapsInMainPane()
                Button("Retry") { Task { await recovery.refresh() } }
            }
            SettingsCard(title: "Reset Notifications") {
                LabeledContent("Authorization", value: authorizationText)
                if home.notificationAuthorization == .denied {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(filePath: "/System/Applications/System Settings.app"))
                    }
                }
                Text("Enable a reminder from an Account Details window to request permission.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("General")
        .task {
            await recovery.refresh()
            await home.reconcileNotifications()
        }
    }

    private var authorizationText: String {
        switch home.notificationAuthorization {
        case .notDetermined: "Not requested"
        case .denied: "Denied in System Settings"
        case .authorized: "Allowed"
        case .provisional: "Provisional"
        case .failed: "Could not request permission"
        case .unknown: "Unknown system status"
        }
    }
}

private struct RelaySettingsView: View {
    @ObservedObject var relay: RelaySetupViewModel
    @ObservedObject var pairing: PairingViewModel
    @ObservedObject var devices: DevicesViewModel
    let rebuildCollector: @MainActor () async -> Void
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
        .task { await relay.load() }
        .onAppear { pairing.pairingViewAppeared() }
        .onDisappear { pairing.pairingViewDisappeared() }
        .onChange(of: pairing.encodedPackage) { previous, current in
            if previous != nil && current == nil {
                Task { await devices.refresh() }
            }
        }
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
                Task {
                    await devices.destroyRelay(confirmed: true)
                    await relay.load()
                }
            }
        }
    }

    private var relaySetup: some View {
        SettingsCard(title: "Relay Setup") {
            LabeledContent("State", value: relayStateText)
            if relay.lifecycle == .active {
                Label("Configured", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(relayStateExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .wrapsInMainPane()
            if let endpoint = relay.endpoint {
                LabeledContent("Endpoint", value: endpoint.absoluteString)
                    .textSelection(.enabled)
            }
            if relay.lifecycle == .notConfigured {
                TextField("https://name.account.workers.dev", text: $relay.origin)
                    .textFieldStyle(.roundedBorder)
                Button("Prepare Relay") { Task { await relay.prepare() } }
            }
            if let write = relay.writeDigest {
                LabeledContent("WRITE_TOKEN_DIGEST", value: write).textSelection(.enabled)
            }
            if let admin = relay.adminDigest {
                LabeledContent("ADMIN_TOKEN_DIGEST", value: admin).textSelection(.enabled)
            }
            if relay.isPending {
                if relay.writeDigest == nil || relay.adminDigest == nil {
                    Button("Retry Prepare Relay") { Task { await relay.prepare() } }
                }
                Button("Activate Relay") {
                    Task {
                        if await relay.activate() { await rebuildCollector() }
                    }
                }
            }
            if relay.lifecycle == .destroyPending {
                Button("Retry Destroy Relay", role: .destructive) {
                    Task {
                        await devices.destroyRelay(confirmed: true)
                        await relay.load()
                    }
                }
            }
        }
    }

    private var pairingSetup: some View {
        SettingsCard(title: "Pair an iPhone or iPad") {
            Button("Pair an iPhone or iPad") { Task { await pairing.begin() } }
            if let encoded = pairing.encodedPackage {
                PairingCodeView(encoded: encoded)
                if let code = pairing.confirmationCode {
                    LabeledContent("Confirmation code", value: code)
                }
                if let expiresAt = pairing.expiresAt {
                    LabeledContent("Expires") {
                        Text(expiresAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Button("Copy pairing package…") { showCopyWarning = true }
            }
        }
    }

    private var pairedDevices: some View {
        SettingsCard(title: "Paired Devices") {
            Button("Refresh") { Task { await devices.refresh() } }
            if devices.roster.isEmpty {
                ContentUnavailableView(
                    "No paired devices", systemImage: "iphone.gen3",
                    description: Text("Create a QR pairing code to pair an iPhone or iPad.")
                )
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(devices.roster, id: \.readerID) { entry in
                        PairedDeviceRow(entry: entry) {
                            Task { await devices.revokeReader(entry.readerID) }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(height: min(440, max(100, CGFloat(devices.roster.count) * 100)))
            }
            if let message = devices.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Button("Destroy Relay…", role: .destructive) { showDestroyConfirmation = true }
        }
    }

    private var relayStateExplanation: String {
        switch relay.lifecycle {
        case .notConfigured:
            "Set up the relay before pairing an iPhone or iPad."
        case .setupPending:
            relay.writeDigest == nil || relay.adminDigest == nil
                ? "Relay setup is pending. Retry preparation to restore the deployment digests."
                : "Add both deployment digests as Worker secrets, then activate this relay."
        case .active:
            "The relay is configured on this Mac."
        case .destroyPending:
            "Publication is stopped while relay destruction is pending. Retry to finish removal."
        }
    }

    private var relayStateText: String {
        switch relay.lifecycle {
        case .notConfigured: "Not Configured"
        case .setupPending: "Setup Pending"
        case .active: "Configured"
        case .destroyPending: "Destroy Pending"
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

extension View {
    func wrapsInMainPane() -> some View {
        multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
