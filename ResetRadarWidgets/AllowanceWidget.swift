// This file keeps the App Intent entity/query and both WidgetKit configurations together because
// they share the cache-only selection contract.
// swiftlint:disable file_length
import AppIntents
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarScheduling
import ResetRadarStorage
import ResetRadarTransport
import ResetRadarUI
import SwiftUI
import WidgetKit

/// A persistent App Intent identity for a window. The extension reconstructs an unavailable
/// selection rather than changing a saved additional window to a sibling.
struct WidgetWindowEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Allowance Window")
    static let defaultQuery = WidgetWindowQuery()

    let id: String
    let label: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }
}

struct WidgetWindowQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetWindowEntity] {
        let labels = await WidgetCache.labels()
        return identifiers.map {
            WidgetWindowEntity(id: $0, label: labels[$0] ?? "Unavailable")
        }
    }

    func suggestedEntities() async throws -> [WidgetWindowEntity] {
        await WidgetCache.selections()
    }
}

struct WidgetAccountEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = WidgetAccountQuery()

    let id: String
    let label: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        let labels = await WidgetCache.accountLabels()
        return identifiers.map { WidgetAccountEntity(id: $0, label: labels[$0] ?? "Unavailable") }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        await WidgetCache.accounts()
    }
}

struct AllowanceWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Allowance Window"
    static let description = IntentDescription("Shows a cached Reset Radar allowance window.")

    @Parameter(title: "Window") var window: WidgetWindowEntity?

    init() {}
}

struct StandardAllowanceWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account Windows"
    static let description = IntentDescription("Shows cached five-hour and weekly windows.")

    @Parameter(title: "Account") var account: WidgetAccountEntity?

    init() {}
}

/// A cache-only Shortcut/Siri result for any exact saved window selection. It deliberately does
/// not construct a relay client: App Intents can be invoked while the main app is not running.
struct ReadAllowanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Allowance"
    static let description = IntentDescription("Reads a cached Reset Radar allowance window.")
    static let openAppWhenRun = false

    @Parameter(title: "Window") var window: WidgetWindowEntity

    init() {}

    init(window: WidgetWindowEntity) {
        self.window = window
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let selection = WindowSelection(versionedID: window.id),
            let value = await WidgetCache.value(for: selection, at: .now)
        else {
            return .result(dialog: "That cached allowance window is unavailable.")
        }
        let percentage =
            value.window.observation.map {
                PercentageUsedFormatter.text(
                    $0.usedPercent, product: value.source.product,
                    fractionDigits: $0.fractionDigits) + " used"
            } ?? "no percentage"
        let reset =
            value.window.resetsAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
            ?? "no reset time"
        let observed =
            value.window.observation?.observedAt.formatted(
                date: .abbreviated, time: .shortened) ?? "no observation"
        let product = value.source.product == .codex ? "Codex" : "Claude Code"
        let sourceState: String
        switch value.source.state {
        case .reporting: sourceState = "reporting"
        case .unavailable: sourceState = "unavailable"
        case .signedOut: sourceState = "signed out"
        case .sourceOffline: sourceState = "offline"
        case .incompatible: sourceState = "incompatible"
        }
        let presentation: String
        switch value.presentation {
        case .current: presentation = "current"
        case .stale: presentation = "stale"
        case .resetAwaitingRefresh: presentation = "reset awaiting refresh"
        case .unavailable: presentation = "unavailable"
        }
        let summary =
            "\(value.label), \(product): \(percentage), reset \(reset), \(presentation), "
            + "source \(sourceState), observed \(observed)."
        return .result(
            dialog: "\(summary)"
        )
    }
}

struct AllowanceWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let status: String
    let resetsAt: Date?
    let nextChange: Date?
}

