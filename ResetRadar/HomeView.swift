import ResetRadarApplication
import ResetRadarDomain
import ResetRadarUI
import SwiftUI
import UIKit

struct AccountRoute: Hashable {
    let accountID: AccountID
    /// The ring that opened Account Details, which receives initial emphasis.
    let focus: AccountWindow.StandardWindow?
}

/// Home: the Account List and Setup Banner. iPhone pushes Account Details; a regular-width
/// iPad keeps the list beside the selected account's details.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var environment: ReaderEnvironment
    @State private var path: [AccountRoute] = []
    @State private var splitFocus: AccountWindow.StandardWindow?
    @State private var showingPairing = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                split
            } else {
                stack
            }
        }
        .sheet(isPresented: $showingPairing) {
            NavigationStack {
                PairingSyncView(environment: environment)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingPairing = false }
                        }
                    }
            }
        }
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            list(selected: nil) { route in path.append(route) }
                .navigationDestination(for: AccountRoute.self) { route in
                    AccountDetailsScreen(
                        environment: environment, accountID: route.accountID, focus: route.focus)
                }
        }
    }

    private var split: some View {
        NavigationSplitView {
            list(selected: environment.selectedAccountID) { route in
                splitFocus = route.focus
                environment.select(route.accountID)
            }
            // Wide enough for an alias, both rings, and the arrow on one Account Row.
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            NavigationStack {
                if let selected = environment.selectedAccountID.flatMap({
                    environment.accountDetails($0) == nil ? nil : $0
                }) {
                    AccountDetailsScreen(
                        environment: environment, accountID: selected, focus: splitFocus
                    )
                    .id(selected)
                } else {
                    SetupGuidanceView(step: environment.setupStep, loaded: environment.loaded)
                }
            }
        }
    }

    private func list(
        selected: AccountID?, open: @escaping (AccountRoute) -> Void
    ) -> some View {
        AccountListView(
            environment: environment, selected: selected, open: open,
            openPairing: { showingPairing = true }
        )
        .navigationTitle("Home")
        .toolbar {
            if UIDevice.current.userInterfaceIdiom == .pad {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await environment.refreshHome() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(environment.refresh?.isRunning == true || !environment.loaded)
                    .accessibilityIdentifier("homeRefresh")
                }
            }
        }
    }
}

private struct AccountListView: View {
    @ObservedObject var environment: ReaderEnvironment
    let selected: AccountID?
    let open: (AccountRoute) -> Void
    let openPairing: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !environment.loaded {
                    ProgressView().padding(.top, 40)
                } else if let step = environment.setupStep {
                    SetupBannerView(
                        step: step, prominent: environment.home.accounts.isEmpty,
                        openPairing: openPairing)
                }
                ForEach(environment.home.accounts, id: \.account.id) { row in
                    AccountRowView(
                        row: row, selected: row.account.id == selected,
                        refreshLine: environment.refresh.flatMap {
                            RefreshFeedback.line(
                                for: row.source.product, accountID: row.account.id, in: $0)
                        },
                        open: { focus in open(AccountRoute(accountID: row.account.id, focus: focus))
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("accountList")
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await environment.pullToRefresh() }
    }
}

struct SetupBannerView: View {
    let step: ReaderSetupStep
    let prominent: Bool
    let openPairing: () -> Void

    var body: some View {
        VStack(alignment: prominent ? .center : .leading, spacing: 10) {
            Label(step.title, systemImage: step.symbolName)
                .font(prominent ? .title3.weight(.semibold) : .headline)
            Text(step.message)
                .font(prominent ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(prominent ? .center : .leading)
            if step.opensPairing {
                Button(step == .pairMac ? "Pair Mac" : "Open Pairing & Sync", action: openPairing)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("setupBanner.action")
            }
        }
        .frame(maxWidth: .infinity, alignment: prominent ? .center : .leading)
        .padding(prominent ? 24 : 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.top, prominent ? 24 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setupBanner")
    }
}

/// The trailing iPad column before an account exists: setup guidance, never invented details.
private struct SetupGuidanceView: View {
    let step: ReaderSetupStep?
    let loaded: Bool

    var body: some View {
        if !loaded {
            ProgressView()
        } else if let step {
            ContentUnavailableView(
                step.title, systemImage: step.symbolName, description: Text(step.message))
        } else {
            ContentUnavailableView(
                "Select an Account", systemImage: "person.crop.circle",
                description: Text("Choose an account in the list to see its Account Details."))
        }
    }
}
