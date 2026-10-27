import ResetRadarApplication
import ResetRadarDomain
import ResetRadarUI
import SwiftUI

private struct WatchSelection: Hashable {
    let accountID: AccountID
    let window: AccountWindow.StandardWindow
}

private enum WatchDestination: Hashable {
    case advancedActions
}

struct RootView: View {
    @ObservedObject var environment: WatchEnvironment

    var body: some View {
        NavigationStack {
            homeList
                .navigationDestination(for: WatchSelection.self) { selection in
                    WatchAccountDetails(selection: selection, environment: environment)
                }
                .navigationDestination(for: WatchDestination.self) { destination in
                    switch destination {
                    case .advancedActions:
                        WatchAdvancedActions(environment: environment)
                    }
                }
                .confirmationDialog(
                    "Use New iPhone Installation?",
                    isPresented: $environment.showInstallationConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Replace Watch Data", role: .destructive) {
                        Task { await environment.confirmPendingInstallation() }
                    }
                } message: {
                    Text(pendingInstallationDescription)
                }
                .alert(
                    "Watch Sync Problem",
                    isPresented: Binding(
                        get: { environment.operationMessage != nil },
                        set: { if !$0 { environment.operationMessage = nil } })
                ) {
                    Button("OK") { environment.operationMessage = nil }
                } message: {
                    Text(environment.operationMessage ?? "Try again.")
                }
        }
    }

    /// Home is one scrollable list: account rows lead, followed by refresh and navigation to
    /// local data controls, so neither action displaces allowance data into a pinned control.
    private var homeList: some View {
        List {
            Section {
                if environment.unavailable {
                    ContentUnavailableView(
                        "Reset Radar Can’t Open Its Data",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("Reinstall this Watch app with its companion app."))
                } else if environment.home.accounts.isEmpty {
                    ContentUnavailableView(
                        "No Allowance Data", systemImage: "chart.donut",
                        description: Text(
                            "Open Reset Radar on your iPhone to refresh this Watch."))
                } else {
                    ForEach(environment.home.accounts, id: \.account.id) { row in
                        WatchAccountRow(row: row)
                            .listRowInsets(
                                EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    }
                }
            }
            if ReaderVocabulary.isSyncProblem(environment.watchState.transportStatus) {
                Section("Sync Problem") {
                    Label(
                        ReaderVocabulary.transport(environment.watchState.transportStatus),
                        systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                }
            }
            if environment.watchState.pendingInstallation != nil {
                Section("New iPhone") {
                    Button("Review New Installation") {
                        environment.requestInstallationConfirmation()
                    }
                }
            }
            Section {
                Button {
                    Task { await environment.refresh() }
                } label: {
                    Text("Refresh")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Refresh from iPhone")
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }
            Section {
                NavigationLink(value: WatchDestination.advancedActions) {
                    Text("Advanced")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Open advanced Watch data actions")
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }
        }
    }

    private var pendingInstallationDescription: String {
        let accounts = environment.watchState.pendingInstallation?.snapshot?.accounts ?? []
        guard !accounts.isEmpty else { return "The new installation has no allowance data." }
        return "Replace this Watch cache with data for "
            + accounts.map(\.effectiveDisplayLabel).joined(separator: ", ") + "?"
    }
}

private struct WatchAdvancedActions: View {
    @ObservedObject var environment: WatchEnvironment

    var body: some View {
        List {
            Section {
                Button("Erase Watch Data", role: .destructive) {
                    environment.requestEraseConfirmation()
                }
                if environment.watchState.localEraseHold {
                    Button("Reset Watch Pairing") { environment.requestResetConfirmation() }
                }
            } footer: {
                Text("These controls affect only data stored on this Watch.")
            }
        }
        .navigationTitle("Advanced Action")
        .confirmationDialog(
            "Erase Watch Data?", isPresented: $environment.showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase Watch Data", role: .destructive) {
                Task { await environment.erase() }
            }
        } message: {
            Text("Cached allowance data will be removed until you choose Reset Watch Pairing.")
        }
        .confirmationDialog(
            "Reset Watch Pairing?", isPresented: $environment.showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Watch Pairing", role: .destructive) {
                Task { await environment.resetPairing() }
            }
        } message: {
            Text("This permits new usage from the currently paired iPhone installation.")
        }
    }
}

private struct WatchAccountRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let row: AccountRow

    var body: some View {
        let palette = AccountPalette(accountNumber: row.account.number)
        HStack(spacing: 8) {
            ForEach(Array(row.standardWindows.enumerated()), id: \.offset) { index, ring in
                let standard = AccountWindow.StandardWindow.allCases[index]
                NavigationLink(
                    value: WatchSelection(accountID: row.account.id, window: standard)
                ) {
                    AllowanceRing(
                        display: AllowanceDisplay(ring: ring, product: row.account.product),
                        caption: ReaderVocabulary.windowCaption(standard), diameter: 58)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(ring, standard: standard))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            palette.surface(appearance).color.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .tint(palette.foreground(appearance).color)
        .accessibilityElement(children: .contain)
    }

    private var appearance: AccountPaletteAppearance {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? .darkIncreased : .lightIncreased
        }
        return colorScheme == .dark ? .dark : .light
    }

    private func accessibilityLabel(
        _ ring: AccountRingSummary, standard: AccountWindow.StandardWindow
    ) -> String {
        let display = AllowanceDisplay(ring: ring, product: row.account.product)
        let base = display.accessibilityLabel(
            account: row.account, window: ReaderVocabulary.windowName(standard))
        let reset =
            ring.resetsAt.map {
                ", resets \($0.formatted(date: .abbreviated, time: .shortened))"
            } ?? ", reset unavailable"
        return base + reset
    }
}

private struct WatchAccountDetails: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let selection: WatchSelection
    @ObservedObject var environment: WatchEnvironment

    var body: some View {
        let account = environment.details.accounts.first {
            $0.account.id == selection.accountID
        }
        let palette = AccountPalette(accountNumber: account?.account.number ?? 1)
        List {
            if let account {
                if ReaderVocabulary.isSyncProblem(environment.watchState.transportStatus) {
                    Section("Sync Problem") {
                        Text(ReaderVocabulary.transport(environment.watchState.transportStatus))
                    }
                }
                Section {
                    Text(account.account.effectiveDisplayLabel)
                    Text(ReaderVocabulary.productName(account.account.product))
                        .foregroundStyle(.secondary)
                }
                ForEach(WindowSection.ordered(account)) { section in
                    WindowDetailsRow(
                        section: section, source: account.source,
                        emphasized: section.id == .standard(selection.window), palette: palette,
                        appearance: appearance)
                }
            }
        }
        .navigationTitle(account?.account.effectiveDisplayLabel ?? "Account")
    }

    private var appearance: AccountPaletteAppearance {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? .darkIncreased : .lightIncreased
        }
        return colorScheme == .dark ? .dark : .light
    }
}

private struct WindowDetailsRow: View {
    let section: WindowSection
    let source: AccountSource
    let emphasized: Bool
    let palette: AccountPalette
    let appearance: AccountPaletteAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                AllowanceRing(
                    display: section.display, diameter: 62, emphasized: emphasized)
                VStack(alignment: .leading) {
                    Text(section.title).font(.headline)
                    StateBadge(display: section.display)
                    Text(section.display.percentText.map { "\($0) used" } ?? "No percentage")
                        .font(.caption)
                }
            }
            if let window = section.details?.window {
                if let reset = window.resetsAt {
                    Text("Resets \(reset, style: .relative)")
                    Text(reset.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                if let observed = window.observation?.observedAt {
                    Text("Last Updated \(observed, style: .relative)")
                        .foregroundStyle(.secondary)
                }
            }
            if let explanation = section.display.explanation(source: source) {
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .tint(palette.foreground(appearance).color)
        .listRowBackground(palette.surface(appearance).color.opacity(emphasized ? 0.9 : 0.55))
    }
}
