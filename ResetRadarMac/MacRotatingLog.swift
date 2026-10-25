import Darwin
import Foundation
import OSLog
import ResetRadarApplication
import ResetRadarDomain

enum MacLifecycleEvent: String, Sendable {
    case starting
    case ready
    case secondInstance
    case restartRequested
    case refreshRequested
    case stopping
    case stopped
    case wake
    case sessionActive
    case foreground
    case sleeping
    case networkRestored
}

enum MacStartupFailureCode: String, Sendable {
    case unsafeSourceLocation
    case incompatibleSourceConfiguration
    case sourceConfigurationUnavailable
    case inconsistentSourceCatalog
    case corruptPublisherState
    case incompatiblePublisherState
    case oversizedPublisherState
    case busyPublisherState
    case publisherIO
    case other
}

enum MacLogEvent: Sendable {
    case lifecycle(MacLifecycleEvent)
    case startupFailure(MacStartupFailureCode)
    case publication(PublicationStatusEvent)
    case diagnostic(DiagnosticEvent)
}

/// Owner-only, structured Mac troubleshooting history. Its event API accepts only typed,
/// redacted categories; account IDs, provider responses, paths, and usage values have no field.
actor MacRotatingLog {
    static let retainedDays = 8
    static let maximumSegmentBytes = 1_048_576
    static let maximumSegmentsPerDay = 4

    private struct Line: Encodable {
        let timestamp: String
        let session: String
        let event: String
        let reason: String?
        let transport: String?
        let httpClass: Int?
        let lastSequence: UInt64?
        let schemaVersion: Int?
        let supportedSchemaVersion: Int?
    }

    private struct Segment {
        let day: String
        let number: Int
        let name: String
    }

    private enum LogError: String, Error {
        case unsafeDirectory
        case unsafeFile
        case writeFailed
    }

    let directoryURL: URL
    private let sessionID: UUID
    private let maximumSegmentBytes: Int
    private let maximumSegmentsPerDay: Int
    private let logger: Logger
    private let dayFormatter: ISO8601DateFormatter
    private let timestampFormatter: ISO8601DateFormatter
    private let encoder = JSONEncoder()
    private var writeFailureReported = false
    private var maintenanceTask: Task<Void, Never>?

    init(
        directoryURL: URL, subsystem: String,
        sessionID: UUID = UUID(), maximumSegmentBytes: Int = MacRotatingLog.maximumSegmentBytes,
        maximumSegmentsPerDay: Int = MacRotatingLog.maximumSegmentsPerDay
    ) {
        self.directoryURL = directoryURL
        self.sessionID = sessionID
        self.maximumSegmentBytes = max(256, maximumSegmentBytes)
        self.maximumSegmentsPerDay = max(1, maximumSegmentsPerDay)
        logger = Logger(subsystem: subsystem, category: "agent-log")
        let dayFormatter = ISO8601DateFormatter()
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.formatOptions = [.withFullDate]
        self.dayFormatter = dayFormatter
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = timestampFormatter
        encoder.outputFormatting = [.sortedKeys]
    }

    @discardableResult
    func record(_ event: MacLogEvent, at date: Date = Date()) -> Bool {
        do {
            try write(event, at: date)
            if writeFailureReported {
                logger.info("local troubleshooting log writing recovered")
                writeFailureReported = false
            }
            return true
        } catch {
            if !writeFailureReported {
                let reason = (error as? LogError)?.rawValue ?? "io"
                logger.error(
                    "local troubleshooting log could not be written: \(reason, privacy: .public)")
                writeFailureReported = true
            }
            return false
        }
    }

    @discardableResult
    func prune(at date: Date = Date()) -> Bool {
        do {
            let directory = try openDirectory()
            defer { close(directory) }
            try withLock(in: directory) { try pruneFiles(in: directory, at: date) }
            return true
        } catch {
            return false
        }
    }

    func startMaintenance() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                _ = await self.prune()
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                let nextDay =
                    calendar.nextDate(
                        after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0),
                        matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86_400)
                let delay = max(1, nextDay.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stopMaintenance() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
    }

    private func write(_ event: MacLogEvent, at date: Date) throws {
        let line = makeLine(for: event, at: date)
        var bytes = try encoder.encode(line)
        bytes.append(0x0A)
        guard bytes.count <= maximumSegmentBytes else { throw LogError.writeFailed }
        let directory = try openDirectory()
        defer { close(directory) }
        try withLock(in: directory) {
            try pruneFiles(in: directory, at: date)
            let day = dayFormatter.string(from: date)
            let current =
                try segments().filter { $0.day == day }
                .map(\.number).max() ?? 0
            var number = current
            var file = try openSegment(day: day, number: number, in: directory)
            if try size(of: file) + bytes.count > maximumSegmentBytes {
                close(file)
                number += 1
                file = try openSegment(day: day, number: number, in: directory)
            }
            defer { close(file) }
            let originalSize = try size(of: file)
            guard Self.writeAll(bytes, to: file) else {
                _ = ftruncate(file, off_t(originalSize))
                throw LogError.writeFailed
            }
            if event.requiresSync, fsync(file) != 0 { throw LogError.writeFailed }
            try pruneFiles(in: directory, at: date)
        }
    }

    private func openDirectory() throws -> Int32 {
        try FileManager.default.createDirectory(
            at: directoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if mkdir(directoryURL.path, mode_t(0o700)) != 0, errno != EEXIST {
            throw LogError.unsafeDirectory
        }
        var metadata = Darwin.stat()
        guard lstat(directoryURL.path, &metadata) == 0,
            (metadata.st_mode & S_IFMT) == S_IFDIR,
            metadata.st_uid == getuid(), metadata.st_mode & 0o777 == 0o700
        else { throw LogError.unsafeDirectory }
        let descriptor = open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LogError.unsafeDirectory }
        return descriptor
    }

    private func withLock<T>(in directory: Int32, _ body: () throws -> T) throws -> T {
        let lock = openat(
            directory, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard lock >= 0 else { throw LogError.unsafeFile }
        defer { close(lock) }
        try validate(lock)
        guard flock(lock, LOCK_EX) == 0 else { throw LogError.writeFailed }
        defer { _ = flock(lock, LOCK_UN) }
        return try body()
    }

    private func openSegment(day: String, number: Int, in directory: Int32) throws -> Int32 {
        let name = "events-\(day)-\(number).jsonl"
        let descriptor = openat(
            directory, name, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600))
        guard descriptor >= 0 else { throw LogError.unsafeFile }
        do {
            try validate(descriptor)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func validate(_ descriptor: Int32) throws {
        var metadata = Darwin.stat()
        guard fstat(descriptor, &metadata) == 0,
            (metadata.st_mode & S_IFMT) == S_IFREG,
            metadata.st_uid == getuid(), metadata.st_mode & 0o777 == 0o600,
            metadata.st_nlink == 1
        else { throw LogError.unsafeFile }
    }

    private func size(of descriptor: Int32) throws -> Int {
        var metadata = Darwin.stat()
        guard fstat(descriptor, &metadata) == 0 else { throw LogError.unsafeFile }
        return Int(metadata.st_size)
    }

    private func segments() throws -> [Segment] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        return names.compactMap(Self.parseSegment)
    }

    private func pruneFiles(in directory: Int32, at date: Date) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let start = calendar.startOfDay(for: date)
        guard let oldest = calendar.date(byAdding: .day, value: 1 - Self.retainedDays, to: start)
        else { throw LogError.writeFailed }
        let cutoff = dayFormatter.string(from: oldest)
        let today = dayFormatter.string(from: date)
        let groups = Dictionary(grouping: try segments(), by: \.day)
        for (day, values) in groups {
            let ordered = values.sorted { $0.number < $1.number }
            let excess = max(0, ordered.count - maximumSegmentsPerDay)
            let removeWholeDay = day < cutoff || day > today
            let firstRetainedNumber = ordered[excess].number
            for segment in ordered {
                guard removeWholeDay || segment.number < firstRetainedNumber else { continue }
                guard unlinkat(directory, segment.name, 0) == 0 else {
                    throw LogError.writeFailed
                }
            }
        }
    }

    private static func parseSegment(_ name: String) -> Segment? {
        guard name.hasPrefix("events-"), name.hasSuffix(".jsonl") else { return nil }
        let stem = String(name.dropFirst(7).dropLast(6))
        guard stem.count >= 12 else { return nil }
        let day = String(stem.prefix(10))
        let suffix = String(stem.dropFirst(10))
        guard day.count == 10, day[day.index(day.startIndex, offsetBy: 4)] == "-",
            day[day.index(day.startIndex, offsetBy: 7)] == "-", suffix.first == "-",
            day.enumerated().allSatisfy({ index, character in
                index == 4 || index == 7 ? character == "-" : character.isNumber
            }),
            let number = Int(suffix.dropFirst()), number >= 0
        else { return nil }
        return Segment(day: day, number: number, name: name)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }

    private func makeLine(for event: MacLogEvent, at date: Date) -> Line {
        let fields = event.fields
        return Line(
            timestamp: timestampFormatter.string(from: date), session: sessionID.uuidString,
            event: fields.event, reason: fields.reason, transport: fields.transport,
            httpClass: fields.httpClass, lastSequence: fields.lastSequence,
            schemaVersion: fields.schemaVersion,
            supportedSchemaVersion: fields.supportedSchemaVersion)
    }
}