struct AllowanceWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AllowanceWidgetEntry {
        AllowanceWidgetEntry(
            date: .now, title: "Reset Radar", status: "No cached window", resetsAt: nil,
            nextChange: nil)
    }

    func snapshot(
        for configuration: AllowanceWidgetIntent, in context: Context
    ) async -> AllowanceWidgetEntry {
        await entry(for: configuration, at: .now)
    }

    func timeline(for configuration: AllowanceWidgetIntent, in context: Context) async -> Timeline<
        AllowanceWidgetEntry
    > {
        await WidgetCache.refresh()
        let currentEntry = await entry(for: configuration, at: .now)
        guard await WidgetCache.reloadAllowed() else {
            return Timeline(entries: [currentEntry], policy: .never)
        }
        let routine = currentEntry.date.addingTimeInterval(1_800)
        var entries = [currentEntry]
        var nextChange = currentEntry.nextChange
        while let next = nextChange, next < routine, entries.count < 4 {
            guard next > (entries.last?.date ?? currentEntry.date) else { break }
            let transition = await entry(for: configuration, at: next)
            entries.append(transition)
            nextChange = transition.nextChange
        }
        return Timeline(entries: entries, policy: .after(routine))
    }

    private func entry(
        for configuration: AllowanceWidgetIntent, at date: Date
    ) async -> AllowanceWidgetEntry {
        guard let id = configuration.window?.id, let selection = WindowSelection(versionedID: id)
        else {
            return AllowanceWidgetEntry(
                date: date, title: "Reset Radar", status: "Choose a window in Edit Widget",
                resetsAt: nil, nextChange: nil)
        }
        guard let value = await WidgetCache.value(for: selection, at: date)
        else {
            return AllowanceWidgetEntry(
                date: date, title: "Reset Radar", status: "Cached window unavailable",
                resetsAt: nil, nextChange: nil
            )
        }
        let percentage =
            value.window.observation.map {
                PercentageUsedFormatter.text(
                    $0.usedPercent, product: value.source.product,
                    fractionDigits: $0.fractionDigits) + " used"
            } ?? "No percentage"
        let status: String
        switch value.presentation {
        case .current: status = percentage
        case .stale: status = "Stale · \(percentage)"
        case .resetAwaitingRefresh: status = "Reset time passed"
        case .unavailable: status = "Unavailable"
        }
        return AllowanceWidgetEntry(
            date: date, title: value.label, status: status, resetsAt: value.window.resetsAt,
            nextChange: value.nextChange)
    }
}

private enum WidgetCache {
    static let appGroup = "group.com.unidentifiedstealthstartup.ResetRadar"
    static var flavor: StorageLocations.Flavor {
        #if DEBUG
            .debug
        #else
            .release
        #endif
    }

    static func snapshot() async -> UsageSnapshot? {
        guard
            let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        let store = FileReaderStore(locations: StorageLocations(root: root, flavor: flavor))
        guard let state = try? await store.load(), state.pairing != nil, !state.awaitingActivation,
            !state.forgetCleanupPending
        else { return nil }
        return state.snapshot
    }

