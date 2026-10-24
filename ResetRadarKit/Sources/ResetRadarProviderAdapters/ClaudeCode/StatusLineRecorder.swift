import Foundation
import ResetRadarDomain

public enum StatusLineRecorderError: Error, Equatable, Sendable {
    case clockRegressed
    case activityDecreased
}

/// Applies the observation-time and dropped-window rules in one locked read-modify-write.
public struct StatusLineRecorder: Sendable {
    private let file: SessionRecordFile
    private let clock: @Sendable () -> Date

    public init(file: SessionRecordFile, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.file = file
        self.clock = clock
    }

    @discardableResult
    public func record(_ input: DecodedStatusLine) throws -> SessionRecord {
        let now = clock()
        let result = try file.update(key: input.sessionKey) { prior in
            try Self.next(from: prior, input: input, now: now)
        }
        guard let result else { throw SessionRecordError.incompatibleRecord }
        return result
    }

    static func next(
        from prior: SessionRecord?, input: DecodedStatusLine, now: Date
    ) throws -> SessionRecord {
        let now = Date(timeIntervalSince1970: (now.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        if let prior {
            let latest = ([prior.lastInvokedAt] + prior.windows.map(\.observedAt)).max()!
            guard now >= latest else { throw StatusLineRecorderError.clockRegressed }
        }
        var increased = false
        if let counter = input.activity, let previous = prior?.lastActivity {
            guard counter >= previous else { throw StatusLineRecorderError.activityDecreased }
            increased = counter > previous
        }
        let firstAppearance = !(prior?.hasHadNormalWindows ?? false) && !input.windows.isEmpty
        let advances = increased || firstAppearance

        let priorByKind = Dictionary(
            uniqueKeysWithValues: (prior?.windows ?? []).map { ($0.kind, $0) })
        let incoming = Dictionary(uniqueKeysWithValues: input.windows.map { ($0.kind, $0) })
        var windows: [SessionWindow] = []
        for (kind, window) in incoming {
            if advances {
                windows.append(
                    SessionWindow(
                        kind: kind, usedPercent: window.usedPercent, resetsAt: window.resetsAt,
                        observedAt: now, sourceVersion: input.version, reportState: .reported))
            } else if let existing = priorByKind[kind] {
                // Values follow Claude Code's display, but the time and version stay with the
                // last response-linked observation.
                windows.append(
                    SessionWindow(
                        kind: kind, usedPercent: window.usedPercent, resetsAt: window.resetsAt,
                        observedAt: existing.observedAt, sourceVersion: existing.sourceVersion,
                        reportState: .reported))
            }
        }
        for (kind, existing) in priorByKind where incoming[kind] == nil {
            windows.append(
                SessionWindow(
                    kind: kind, usedPercent: existing.usedPercent, resetsAt: existing.resetsAt,
                    observedAt: existing.observedAt, sourceVersion: existing.sourceVersion,
                    reportState: .retained))
        }
        return SessionRecord(
            key: input.sessionKey, lastInvokedAt: now,
            lastActivity: input.activity ?? prior?.lastActivity,
            hasHadNormalWindows: (prior?.hasHadNormalWindows ?? false) || !input.windows.isEmpty,
            windows: windows)
    }
}