private struct MacLogFields {
    let event: String
    var reason: String?
    var transport: String?
    var httpClass: Int?
    var lastSequence: UInt64?
    var schemaVersion: Int?
    var supportedSchemaVersion: Int?
}

extension MacLogEvent {
    fileprivate var fields: MacLogFields {
        switch self {
        case .lifecycle(let event):
            MacLogFields(event: "collector.\(event.rawValue)")
        case .startupFailure(let reason):
            MacLogFields(event: "collector.startupFailed", reason: reason.rawValue)
        case .publication(let event):
            switch event {
            case .blocked(let outcome):
                MacLogFields(event: "publication.blocked", reason: outcome.logReason)
            case .recovered:
                MacLogFields(event: "publication.recovered")
            }
        case .diagnostic(let event):
            MacLogFields(
                event: "diagnostic.\(event.category.rawValue)",
                reason: event.providerFailureClass?.rawValue,
                transport: event.transportStatus?.rawValue,
                httpClass: event.httpStatusClass, lastSequence: event.lastSequence,
                schemaVersion: event.schemaVersion,
                supportedSchemaVersion: event.supportedSchemaVersion)
        }
    }

    fileprivate var requiresSync: Bool {
        switch self {
        case .startupFailure, .publication(.blocked): true
        case .lifecycle, .publication(.recovered), .diagnostic: false
        }
    }
}

extension PublishOutcome {
    fileprivate var logReason: String {
        switch self {
        case .stopped(.snapshotConflict): "snapshotConflict"
        case .stopped(.authorizationRequired): "authorizationRequired"
        case .stopped(.payloadRejected): "payloadRejected"
        case .stopped(.incompatible): "incompatible"
        case .envelopeTooLarge: "envelopeTooLarge"
        case .secretsUnavailable: "secretsUnavailable"
        case .paused: "paused"
        case .backoff: "backoff"
        case .notDue: "notDue"
        case .published: "published"
        }
    }
}
