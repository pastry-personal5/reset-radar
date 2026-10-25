import Foundation
import OSLog
import ResetRadarApplication
import ResetRadarDomain

/// Forwards each event to unified logging and keeps a bounded ring file for the diagnostics
/// export. An event holds only enums, numbers, and dates, so nothing sensitive can reach either.
public final class LogDiagnosticsSink: DiagnosticsSink {
    private struct Ring: Codable, Sendable {
        var events: [DiagnosticEvent]
    }

    private let file: TransactionalFile<Ring>
    private let capacity: Int
    private let logger: Logger
    private let onRecord: (@Sendable (DiagnosticEvent) async -> Void)?

    public init(
        locations: StorageLocations, capacity: Int = 200,
        writer: AtomicFileWriter = AtomicFileWriter(),
        subsystem: String = "com.unidentifiedstealthstartup.ResetRadar",
        onRecord: (@Sendable (DiagnosticEvent) async -> Void)? = nil
    ) {
        file = TransactionalFile(
            locations: locations, name: "diagnostics", writer: writer,
            makeDefault: { Ring(events: []) })
        self.capacity = max(1, capacity)
        logger = Logger(subsystem: subsystem, category: "diagnostics")
        self.onRecord = onRecord
    }

    public func record(_ event: DiagnosticEvent) async {
        let category = event.category.rawValue
        let transport = event.transportStatus?.rawValue ?? "none"
        let httpClass = event.httpStatusClass ?? 0
        let failureClass = event.providerFailureClass?.rawValue ?? "none"
        logger.info("diagnostic category=\(category, privacy: .public)")
        logger.info("diagnostic failure=\(failureClass, privacy: .public)")
        logger.info(
            "diagnostic transport=\(transport, privacy: .public) http=\(httpClass)"
        )
        await onRecord?(event)
        let limit = capacity
        do {
            try await file.transact { ring in
                ring.events.append(event)
                if ring.events.count > limit {
                    ring.events.removeFirst(ring.events.count - limit)
                }
            }
        } catch {
            logger.error("diagnostic history could not be written")
        }
    }

    /// Oldest first. An unreadable ring reads as empty.
    public func history() async -> [DiagnosticEvent] {
        do {
            return try await file.load().events
        } catch {
            return []
        }
    }
}
