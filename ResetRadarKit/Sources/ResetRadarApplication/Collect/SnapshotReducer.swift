import Foundation
import ResetRadarDomain

public struct SnapshotAssemblyContext: Sendable {
    public let accounts: [AccountMetadata]
    public let publisherID: PublisherID
    public let heartbeatSeconds: Int
    public let now: Date

    public init(
        accounts: [AccountMetadata], publisherID: PublisherID, heartbeatSeconds: Int, now: Date
    ) {
        self.accounts = accounts
        self.publisherID = publisherID
        self.heartbeatSeconds = heartbeatSeconds
        self.now = now
    }
}

/// Merges source reports into the authoritative snapshot and classifies what changed. Pure.
public enum SnapshotReducer {
    public static func reduce(
        previous: UsageSnapshot?, reports: [SourceSnapshot], context: SnapshotAssemblyContext
    ) throws(UsageSnapshotError) -> (snapshot: UsageSnapshot, change: ChangeClass) {
        let accounts = context.accounts
        let now = context.now
        var sources = previous?.sources ?? []
        var windows = previous?.windows ?? []
        var diagnostics: [DiagnosticEvent] = []
        let accountIDs = Set(accounts.map(\.id))
        sources.removeAll { !accountIDs.contains($0.accountID) }
        windows.removeAll { !accountIDs.contains($0.accountID) }
        for account in accounts where !sources.contains(where: { $0.accountID == account.id }) {
            sources.append(
                AccountSource(
                    accountID: account.id, product: account.product,
                    kind: account.product == .codex ? .codexAppServer : .claudeCodeStatusLine,
                    version: "", state: .unavailable))
        }
        for report in reports {
            merge(report.source, into: &sources)
            if report.clearsWindows {
                windows.removeAll { $0.accountID == report.source.accountID }
            }
            guard report.isCompleteReport else { continue }
            let accepted = acceptedWindows(of: report, now: now, diagnostics: &diagnostics)
            windows = merged(windows, with: accepted, accountID: report.source.accountID)
        }
        windows.removeAll { isExpiredRetained($0, now: now) }
        let results = ManualRefreshResults.retained(previous?.manualRefreshResults ?? [], now: now)
        let snapshot = try UsageSnapshot(
            publisherID: context.publisherID, generatedAt: now,
            heartbeatSeconds: context.heartbeatSeconds,
            accounts: accounts, sources: sources, windows: windows, diagnostics: diagnostics,
            manualRefreshResults: results)
        return (snapshot, classify(previous: previous, current: snapshot))
    }

    private static func merge(_ source: AccountSource, into sources: inout [AccountSource]) {
        if let index = sources.firstIndex(where: { $0.accountID == source.accountID }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
    }

    /// Drops a window of another product and any duplicate `WindowID`, each with a diagnostic.
    private static func acceptedWindows(
        of report: SourceSnapshot, now: Date, diagnostics: inout [DiagnosticEvent]
    ) -> [AllowanceWindow] {
        var seen: Set<WindowID> = []
        var accepted: [AllowanceWindow] = []
        for window in report.windows {
            let belongsToSource =
                window.accountID == report.source.accountID
                && window.product == report.source.product
            if !belongsToSource {
                diagnostics.append(
                    .invalidWindow(.unknownProduct, product: report.source.product, at: now))
            } else if !seen.insert(window.id).inserted {
                diagnostics.append(
                    .duplicateWindow(
                        accountID: window.accountID, product: window.product, at: now))
            } else {
                accepted.append(window)
            }
        }
        return accepted
    }

    private static func merged(
        _ existing: [AllowanceWindow], with accepted: [AllowanceWindow], accountID: AccountID
    ) -> [AllowanceWindow] {
        let reportedScopes = Set(accepted.compactMap(\.scope))
        let replacedDefaults = Set(
            accepted.filter(\.isDefaultLimit).map {
                DefaultSlot(accountID: $0.accountID, minutes: $0.durationMinutes)
            })
        var remaining = Dictionary(
            accepted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [AllowanceWindow] = []
        for window in existing {
            if window.accountID != accountID {
                result.append(window)
            } else if let replacement = remaining.removeValue(forKey: window.id) {
                result.append(replacement)
            } else if isFromReplacedScope(window, reportedScopes: reportedScopes) {
                continue  // an account-scope change: the prior scope's windows are never merged
            } else if movedDefault(window, in: replacedDefaults) {
                continue  // the default bucket moved: exactly one default per duration remains
            } else {
                result.append(window.markingRetained())
            }
        }
        result += accepted.filter { remaining[$0.id] != nil }
        return result
    }

    private static func movedDefault(
        _ window: AllowanceWindow, in slots: Set<DefaultSlot>
    ) -> Bool {
        window.isDefaultLimit
            && slots.contains(
                DefaultSlot(accountID: window.accountID, minutes: window.durationMinutes))
    }

    private struct DefaultSlot: Hashable {
        let accountID: AccountID
        let minutes: Int?
    }

    private static func isFromReplacedScope(
        _ window: AllowanceWindow, reportedScopes: Set<AccountScope>
    ) -> Bool {
        guard let scope = window.scope else { return false }
        return !reportedScopes.isEmpty && !reportedScopes.contains(scope)
    }

    /// A retained non-standard window is dropped once its reset passes, or at once if it has no
    /// reset instant. A retained standard window stays; Domain shows it unavailable.
    private static func isExpiredRetained(_ window: AllowanceWindow, now: Date) -> Bool {
        guard window.reportState == .retained, !isStandardWindow(window) else { return false }
        guard let resetsAt = window.resetsAt else { return true }
        return resetsAt <= now
    }

    private static func isStandardWindow(_ window: AllowanceWindow) -> Bool {
        window.isDefaultLimit
            && AccountWindow.StandardWindow.allCases.contains {
                $0.durationMinutes == window.durationMinutes
            }
    }

    static func classify(previous: UsageSnapshot?, current: UsageSnapshot) -> ChangeClass {
        guard let previous else { return .transition }
        guard previous.sources == current.sources else { return .transition }
        let old = Dictionary(
            previous.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(
            current.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard Set(old.keys) == Set(new.keys) else { return .transition }
        var change = ChangeClass.none
        for (id, before) in old {
            guard let after = new[id] else { continue }
            change = max(change, classify(before: before, after: after))
        }
        return change
    }

    private static func classify(before: AllowanceWindow, after: AllowanceWindow) -> ChangeClass {
        if before.reportState != after.reportState { return .transition }
        let materialChange =
            before.resetsAt != after.resetsAt
            || before.observation?.usedPercent != after.observation?.usedPercent
            || before.providerLimitState != after.providerLimitState || before.label != after.label
        if materialChange { return .material }
        return before.observation?.observedAt != after.observation?.observedAt
            ? .observationOnly : .none
    }
}
