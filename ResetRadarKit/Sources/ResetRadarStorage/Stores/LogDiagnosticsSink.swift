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

    private static let logger = Logger(
        subsystem: "com.unidentifiedstealthstartup.ResetRadar", category: "diagnostics")

    private let file: TransactionalFile<Ring>
    private let capacity: Int

    public init(
        locations: StorageLocations, capacity: Int = 200,
        writer: AtomicFileWriter = AtomicFileWriter()
    ) {
        file = TransactionalFile(
            locations: locations, name: "diagnostics", writer: writer,
            makeDefault: { Ring(events: []) })
        self.capacity = max(1, capacity)
    }

    public func record(_ event: DiagnosticEvent) async {
        let category = event.category.rawValue
        let product = event.product?.rawValue ?? "none"
        let transport = event.transportStatus?.rawValue ?? "none"
        let httpClass = event.httpStatusClass ?? 0
        let failureClass = event.providerFailureClass?.rawValue ?? "none"
        Self.logger.info("diagnostic category=\(category, privacy: .public)")
        Self.logger.info("diagnostic failure=\(failureClass, privacy: .public)")
        Self.logger.info("diagnostic product=\(product, privacy: .public)")
        Self.logger.info(
            "diagnostic transport=\(transport, privacy: .public) http=\(httpClass)"
        )
        let limit = capacity
        do {
            try await file.transact { ring in
                ring.events.append(event)
                if ring.events.count > limit {
                    ring.events.removeFirst(ring.events.count - limit)
                }
            }
        } catch {
            Self.logger.error("diagnostic history could not be written")
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
