import AppIntents
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarStorage
import ResetRadarUI
import SwiftUI
import WidgetKit

@main
struct ResetRadarWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AllowanceComplication()
    }
}

enum ComplicationWindow: String, AppEnum {
    case fiveHour
    case weekly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Allowance Window")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fiveHour: "Five-hour", .weekly: "Weekly",
    ]

    var standardWindow: AccountWindow.StandardWindow {
        self == .fiveHour ? .fiveHour : .weekly
    }
}

struct AllowanceComplicationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Allowance"
    static let description = IntentDescription(
        "Choose the account and allowance window to display.")

    @Parameter(title: "Account") var account: ComplicationAccount?
    @Parameter(title: "Window", default: .fiveHour) var window: ComplicationWindow
}

struct ComplicationAccount: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = ComplicationAccountQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ComplicationAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ComplicationAccount] {
        let requested = Set(identifiers)
        return await accounts().filter { requested.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ComplicationAccount] { await accounts() }

    private func accounts() async -> [ComplicationAccount] {
        guard
            let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    "group.com.unidentifiedstealthstartup.ResetRadar")
        else { return [] }
        let cache = FileWatchCacheStore(
            locations: StorageLocations(root: root, flavor: .release))
        let home = await LoadHome(
            visible: VisibleSnapshot(snapshots: WatchSnapshotStore(store: cache)),
            clock: ComplicationClock()
        ).load()
        return home.accounts.map {
            ComplicationAccount(id: $0.account.id.hex, name: $0.account.effectiveDisplayLabel)
        }
    }
}

struct AllowanceComplicationEntry: TimelineEntry {
    let date: Date
    let display: AllowanceDisplay
    let title: String
    let nextChange: Date?
}

struct AllowanceComplicationProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<AllowanceComplicationIntent>] { [] }

    func placeholder(in context: Context) -> AllowanceComplicationEntry {
        AllowanceComplicationEntry(
            date: .now, display: AllowanceDisplay(state: .unavailable, window: nil),
            title: "Reset Radar", nextChange: nil)
    }

    func snapshot(
        for configuration: AllowanceComplicationIntent, in context: Context
    ) async -> AllowanceComplicationEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: AllowanceComplicationIntent, in context: Context
    ) async -> Timeline<AllowanceComplicationEntry> {
        let entry = await entry(for: configuration)
        let next = ComplicationTimelinePolicy.reloadDate(
            now: entry.date, nextChange: entry.nextChange)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(
        for configuration: AllowanceComplicationIntent
    ) async -> AllowanceComplicationEntry {
        let now = Date()
        guard
            let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    "group.com.unidentifiedstealthstartup.ResetRadar")
        else {
            return AllowanceComplicationEntry(
                date: now, display: AllowanceDisplay(state: .unavailable, window: nil),
                title: "Reset Radar", nextChange: nil)
        }
        let cache = FileWatchCacheStore(locations: StorageLocations(root: root, flavor: .release))
        let home = await LoadHome(
            visible: VisibleSnapshot(snapshots: WatchSnapshotStore(store: cache)),
            clock: ComplicationClock()
        ).load()
        guard let accountID = configuration.account.flatMap({ AccountID(hex: $0.id) }),
            let ring = ComplicationTimelinePolicy.ring(
                selection: ComplicationSelection(
                    accountID: accountID, window: configuration.window.standardWindow),
                in: home),
            let row = home.accounts.first(where: { $0.account.id == accountID })
        else {
            return AllowanceComplicationEntry(
                date: now, display: AllowanceDisplay(state: .unavailable, window: nil),
                title: "Unavailable", nextChange: home.nextChange)
        }
        return AllowanceComplicationEntry(
            date: now, display: AllowanceDisplay(ring: ring),
            title: row.account.effectiveDisplayLabel, nextChange: ring.nextChange)
    }
}

struct AllowanceComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "allowance", intent: AllowanceComplicationIntent.self,
            provider: AllowanceComplicationProvider()
        ) { entry in
            AllowanceComplicationView(entry: entry)
        }
        .configurationDisplayName("Allowance")
        .description("Shows the selected account’s allowance usage.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct AllowanceComplicationView: View {
    let entry: AllowanceComplicationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title).lineLimit(1)
            HStack {
                Text(entry.display.percentText ?? "—").font(.headline).monospacedDigit()
                Image(systemName: entry.display.symbolName)
            }
            Text(entry.display.statusText).font(.caption2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ComplicationClock: AppClock {
    var now: Date { Date() }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
