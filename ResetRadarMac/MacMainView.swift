import Foundation
import ResetRadarDomain
import SwiftUI

private enum MacMainSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case benefits = "Benefits"
    case community = "Community"
    case insight = "Insight"
    case all = "All"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .home: "house"
        case .benefits: "diamond"
        case .community: "person.3"
        case .insight: "lightbulb"
        case .all: "line.3.horizontal"
        }
    }
}

enum MacHomeSelection {
    static var key: String {
        switch MacBuildFlavor.current {
        case .development, .test: "mac-home-selection.dev"
        case .release: "mac-home-selection"
        }
    }

    static func restore(
        from accounts: [AccountMetadata], defaults: UserDefaults = .standard
    ) -> AccountID? {
        if let text = defaults.string(forKey: key), let id = AccountID(hex: text) {
            if accounts.contains(where: { $0.id == id }) { return id }
        }
        return accounts.first?.id
    }

    static func save(_ accountID: AccountID?, defaults: UserDefaults = .standard) {
        defaults.set(accountID?.hex, forKey: key)
    }
}

struct MacMainView: View {
    @ObservedObject var model: HomeViewModel
    @ObservedObject var messages: GlobalMessageCenter
    @State private var section = MacMainSection.home
    @State private var selectedAccountID: AccountID?
    @State private var focusedWindow: AccountWindow.StandardWindow?
    @State private var focusedAccountID: AccountID?

    private var selectedAccount: AccountMetadata? {
        model.accounts.first { $0.id == selectedAccountID }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar.frame(width: 210)
                Divider()
                if section == .home {
                    accountList.frame(width: 440)
                    Divider()
                }
                detailPane(height: max(0, geometry.size.height - 40))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: max(0, geometry.size.height - 40))
            .padding(.top, 40)
        }
        .task {
            await model.load()
            if selectedAccount == nil {
                selectedAccountID = MacHomeSelection.restore(from: model.accounts)
            }
        }
        .onChange(of: model.accounts.map(\.id)) { _, ids in
            if let selectedAccountID, ids.contains(selectedAccountID) { return }
            selectedAccountID = MacHomeSelection.restore(from: model.accounts)
        }
        .onChange(of: selectedAccountID) { _, id in MacHomeSelection.save(id) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Text("Reset Radar")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            List(MacMainSection.allCases, selection: $section) { destination in
                Label(destination.rawValue, systemImage: destination.symbol)
                    .tag(destination)
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailPane(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Group {
                if section == .home {
                    if let account = selectedAccount {
                        MacAccountDetailsView(
                            account: account, model: model, messages: messages,
                            focusedWindow: focusedAccountID == account.id ? focusedWindow : nil
                        )
                        .id(account.id)
                    } else {
                        ContentUnavailableView(
                            "No account selected",
                            systemImage: "gauge.with.dots.needle.50percent",
                            description: Text(
                                "Configure a source in Settings to see its details."))
                    }
                } else {
                    ContentUnavailableView(section.rawValue, systemImage: section.symbol)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(0, height - 180))
            .clipped()
            GlobalMessagesPane(messages: messages)
                .frame(height: 180, alignment: .bottom)
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Account List").font(.headline)
                Spacer()
                Button("Refresh") { Task { await model.refreshAll() } }
                    .disabled(model.isRefreshing || model.accounts.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if let step = model.setupStep {
                MacSetupBanner(step: step)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            List(selection: $selectedAccountID) {
                ForEach(model.accounts, id: \.id) { account in
                    MacAccountRow(
                        account: account, model: model, snapshot: model.snapshot,
                        openDetails: { window in
                            selectedAccountID = account.id
                            focusedAccountID = account.id
                            focusedWindow = window
                        }
                    )
                    .tag(account.id)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct MacSetupBanner: View {
    let step: MacSetupStep

    private var copy: String {
        switch step {
        case .sources:
            "Add a Codex or Claude Code source in Settings to start local readings."
        case .relay:
            "Set up the relay in Settings to share local readings with your other devices."
        case .pairing:
            "Pair an iPhone or iPad in Settings to receive encrypted readings."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Finish setup", systemImage: "info.circle")
                .font(.headline)
            Text(copy).fixedSize(horizontal: false, vertical: true)
            SettingsLink { Text("Open Settings") }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
    }
}

private struct MacAccountRow: View {
    let account: AccountMetadata
    @ObservedObject var model: HomeViewModel
    let snapshot: UsageSnapshot?
    let openDetails: (AccountWindow.StandardWindow?) -> Void
    @State private var editingAlias = false
    @State private var alias = ""
    @State private var aliasError: String?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if editingAlias {
                    TextField("Account Alias", text: $alias)
                        .onSubmit { saveAlias() }
                    Button("Save Alias") { saveAlias() }
                        .font(.caption)
                    Button("Cancel") { editingAlias = false }
                        .font(.caption)
                    if let aliasError {
                        Text(aliasError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Button(account.effectiveDisplayLabel) {
                        alias = account.alias?.value ?? ""
                        aliasError = nil
                        editingAlias = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityHint("Edit Account Alias")
                }
                Text(account.product == .codex ? "Codex" : "Claude Code")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(AccountWindow.StandardWindow.allCases, id: \.self) { window in
                Button {
                    openDetails(window)
                } label: {
                    MacAllowanceRing(account: account, window: window, snapshot: snapshot)
                }
                .buttonStyle(.plain)
            }
            Button {
                openDetails(nil)
            } label: {
                Image("AccountDetails")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account Details")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
        .onChange(of: account.alias?.value) { _, value in alias = value ?? "" }
    }

    private func saveAlias() {
        Task {
            await model.updateAlias(accountID: account.id, input: alias)
            aliasError = model.message
            if aliasError == nil { editingAlias = false }
        }
    }
}
