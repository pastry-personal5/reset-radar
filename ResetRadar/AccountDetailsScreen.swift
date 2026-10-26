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
                            section: section, source: account.source,
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
    let emphasized: Bool

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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("windowDetails.\(section.title)")
        .accessibilityAddTraits(emphasized ? .isSelected : [])
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
