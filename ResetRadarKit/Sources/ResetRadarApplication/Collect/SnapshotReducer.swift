import Foundation
import ResetRadarDomain

/// Merges source reports into the authoritative snapshot and classifies what changed. Pure.
public enum SnapshotReducer {
    public static func reduce(
        previous: UsageSnapshot?, reports: [SourceSnapshot], publisherID: PublisherID,
        heartbeatSeconds: Int, now: Date
    ) throws(UsageSnapshotError) -> (snapshot: UsageSnapshot, change: ChangeClass) {
        var sources = previous?.sources ?? []
        var windows = previous?.windows ?? []
        var diagnostics: [DiagnosticEvent] = []
        for report in reports {
            merge(report.source, into: &sources)
            guard report.isCompleteReport else { continue }
            let accepted = acceptedWindows(of: report, now: now, diagnostics: &diagnostics)
            windows = merged(windows, with: accepted, product: report.source.product)
        }
        windows.removeAll { isExpiredRetained($0, now: now) }
        let results = ManualRefreshResults.retained(previous?.manualRefreshResults ?? [], now: now)
        let snapshot = try UsageSnapshot(
            publisherID: publisherID, generatedAt: now, heartbeatSeconds: heartbeatSeconds,
            sources: sources, windows: windows, diagnostics: diagnostics,
            manualRefreshResults: results)
        return (snapshot, classify(previous: previous, current: snapshot))
    }

    private static func merge(_ source: ProductSource, into sources: inout [ProductSource]) {
        if let index = sources.firstIndex(where: { $0.product == source.product }) {
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
            if window.product != report.source.product {
                diagnostics.append(
                    .invalidWindow(.unknownProduct, product: report.source.product, at: now))
            } else if !seen.insert(window.id).inserted {
                diagnostics.append(.duplicateWindow(product: window.product, at: now))
            } else {
                accepted.append(window)
            }
        }
        return accepted
    }

    private static func merged(
        _ existing: [AllowanceWindow], with accepted: [AllowanceWindow], product: ProductID
    ) -> [AllowanceWindow] {
        let reportedScopes = Set(accepted.compactMap(\.scope))
        var remaining = Dictionary(
            accepted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [AllowanceWindow] = []
        for window in existing {
            if window.product != product {
                result.append(window)
            } else if let replacement = remaining.removeValue(forKey: window.id) {
                result.append(replacement)
            } else if isFromReplacedScope(window, reportedScopes: reportedScopes) {
                continue  // an account-scope change: the prior scope's windows are never merged
            } else {
                result.append(window.markingRetained())
            }
        }
        result += accepted.filter { remaining[$0.id] != nil }
        return result
    }

    private static func isFromReplacedScope(
        _ window: AllowanceWindow, reportedScopes: Set<AccountScope>
    ) -> Bool {
        guard let scope = window.scope else { return false }
        return !reportedScopes.isEmpty && !reportedScopes.contains(scope)
    }

    /// A retained window that resolves to no Home slot is dropped once its reset passes, or at
    /// once if it has no reset instant. A retained Home window stays; Domain shows it unavailable.
    private static func isExpiredRetained(_ window: AllowanceWindow, now: Date) -> Bool {
        guard window.reportState == .retained, !isHomeWindow(window) else { return false }
        guard let resetsAt = window.resetsAt else { return true }
        return resetsAt <= now
    }

    private static func isHomeWindow(_ window: AllowanceWindow) -> Bool {
        window.isDefaultLimit
            && HomeSlot.allCases.contains {
                $0.product == window.product && $0.durationMinutes == window.durationMinutes
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
