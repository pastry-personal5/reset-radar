import Foundation
import ResetRadarDomain

public enum SessionMergeError: Error, Equatable, Sendable {
    /// Two exact-time observations disagree on more than their report state.
    case conflictingObservations
    /// A merged window failed Domain validation.
    case invalidWindow
}

/// The per-kind freshest view across every session, ready for a `SourceSnapshot`.
public struct MergedUsage: Equatable, Sendable {
    public let windows: [AllowanceWindow]
    /// The public version on the newest selected observation; nil when there is no window.
    public let version: String?
}

/// Selects each limit kind's newest observation across sessions. Ties never depend on file name,
/// enumeration, or locale order.
public struct SessionMerger: Sendable {
    private let accountID: AccountID

    public init(accountID: AccountID) {
        self.accountID = accountID
    }

    public func merge(_ records: [SessionRecord]) throws(SessionMergeError) -> MergedUsage {
        var byKind: [String: [SessionWindow]] = [:]
        for window in records.flatMap(\.windows) { byKind[window.kind, default: []].append(window) }
        var selected: [SessionWindow] = []
        for kind in byKind.keys.sorted() {
            selected.append(try Self.newest(byKind[kind] ?? []))
        }
        var windows: [AllowanceWindow] = []
        for window in selected { windows.append(try allowanceWindow(window)) }
        let newest = selected.max { lhs, rhs in
            (lhs.observedAt, lhs.sourceVersion) < (rhs.observedAt, rhs.sourceVersion)
        }
        return MergedUsage(windows: windows, version: newest?.sourceVersion)
    }

    private static func newest(
        _ candidates: [SessionWindow]
    ) throws(SessionMergeError) -> SessionWindow {
        guard let latest = candidates.map(\.observedAt).max() else {
            throw .conflictingObservations
        }
        let tied = candidates.filter { $0.observedAt == latest }
        guard var chosen = tied.first else { throw .conflictingObservations }
        for other in tied.dropFirst() {
            guard other.equalIgnoringReportState(chosen) else { throw .conflictingObservations }
            if other.reportState == .reported { chosen = other }
        }
        return chosen
    }

    private func allowanceWindow(
        _ window: SessionWindow
    ) throws(SessionMergeError) -> AllowanceWindow {
        let raw = RawWindow(
            accountID: accountID.hex, product: ProductID.claudeCode.rawValue, accountScope: nil,
            limitID: window.kind, label: nil, durationMinutes: window.durationMinutes,
            isDefaultLimit: true, reportState: window.reportState, resetsAt: window.resetsAt,
            observation: RawObservation(
                usedPercent: window.usedPercent, observedAt: window.observedAt,
                sourceVersion: window.sourceVersion, fractionDigits: 1),
            providerLimitState: nil)
        do {
            return try AllowanceWindow(validating: raw)
        } catch {
            throw .invalidWindow
        }
    }
}

extension SessionWindow {
    fileprivate func equalIgnoringReportState(_ other: SessionWindow) -> Bool {
        kind == other.kind && usedPercent == other.usedPercent && resetsAt == other.resetsAt
            && observedAt == other.observedAt && sourceVersion == other.sourceVersion
    }
}
