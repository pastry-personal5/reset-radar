import Foundation
import ResetRadarApplication
import ResetRadarDomain
import SwiftUI

struct SourcesSettingsView: View {
    @ObservedObject var model: SourceSetupViewModel
    @ObservedObject var home: HomeViewModel
    let rebuildCollector: @MainActor () async -> Void
    @State private var isAddingCodex = false
    @State private var replacementAccount: AccountMetadata?
    @State private var codexAlias = ""
    @State private var codexHome = ""
    @FocusState private var codexAliasFocused: Bool
    @State private var showRestoreConfirmation = false
    @State private var showRemovalConfirmation = false
    @State private var removalCandidate: AccountMetadata?

    private var codexAccounts: [AccountMetadata] {
        model.configuredAccounts.filter { $0.product == .codex }
    }

    var body: some View {
        SettingsCardColumn {
            codexCard
            SettingsCard(title: "Claude Code") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Connection")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                    Divider()
                    Text(
                        "Reset Radar edits ~/.claude/settings.json directly after you review "
                            + "and confirm the exact status-line change."
                    )
                    .foregroundStyle(.secondary)
                    .padding(12)
                    Divider()
                    HStack(spacing: 12) {
                        Button("Set Up Claude Code Connection") {
                            Task { await model.discoverClaudeCode() }
                        }
                        Button("Restore Previous Setting") {
                            showRestoreConfirmation = true
                        }
                    }
                    .padding(12)
                    Divider()
                    sourceOptions(for: .claudeCode)
                        .padding(12)
                    if let account = model.configuredAccounts.first(where: {
                        $0.product == .claudeCode
                    }) {
                        Divider()
                        Text("Configured Account")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                        Divider()
                        ConfiguredSourceRow(
                            account: account, home: home,
                            remove: { confirmRemoval(of: account) }
                        )
                        .padding(12)
                    }
                    if model.preview?.product == .claudeCode {
                        Divider()
                        confirmationPreview.padding(12)
                    }
                }
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary)
                }
            }
            if let message = model.message {
                SettingsCard(title: "Source status") {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sourceSetupMessage")
                }
            }
        }
        .navigationTitle("Sources")
        .task { await model.loadConfiguredAccounts() }
        .onDisappear {
            for account in model.configuredAccounts {
                home.clearAliasDelivery(for: account.id)
            }
        }
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

    private var codexCard: some View {
        SettingsCard(title: "Codex") {
            Text("Configure up to two accounts, each with its own home folder.")
                .foregroundStyle(.secondary)
            codexTable
            if isAddingCodex {
                TextField("Optional Codex executable path", text: $model.codexExecutable)
                    .onChange(of: model.codexExecutable) { _, _ in
                        if isAddingCodex { model.cancelPendingSetup() }
                    }
            }
            sourceOptions(for: .codex)
            if model.preview?.product == .codex { confirmationPreview }
        }
    }

    private var codexTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Alias").frame(width: 190, alignment: .leading)
                Text("Home Folder").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 260, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider()

            ForEach(codexAccounts, id: \.id) { account in
                CodexSourceRow(
                    account: account,
                    homeFolder: model.codexHomeFolders[account.id],
                    home: home,
                    changeHome: { beginChangingHome(of: account, proposedHome: $0) },
                    remove: { confirmRemoval(of: account) }
                )
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                Divider()
            }

            if isAddingCodex {
                codexDraftRow
            } else if codexAccounts.count < AccountCatalog.maximumCodexAccounts {
                codexAddRow
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary)
        }
    }

    private var codexAddRow: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 190, height: 1)
            Color.clear.frame(maxWidth: .infinity, minHeight: 1)
            Button {
                replacementAccount = nil
                isAddingCodex = true
            } label: {
                Label {
                    Text("Add")
                } icon: {
                    Image("AddSource")
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 18, height: 18)
                }
            }
            .accessibilityLabel("Add Codex source")
            .frame(width: 260, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
    }

    private var codexDraftRow: some View {
        HStack(spacing: 12) {
            if let replacementAccount {
                Text(replacementAccount.effectiveDisplayLabel)
                    .frame(width: 190, alignment: .leading)
            } else {
                TextField("Alias", text: $codexAlias)
                    .textFieldStyle(.roundedBorder)
                    .focused($codexAliasFocused)
                    .frame(width: 190)
            }
            TextField("Absolute Home Folder", text: $codexHome)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onChange(of: codexHome) { _, _ in
                    if isAddingCodex { model.cancelPendingSetup() }
                }
            HStack(spacing: 6) {
                Button("Cancel") { cancelCodexDraft() }
                Button("Discover") {
                    model.codexHomes = [codexHome]
                    Task { await model.discoverCodex() }
                }
                .disabled(!codexHome.hasPrefix("/"))
            }
            .frame(width: 260, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .onAppear { codexAliasFocused = replacementAccount == nil }
    }
}

extension SourcesSettingsView {
    private func beginChangingHome(of account: AccountMetadata, proposedHome: String) {
        replacementAccount = account
        codexHome = proposedHome
        codexAlias = ""
        model.codexExecutable = ""
        model.cancelPendingSetup()
        isAddingCodex = true
    }

    private func cancelCodexDraft() {
        isAddingCodex = false
        replacementAccount = nil
        codexAlias = ""
        codexHome = ""
        model.codexExecutable = ""
        model.cancelPendingSetup()
    }

    @ViewBuilder
    private func sourceOptions(for product: ProductID) -> some View {
        ForEach(model.options.filter { $0.product == product }, id: \.id) { option in
            HStack(alignment: .top) {
                SourceLaunchDetails(launch: option.launch)
                Spacer()
                Button("Preview") {
                    Task {
                        let intent: ConfigurationIntent
                        if product == .codex, let replacementAccount {
                            intent = .replace(replacementAccount.id)
                        } else {
                            intent = .add
                        }
                        await model.prepare(option, intent: intent)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var confirmationPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Confirm exact change").font(.headline)
            if let preview = model.preview {
                if preview.product == .codex {
                    LabeledContent(
                        "Alias",
                        value: replacementAccount?.effectiveDisplayLabel
                            ?? (codexAlias.isEmpty ? "Default account label" : codexAlias))
                }
                SourceLaunchDetails(launch: preview.launch)
                if let status = preview.statusLine {
                    Text("Settings: \(status.settingsPath)").wrapsInMainPane()
                    Text("Helper: \(status.helperPath)").wrapsInMainPane()
                }
                if !codexPreviewMatchesDraft(preview) {
                    Text("Home Folder changed. Discover the source again before confirming.")
                        .foregroundStyle(.orange)
                }
                Button("Confirm and Apply") {
                    Task {
                        let alias =
                            preview.product == .codex && replacementAccount == nil
                            ? codexAlias : ""
                        if await model.confirmPreview(alias: alias) {
                            if preview.product == .codex {
                                isAddingCodex = false
                                replacementAccount = nil
                                codexAlias = ""
                                codexHome = ""
                                model.codexExecutable = ""
                            }
                            await rebuildCollector()
                        }
                    }
                }
                .disabled(!codexPreviewMatchesDraft(preview))
            }
        }
        .padding(.top, 12)
    }

    private func confirmRemoval(of account: AccountMetadata) {
        removalCandidate = account
        showRemovalConfirmation = true
    }

    private func codexPreviewMatchesDraft(_ preview: ConfigurationPreview) -> Bool {
        guard preview.product == .codex else { return true }
        guard codexHome.hasPrefix("/") else { return false }
        guard preview.intent.accountID == replacementAccount?.id else { return false }
        let selectedHome = URL(fileURLWithPath: codexHome).path
        return preview.launch.environment.contains {
            $0.key == .codexHome && $0.value == selectedHome
        }
    }
}