    static func reloadAllowed() async -> Bool {
        guard
            let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup),
            let state = try? await FileReaderStore(
                locations: StorageLocations(root: root, flavor: flavor)
            ).load()
        else { return false }
        return state.pairing != nil && !state.awaitingActivation && !state.forgetCleanupPending
    }

    /// WidgetKit may call this only opportunistically. `IngestRelaySnapshot` enforces the shared
    /// widget refresh policy and commits atomically before this extension renders cached data.
    static func refresh() async {
        guard
            let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup),
            let defaults = UserDefaults(suiteName: appGroup),
            let accessGroup = Bundle.main.object(
                forInfoDictionaryKey: "ResetRadarKeychainAccessGroup") as? String,
            accessGroup.hasSuffix(appGroup), !accessGroup.contains("$(")
        else { return }
        let locations = StorageLocations(root: root, flavor: flavor)
        let clock = WidgetClock()
        let reader = FileReaderStore(locations: locations)
        let visible = VisibleSnapshot(
            snapshots: ReaderSnapshotStore(store: reader), reader: reader)
        let scheduler = SystemNotificationScheduler()
        let notifications = ReconcileResetNotifications(
            visible: visible,
            preferences: DefaultsPreferenceStore(defaults: defaults), scheduler: scheduler,
            gate: FileNotificationReconcileGate(locations: locations, clock: clock), clock: clock)
        let pipeline = AfterCommitPipeline(
            reader: reader, reloader: WidgetSurfaceReloader(), notifications: notifications,
            liveActivities: WidgetNoOpStep(), watch: nil)
        let ingest = IngestRelaySnapshot(
            reader: reader, secrets: KeychainSecretStore(accessGroup: accessGroup),
            cipher: AESGCMEnvelopeCipher(), relay: HTTPRelayGateway(),
            random: CryptoSecretGenerator(),
            clock: clock, diagnostics: LogDiagnosticsSink(locations: locations),
            afterCommit: pipeline)
        _ = await ingest.run(trigger: .widgetReload, inAppProcess: false)
    }

    static func selections() async -> [WidgetWindowEntity] {
        guard let snapshot = await snapshot() else { return [] }
        let standard = AccountDisplayOrder.sorted(snapshot.accounts).flatMap { account in
            AccountWindow.StandardWindow.allCases.compactMap { window -> WindowSelection? in
                let accountWindow = AccountWindow(accountID: account.id, window: window)
                guard
                    case .window = AccountWindowResolver.resolve(
                        accountWindow, in: snapshot, now: .now
                    ).0
                else { return nil }
                return .standard(accountWindow)
            }
        }
        let additional = snapshot.windows.filter { !$0.isDefaultLimit }.map {
            WindowSelection.additional($0.id)
        }
        return (standard + additional).map {
            WidgetWindowEntity(id: $0.versionedID, label: label(for: $0, in: snapshot))
        }
    }

    static func labels() async -> [String: String] {
        guard await snapshot() != nil else { return [:] }
        return await selections().reduce(into: [:]) { $0[$1.id] = $1.label }
    }

    static func accounts() async -> [WidgetAccountEntity] {
        guard let snapshot = await snapshot() else { return [] }
        return AccountDisplayOrder.sorted(snapshot.accounts).map {
            WidgetAccountEntity(id: $0.id.hex, label: $0.effectiveDisplayLabel)
        }
    }

    static func accountLabels() async -> [String: String] {
        Dictionary(uniqueKeysWithValues: await accounts().map { ($0.id, $0.label) })
    }

    struct Value {
        let label: String
        let source: AccountSource
        let window: AllowanceWindow
        let presentation: PresentationState
        let nextChange: Date?
    }

    static func value(for selection: WindowSelection, at now: Date) async -> Value? {
        guard
            let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        let reader = FileReaderStore(locations: StorageLocations(root: root, flavor: flavor))
        let query = LoadWindowSelection(
            visible: VisibleSnapshot(
                snapshots: ReaderSnapshotStore(store: reader), reader: reader),
            clock: WidgetClock(now: now))
        guard case .window(let account, let source, let details) = await query.load(selection)
        else { return nil }
        return Value(
            label: label(for: selection, account: account, window: details.window), source: source,
            window: details.window, presentation: details.presentation,
            nextChange: details.nextChange)
    }

    static func label(for selection: WindowSelection, in snapshot: UsageSnapshot) -> String {
        let account =
            snapshot.accounts.first { $0.id == selection.accountID }?.effectiveDisplayLabel
            ?? "Account"
        let window: AllowanceWindow?
        switch selection {
        case .standard: window = nil
        case .additional(let id): window = snapshot.windows.first { $0.id == id }
        }
        return label(for: selection, accountLabel: account, window: window)
    }

    private static func label(
        for selection: WindowSelection, account: AccountMetadata, window: AllowanceWindow
    ) -> String {
        label(for: selection, accountLabel: account.effectiveDisplayLabel, window: window)
    }

    private static func label(
        for selection: WindowSelection, accountLabel: String, window: AllowanceWindow?
    ) -> String {
        switch selection {
        case .standard(let accountWindow):
            return "\(accountLabel) · \(accountWindow.window == .fiveHour ? "5-hour" : "Weekly")"
        case .additional(let id):
            return "\(accountLabel) · \(window?.label ?? id.limitID)"
        }
    }
}

