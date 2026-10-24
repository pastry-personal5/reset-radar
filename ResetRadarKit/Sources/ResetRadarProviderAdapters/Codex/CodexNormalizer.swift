import Foundation
import ResetRadarDomain

public struct CodexNormalization: Equatable, Sendable {
    public let snapshot: SourceSnapshot
    public let diagnostics: [DiagnosticEvent]

    public init(snapshot: SourceSnapshot, diagnostics: [DiagnosticEvent]) {
        self.snapshot = snapshot
        self.diagnostics = diagnostics
    }
}

public struct CodexNormalizer: Sendable {
    private struct SelectedBucket {
        let limitID: String
        let bucket: CodexDecodedBucket
        let isDefault: Bool
    }

    private let accountID: AccountID
    private let sourceVersion: String

    public init(accountID: AccountID, sourceVersion: String) {
        self.accountID = accountID
        self.sourceVersion = sourceVersion
    }

    public func normalize(
        _ response: CodexDecodedRateLimits, observedAt: Date
    ) async throws(CodexRateLimitError) -> CodexNormalization {
        let selected = try selectBuckets(response)
        let normalized = try normalizeWindows(
            selected, response: response, observedAt: observedAt)
        return CodexNormalization(
            snapshot: SourceSnapshot(
                source: AccountSource(
                    accountID: accountID, product: .codex, kind: .codexAppServer,
                    version: sourceVersion, state: .reporting,
                    providerScope: response.accountScope),
                windows: normalized.windows, isCompleteReport: true),
            diagnostics: normalized.diagnostics)
    }

    private func normalizeWindows(
        _ selected: [SelectedBucket], response: CodexDecodedRateLimits, observedAt: Date
    ) throws(CodexRateLimitError) -> (
        windows: [AllowanceWindow], diagnostics: [DiagnosticEvent]
    ) {
        var windows: [AllowanceWindow] = []
        var diagnostics: [DiagnosticEvent] = []
        var identities = Set<WindowID>()
        for selection in selected {
            for candidate in [selection.bucket.primary, selection.bucket.secondary] {
                guard let candidate else { continue }
                switch candidate {
                case .rejected(let error):
                    diagnostics.append(
                        .invalidWindow(error.category, product: .codex, at: observedAt))
                case .valid(let decoded):
                    let reset = decoded.resetsAtUnixSeconds.map {
                        Date(timeIntervalSince1970: TimeInterval($0))
                    }
                    let raw = RawWindow(
                        accountID: accountID.hex, product: ProductID.codex.rawValue,
                        accountScope: response.accountScope.hex, limitID: selection.limitID,
                        label: selection.bucket.label,
                        durationMinutes: decoded.durationMinutes,
                        isDefaultLimit: selection.isDefault,
                        reportState: .reported,
                        resetsAt: reset,
                        observation: RawObservation(
                            usedPercent: Double(decoded.usedPercent), observedAt: observedAt,
                            sourceVersion: sourceVersion, fractionDigits: 0),
                        providerLimitState: state(
                            reached: selection.bucket.reached,
                            ordinaryUsageAllowed: response.ordinaryUsageAllowed))
                    let window: AllowanceWindow
                    do {
                        window = try AllowanceWindow(validating: raw)
                    } catch {
                        diagnostics.append(
                            .invalidWindow(error.category, product: .codex, at: observedAt))
                        continue
                    }
                    guard identities.insert(window.id).inserted else { throw .duplicateWindow }
                    windows.append(window)
                }
            }
        }
        guard !windows.isEmpty else { throw .noValidWindows }
        return (windows, diagnostics)
    }

    private func selectBuckets(
        _ response: CodexDecodedRateLimits
    ) throws(CodexRateLimitError) -> [SelectedBucket] {
        guard let buckets = response.buckets, !buckets.isEmpty else {
            guard let limitID = response.compatibility.embeddedLimitID else {
                throw .ambiguousDefaultBucket
            }
            return [
                SelectedBucket(limitID: limitID, bucket: response.compatibility, isDefault: true)
            ]
        }
        let defaultID: String
        if let compatibilityID = response.compatibility.embeddedLimitID {
            guard buckets[compatibilityID] != nil else { throw .ambiguousDefaultBucket }
            defaultID = compatibilityID
        } else {
            let matches = buckets.filter {
                response.compatibility.matchesWithoutIdentity($0.value)
            }
            guard matches.count == 1, let match = matches.first else {
                throw .ambiguousDefaultBucket
            }
            defaultID = match.key
        }
        return buckets.keys.sorted().compactMap { limitID in
            buckets[limitID].map {
                SelectedBucket(limitID: limitID, bucket: $0, isDefault: limitID == defaultID)
            }
        }
    }

    private func state(
        reached: Bool, ordinaryUsageAllowed: Bool?
    ) -> ProviderLimitState {
        if reached { return .reached }
        switch ordinaryUsageAllowed {
        case true: return ProviderLimitState.ordinaryUsageAllowed
        case false: return ProviderLimitState.ordinaryUsageDisallowed
        case nil: return ProviderLimitState.unknown
        }
    }
}
