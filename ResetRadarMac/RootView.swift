import ResetRadarDomain
import SwiftUI

struct RootView: View {
    let environment: MacEnvironment?
    @ObservedObject var messages: GlobalMessageCenter
    var startupFailed = false

    var body: some View {
        if startupFailed {
            VStack(spacing: 0) {
                ContentUnavailableView(
                    "Reset Radar could not start", systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Open Settings to review signing, Keychain, and source setup.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                GlobalMessagesPane(messages: messages)
            }
        } else if let environment {
            HomeView(model: environment.ownerFlows.home, messages: messages)
        } else {
            VStack(spacing: 0) {
                ProgressView("Starting collector…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                GlobalMessagesPane(messages: messages)
            }
        }
    }
}

private struct HomeView: View {
    @ObservedObject var model: HomeViewModel
    @ObservedObject var messages: GlobalMessageCenter
    @State private var selection: AccountID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.accounts, id: \.id) { account in
                    MacAccountRow(account: account, snapshot: model.snapshot) {
                        selection = account.id
                    }
                    .tag(account.id)
                }
            }
            .navigationTitle("Accounts")
            .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 500)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    if let account = model.accounts.first(where: { $0.id == selection }) {
                        AccountDetailView(account: account, model: model)
                            .id(account.id)
                    } else {
                        ContentUnavailableView(
                            "Select an account", systemImage: "gauge.with.dots.needle.50percent")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                GlobalMessagesPane(messages: messages)
            }
        }
        .task {
            await model.load()
            if selection == nil { selection = model.accounts.first?.id }
        }
        .onChange(of: model.accounts.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = ids.first
        }
    }
}

private struct MacAccountRow: View {
    let account: AccountMetadata
    let snapshot: UsageSnapshot?
    let openDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.effectiveDisplayLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(account.product == .codex ? "Codex" : "Claude Code")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MacAllowanceRing(account: account, window: .fiveHour, snapshot: snapshot)
            MacAllowanceRing(account: account, window: .weekly, snapshot: snapshot)

            Button(action: openDetails) {
                Image(systemName: "arrow.right.circle")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account Details")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary)
        }
    }
}

private struct AccountDetailView: View {
    let account: AccountMetadata
    @ObservedObject var model: HomeViewModel
    @State private var alias = ""

    var body: some View {
        Form {
            Text(account.product == .codex ? "Codex" : "Claude Code")
                .font(.headline)
            TextField("Alias", text: $alias)
            Button("Save Alias") {
                Task { await model.updateAlias(accountID: account.id, input: alias) }
            }
            if let source = model.snapshot?.source(for: account.id) {
                LabeledContent("Source state") {
                    Text(String(describing: source.state))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .navigationTitle(account.effectiveDisplayLabel)
        .onAppear { alias = account.alias?.value ?? "" }
        .onChange(of: account.alias?.value) { _, value in alias = value ?? "" }
    }
}