private struct WidgetClock: AppClock {
    let now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

private struct WidgetSurfaceReloader: SurfaceReloader {
    func reloadWidgets() {}
    func reloadComplications() {}
}

private struct WidgetNoOpStep: AfterCommitStep {
    func afterCommitOutcome(_ event: CommitEvent) async -> AfterCommitOutcome { .complete }
}

struct AllowanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.unidentifiedstealthstartup.ResetRadar.allowance",
            intent: AllowanceWidgetIntent.self, provider: AllowanceWidgetProvider()
        ) { entry in
            AllowanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Allowance")
        .description("A cached Reset Radar allowance window.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct StandardAllowanceWidgetEntry: TimelineEntry {
    let date: Date
    let account: String
    let fiveHour: String
    let weekly: String
    let nextChange: Date?
}

struct StandardAllowanceWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StandardAllowanceWidgetEntry {
        StandardAllowanceWidgetEntry(
            date: .now, account: "Account", fiveHour: "5-hour · No cached window",
            weekly: "Weekly · No cached window", nextChange: nil)
    }

    func snapshot(
        for configuration: StandardAllowanceWidgetIntent, in context: Context
    ) async -> StandardAllowanceWidgetEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: StandardAllowanceWidgetIntent, in context: Context
    ) async -> Timeline<StandardAllowanceWidgetEntry> {
        await WidgetCache.refresh()
        let current = await entry(for: configuration, at: .now)
        guard await WidgetCache.reloadAllowed() else {
            return Timeline(entries: [current], policy: .never)
        }
        let routine = current.date.addingTimeInterval(1_800)
        var entries = [current]
        var nextChange = current.nextChange
        while let next = nextChange, next < routine, entries.count < 4 {
            guard next > (entries.last?.date ?? current.date) else { break }
            let transition = await entry(for: configuration, at: next)
            entries.append(transition)
            nextChange = transition.nextChange
        }
        return Timeline(entries: entries, policy: .after(routine))
    }

    private func entry(
        for configuration: StandardAllowanceWidgetIntent, at date: Date = .now
    ) async -> StandardAllowanceWidgetEntry {
        guard let id = configuration.account?.id, let accountID = AccountID(hex: id),
            let snapshot = await WidgetCache.snapshot()
        else {
            return StandardAllowanceWidgetEntry(
                date: date, account: "Reset Radar", fiveHour: "Choose an account",
                weekly: "Choose an account", nextChange: nil)
        }
        let name =
            snapshot.accounts.first { $0.id == accountID }?.effectiveDisplayLabel ?? "Unavailable"
        let five = await WidgetCache.value(
            for: .standard(AccountWindow(accountID: accountID, window: .fiveHour)), at: date)
        let weekly = await WidgetCache.value(
            for: .standard(AccountWindow(accountID: accountID, window: .weekly)), at: date)
        return StandardAllowanceWidgetEntry(
            date: date, account: name, fiveHour: standardText("5-hour", value: five),
            weekly: standardText("Weekly", value: weekly),
            nextChange: [five?.nextChange, weekly?.nextChange]
                .compactMap { $0 }.filter { $0 > date }.min())
    }

    private func standardText(_ label: String, value: WidgetCache.Value?) -> String {
        guard let value else { return "\(label) · Unavailable" }
        let percentage =
            value.window.observation.map {
                PercentageUsedFormatter.text(
                    $0.usedPercent, product: value.source.product,
                    fractionDigits: $0.fractionDigits) + " used"
            } ?? "No percentage"
        switch value.presentation {
        case .current: return "\(label) · \(percentage)"
        case .stale: return "\(label) · Stale · \(percentage)"
        case .resetAwaitingRefresh: return "\(label) · Reset time passed"
        case .unavailable: return "\(label) · Unavailable"
        }
    }
}

struct StandardAllowanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.unidentifiedstealthstartup.ResetRadar.standard-windows",
            intent: StandardAllowanceWidgetIntent.self, provider: StandardAllowanceWidgetProvider()
        ) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.account).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(entry.fiveHour).font(.caption)
                Text(entry.weekly).font(.caption)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Standard Windows")
        .description("Five-hour and weekly cached windows for one account.")
        .supportedFamilies([.systemMedium])
    }
}

private struct AllowanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AllowanceWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 2 : 6) {
            Text(entry.title)
                .font(family == .accessoryRectangular ? .caption : .headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.status).font(.caption).foregroundStyle(.secondary)
            if let resetsAt = entry.resetsAt, resetsAt > entry.date {
                Text(timerInterval: entry.date...resetsAt, countsDown: true)
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
