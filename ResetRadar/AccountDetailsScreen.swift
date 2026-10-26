import ResetRadarApplication
import ResetRadarDomain
import ResetRadarUI
import SwiftUI

/// Account Details: identity, the two standard windows first, every other valid window, the
/// account's Refresh Result, then provenance and synchronization.
struct AccountDetailsScreen: View {
    @ObservedObject var environment: ReaderEnvironment
    let accountID: AccountID
    let focus: AccountWindow.StandardWindow?

    var body: some View {
        if let account = environment.accountDetails(accountID) {
            content(account)
        } else {
            ContentUnavailableView(
                "Account Unavailable", systemImage: "person.crop.circle.badge.questionmark",
                description: Text("The Collector Mac no longer publishes this account."))
        }
    }

    private func content(_ account: AccountDetails) -> some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    LabeledContent(
                        "Product", value: ReaderVocabulary.productName(account.source.product))
                    LabeledContent(
                        "Source", value: ReaderVocabulary.sourceState(account.source.state))
                }
                ForEach(WindowSection.ordered(account)) { section in
                    Section {
                        WindowDetailsView(
                            section: section, source: account.source, accountID: account.account.id,
                            environment: environment,
                            emphasized: focus.map { .standard($0) } == section.id)
                    }
                    .id(section.id)
                }
                if let line = environment.refresh.flatMap({
                    RefreshFeedback.line(
                        for: account.source.product, accountID: accountID, in: $0)
                }) {
                    Section("Refresh") {
                        Text(line).accessibilityIdentifier("accountRefreshResult")
                    }
                }
                ProvenanceSection(
                    source: account.source, macLive: environment.details.macLive,
                    transport: environment.details.transport,
                    lastSyncedAt: environment.details.lastSyncedAt)
            }
            .onAppear {
                if let focus {
                    proxy.scrollTo(WindowSection.Identity.standard(focus), anchor: .top)
                }
            }
        }
        .navigationTitle(account.account.effectiveDisplayLabel)
        .refreshable { await environment.pullToRefresh(account: accountID) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await environment.refreshAccount(accountID) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(environment.refresh?.isRunning == true)
                .accessibilityIdentifier("accountRefresh")
            }
        }
    }
}

/// One Window Details section.
private struct WindowDetailsView: View {
    let section: WindowSection
    let source: AccountSource
    let accountID: AccountID
    @ObservedObject var environment: ReaderEnvironment
    let emphasized: Bool
    @State private var remindersEnabled: Bool?
    @State private var liveActivityRunning = false
    @State private var liveActivityMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AllowanceRing(display: section.display, diameter: 58, emphasized: emphasized)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title).font(.headline)
                Text(section.display.percentText.map { "\($0) used" } ?? "No percentage")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                StateBadge(display: section.display)
                if let window = section.details?.window {
                    reset(window)
                    if let observed = window.observation?.observedAt {
                        Text("Last Updated \(Text(observed, style: .relative)) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                reminderToggle
                liveActivityControl
                if let liveActivityMessage {
                    Text(liveActivityMessage).font(.caption).foregroundStyle(.secondary)
                }
                if section.ambiguous {
                    Text("More than one provider window matches this window, so none is shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let explanation = section.display.explanation(source: source) {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(windowAccessibilityLabel)
        .accessibilityIdentifier("windowDetails.\(section.title)")
        .accessibilityAddTraits(emphasized ? .isSelected : [])
        .task(id: selection.versionedID) {
            remindersEnabled = await environment.notificationOptIn(selection)
            if case .standard(let accountWindow) = selection {
                liveActivityRunning = await environment.liveActivityRunning(accountWindow)
            }
        }
    }

    private var selection: WindowSelection {
        switch section.id {
        case .standard(let standard):
            .standard(AccountWindow(accountID: accountID, window: standard))
        case .additional(let id): .additional(id)
        }
    }

    private var windowAccessibilityLabel: String {
        let reading = section.display.percentText.map { "\($0) used" } ?? "No percentage"
        return "\(section.title), \(reading), \(section.display.statusText)"
    }

    @ViewBuilder private var reminderToggle: some View {
        if section.details != nil, source.state != .incompatible {
            Toggle(
                "Reset Reminder",
                isOn: Binding(
                    get: { remindersEnabled ?? false },
                    set: { enabled in
                        remindersEnabled = enabled
                        Task {
                            _ = await environment.setNotificationOptIn(selection, enabled: enabled)
                        }
                    })
            )
            .font(.caption)
            .accessibilityIdentifier("resetReminder.\(selection.versionedID)")
        }
    }

    @ViewBuilder private var liveActivityControl: some View {
        if let accountWindow = liveActivityWindow {
            Button(liveActivityRunning ? "Stop Live Activity" : "Start Live Activity") {
                Task {
                    let outcome = await environment.toggleLiveActivity(accountWindow)
                    liveActivityRunning = await environment.liveActivityRunning(accountWindow)
                    switch outcome {
                    case .unavailable:
                        liveActivityMessage =
                            "A fresh reading with a reset in the next eight hours is required."
                    case .failed:
                        liveActivityMessage = "The Live Activity could not be started."
                    case .started, .alreadyRunning, nil:
                        liveActivityMessage = nil
                    }
                }
            }
            .font(.caption)
            .accessibilityIdentifier("liveActivity.\(accountWindow.accountID.hex)")
        }
    }

    private var liveActivityWindow: AccountWindow? {
        guard environment.hasWatchStage, case .standard(let accountWindow) = selection,
            accountWindow.window == .fiveHour, section.details?.window.resetsAt != nil
        else { return nil }
        return accountWindow
    }

    @ViewBuilder private func reset(_ window: AllowanceWindow) -> some View {
        if let resetsAt = window.resetsAt {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(alignment: .leading, spacing: 2) {
                    if resetsAt > timeline.date {
                        Text("Resets in \(Text(resetsAt, style: .relative))")
                    } else {
                        Text("Reset time passed")
                    }
                    Text(resetsAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

/// Acquisition source, the Collector Mac's publication status, Last Synced on this device,
/// and compatibility; versions and delivery detail sit behind a disclosure.
private struct ProvenanceSection: View {
    let source: AccountSource
    let macLive: Bool?
    let transport: TransportStatus
    let lastSyncedAt: Date?

    var body: some View {
        Section("Provenance & Sync") {
            LabeledContent("Acquired by", value: ReaderVocabulary.sourceName(source.kind))
                .accessibilityIdentifier("provenance.source")
            LabeledContent("Collector Mac", value: ReaderVocabulary.macPublication(macLive))
            LabeledContent("Last Synced") {
                if let lastSyncedAt {
                    Text("\(Text(lastSyncedAt, style: .relative)) ago")
                } else {
                    Text("Not yet")
                }
            }
            LabeledContent("Compatibility", value: ReaderVocabulary.compatibility(source.state))
            if ReaderVocabulary.isSyncProblem(transport) {
                Label(ReaderVocabulary.transport(transport), systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("syncProblem")
            }
            DisclosureGroup("Diagnostics") {
                LabeledContent("Source version", value: source.version)
                LabeledContent("Delivery", value: ReaderVocabulary.transport(transport))
            }
        }
    }
}
