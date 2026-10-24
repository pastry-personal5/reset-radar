import Foundation
import ResetRadarDomain

public enum ClaudeCodeSourceError: Error, Equatable, Sendable {
    case stopped
}

/// The exhaustive failure table behind `ClaudeCodeSource`. Status-line data can never prove
/// `signedOut`, and every case maps to exactly one source state and one redacted diagnostic.
enum ClaudeCodeSourceFailure: Error, Equatable {
    /// Setup has not run, was restored, or the helper copy is missing or mismatched.
    case notInstalled
    /// No session has produced a usable normal window yet.
    case noObservation
    /// A malformed, incompatible, unsafe, or over-bound recognized record.
    case malformed
    /// Two exact-time observations disagree beyond report state.
    case conflict
    case permissionDenied
    case temporarilyUnavailable

    var state: SourceState {
        switch self {
        case .notInstalled, .noObservation: .unavailable
        case .malformed, .conflict: .incompatible
        case .permissionDenied, .temporarilyUnavailable: .sourceOffline
        }
    }

    /// nil when the failure is an ordinary absence rather than something to diagnose.
    var diagnosticClass: ProviderFailureClass? {
        switch self {
        case .noObservation: nil
        case .notInstalled: .notInstalled
        case .malformed: .malformed
        case .conflict: .incompatible
        case .permissionDenied: .permissionDenied
        case .temporarilyUnavailable: .temporarilyUnavailable
        }
    }

    /// Only operational failures revalidate on the backoff ladder; the rest wait for data or
    /// a configuration change.
    var retriesWithBackoff: Bool { state == .sourceOffline }

    init(_ error: SessionScanError) {
        switch error {
        case .permissionDenied: self = .permissionDenied
        case .unavailable: self = .temporarilyUnavailable
        case .incompatible: self = .malformed
        }
    }

    init(_ error: DirectoryWatchError) {
        self = error == .permissionDenied ? .permissionDenied : .temporarilyUnavailable
    }
}

/// The one-, two-, five-, then fifteen-minute revalidation ladder, shared with Codex's restarts.
struct ClaudeCodeRevalidationSchedule: Equatable {
    static let delays: [TimeInterval] = [60, 120, 300, 900]

    private(set) var failureCount = 0

    mutating func nextDeadline(after failedAt: Date) -> Date {
        let index = min(failureCount, Self.delays.count - 1)
        failureCount += 1
        return failedAt.addingTimeInterval(Self.delays[index])
    }

    mutating func reset() { failureCount = 0 }
}
