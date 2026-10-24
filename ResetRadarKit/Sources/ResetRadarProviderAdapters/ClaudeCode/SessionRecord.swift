import Foundation
import ResetRadarDomain

public enum SessionRecordError: Error, Equatable, Sendable {
    case unsafeLocation
    case unavailable
    case incompatibleRecord
    case recordTooLarge
    case notFound
}

/// One retained window of a session, with the provenance of its observation.
public struct SessionWindow: Equatable, Sendable {
    public let kind: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let observedAt: Date
    public let sourceVersion: String
    public let reportState: ReportState

    public init(
        kind: String, usedPercent: Double, resetsAt: Date?, observedAt: Date,
        sourceVersion: String, reportState: ReportState
    ) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.sourceVersion = sourceVersion
        self.reportState = reportState
    }

    public var durationMinutes: Int? { StatusLineGrammar.durationMinutes(forKind: kind) }
}

/// The versioned per-session record. It holds only the digest key, invocation and observation
/// times, the prior activity counter, and normalized non-spend windows.
public struct SessionRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let key: SessionKey
    public let lastInvokedAt: Date
    public let lastActivity: Double?
    public let hasHadNormalWindows: Bool
    public let windows: [SessionWindow]

    public init(
        key: SessionKey, lastInvokedAt: Date, lastActivity: Double?, hasHadNormalWindows: Bool,
        windows: [SessionWindow]
    ) {
        self.key = key
        self.lastInvokedAt = lastInvokedAt
        self.lastActivity = lastActivity
        self.hasHadNormalWindows = hasHadNormalWindows
        self.windows = windows.sorted { $0.kind < $1.kind }
    }

    public var newestObservation: Date? { windows.map(\.observedAt).max() }

    /// When the eight-day pruning rule starts counting for this record.
    public var pruneAnchor: Date { newestObservation ?? lastInvokedAt }
}

// MARK: - Canonical encoding

private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
}

private func date(milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
}

private struct WireWindow: Codable {
    let kind: String
    let usedPercent: Double
    let resetsAt: Int64?
    let observedAtMs: Int64
    let sourceVersion: String
    let retained: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, usedPercent, resetsAt, observedAtMs, sourceVersion, retained
    }

    init(_ window: SessionWindow) {
        kind = window.kind
        usedPercent = window.usedPercent
        resetsAt = window.resetsAt.map { Int64($0.timeIntervalSince1970) }
        observedAtMs = milliseconds(window.observedAt)
        sourceVersion = window.sourceVersion
        retained = window.reportState == .retained
    }

    init(from decoder: any Decoder) throws {
        try Self.requireKnownKeys(
            decoder,
            required: [
                "kind", "usedPercent", "observedAtMs",
                "sourceVersion", "retained",
            ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        resetsAt = try container.decodeIfPresent(Int64.self, forKey: .resetsAt)
        observedAtMs = try container.decode(Int64.self, forKey: .observedAtMs)
        sourceVersion = try container.decode(String.self, forKey: .sourceVersion)
        retained = try container.decode(Bool.self, forKey: .retained)
    }

    var window: SessionWindow? {
        guard StatusLineGrammar.isWindowKind(kind), StatusLineGrammar.isVersion(sourceVersion),
            usedPercent.isFinite, (0...100).contains(usedPercent),
            observedAtMs >= 0, resetsAt.map({ (0...253_402_300_799).contains($0) }) ?? true
        else { return nil }
        return SessionWindow(
            kind: kind, usedPercent: usedPercent,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: Double($0)) },
            observedAt: date(milliseconds: observedAtMs), sourceVersion: sourceVersion,
            reportState: retained ? .retained : .reported)
    }

    fileprivate static func requireKnownKeys(
        _ decoder: any Decoder, required: Set<String>
    ) throws {
        let all = Set(CodingKeys.allCases.map(\.rawValue))
        let present = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        guard present.isSubset(of: all), required.isSubset(of: present) else {
            throw SessionRecordError.incompatibleRecord
        }
    }
}

private struct WireRecord: Codable {
    let schemaVersion: Int
    let key: String
    let lastInvokedAtMs: Int64
    let lastActivity: Double?
    let hasHadNormalWindows: Bool
    let windows: [WireWindow]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, key, lastInvokedAtMs, lastActivity, hasHadNormalWindows, windows
    }

    init(_ record: SessionRecord) {
        schemaVersion = SessionRecord.currentSchemaVersion
        key = record.key.hex
        lastInvokedAtMs = milliseconds(record.lastInvokedAt)
        lastActivity = record.lastActivity
        hasHadNormalWindows = record.hasHadNormalWindows
        windows = record.windows.map(WireWindow.init)
    }

    init(from decoder: any Decoder) throws {
        let all = Set(CodingKeys.allCases.map(\.rawValue))
        let present = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        guard present.isSubset(of: all),
            all.subtracting(["lastActivity"]).isSubset(of: present)
        else { throw SessionRecordError.incompatibleRecord }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        key = try container.decode(String.self, forKey: .key)
        lastInvokedAtMs = try container.decode(Int64.self, forKey: .lastInvokedAtMs)
        lastActivity = try container.decodeIfPresent(Double.self, forKey: .lastActivity)
        hasHadNormalWindows = try container.decode(Bool.self, forKey: .hasHadNormalWindows)
        windows = try container.decode([WireWindow].self, forKey: .windows)
    }
}

enum SessionRecordCodec {
    static func encode(_ record: SessionRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(WireRecord(record))
        } catch {
            throw SessionRecordError.incompatibleRecord
        }
        guard data.count <= StatusLineLimits.maximumRecordBytes else {
            throw SessionRecordError.recordTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> SessionRecord {
        guard data.count <= StatusLineLimits.maximumRecordBytes else {
            throw SessionRecordError.recordTooLarge
        }
        do {
            try JSONStructuralPreflight.validate(data)
        } catch {
            throw SessionRecordError.incompatibleRecord
        }
        let wire: WireRecord
        do {
            wire = try JSONDecoder().decode(WireRecord.self, from: data)
        } catch {
            throw SessionRecordError.incompatibleRecord
        }
        guard wire.schemaVersion == SessionRecord.currentSchemaVersion,
            let key = SessionKey(hex: wire.key), wire.lastInvokedAtMs >= 0,
            wire.windows.count <= StatusLineLimits.maximumRateLimitMembers,
            wire.lastActivity.map({ $0.isFinite && $0 >= 0 }) ?? true
        else { throw SessionRecordError.incompatibleRecord }
        let windows = wire.windows.compactMap(\.window)
        guard windows.count == wire.windows.count,
            Set(windows.map(\.kind)).count == windows.count
        else { throw SessionRecordError.incompatibleRecord }
        return SessionRecord(
            key: key, lastInvokedAt: date(milliseconds: wire.lastInvokedAtMs),
            lastActivity: wire.lastActivity, hasHadNormalWindows: wire.hasHadNormalWindows,
            windows: windows)
    }
}
