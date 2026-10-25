import ResetRadarDomain
import SwiftUI

struct RootView: View {
    let environment: MacEnvironment?
    var startupFailed = false

    var body: some View {
        if startupFailed {
            ContentUnavailableView(
                "Reset Radar could not start", systemImage: "exclamationmark.triangle",
                description: Text("Open Settings to review signing, Keychain, and source setup."))
        } else if let environment {
            HomeView(model: environment.ownerFlows.home)
        } else {
            ProgressView("Starting collector…")
        }
    }
}

private struct HomeView: View {
    @ObservedObject var model: HomeViewModel
    @State private var selection: AccountID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.accounts, id: \.id) { account in
                    Text(account.effectiveDisplayLabel).tag(account.id)
                }
            }
            .navigationTitle("Accounts")
        } detail: {
            if let account = model.accounts.first(where: { $0.id == selection }) {
                AccountDetailView(account: account, model: model)
            } else {
                ContentUnavailableView(
                    "Select an account", systemImage: "gauge.with.dots.needle.50percent")
            }
        }
        .task {
            await model.load()
            if selection == nil { selection = model.accounts.first?.id }
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
            if let message = model.message {
                Text(message)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle(account.effectiveDisplayLabel)
        .onAppear { alias = account.alias?.value ?? "" }
    }
}
