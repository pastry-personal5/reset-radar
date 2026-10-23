import Foundation
import ResetRadarApplication

/// A bounded claim, kept in a file under its own lock, that serializes reset-notification
/// reconciliation across the iOS app and widget extension. A crashed holder's claim expires, so
/// the work is retried; no relay request runs while the gate is held.
public final class FileNotificationReconcileGate: NotificationReconcileGate {
    private struct StoredClaim: Codable, Sendable {
        var id: UUID
        var expiresAt: Date
    }

    private struct Stored: Codable, Sendable {
        var claim: StoredClaim?
    }

    private let file: TransactionalFile<Stored>
    private let clock: any AppClock
    private let lease: Duration

    public init(
        locations: StorageLocations, clock: any AppClock, lease: Duration = .seconds(30),
        writer: AtomicFileWriter = AtomicFileWriter()
    ) {
        file = TransactionalFile(
            locations: locations, name: "reconcile-gate", writer: writer,
            makeDefault: { Stored(claim: nil) })
        self.clock = clock
        self.lease = lease
    }

    /// A storage failure reads as "another holder": the caller leaves `needsAppReconcile` set
    /// and tries again, which is the safe outcome.
    public func claim() async -> GateClaim? {
        let seconds = Double(lease.components.seconds) + Double(lease.components.attoseconds) / 1e18
        do {
            return try await file.transact { stored -> GateClaim? in
                let now = clock.now
                if let held = stored.claim, now < held.expiresAt { return nil }
                let candidate = GateClaim(id: UUID(), expiresAt: now.addingTimeInterval(seconds))
                stored.claim = StoredClaim(id: candidate.id, expiresAt: candidate.expiresAt)
                return candidate
            }
        } catch {
            return nil
        }
    }

    /// Frees the gate only while `claim` still owns it; a late release of a reclaimed claim does
    /// nothing. A storage failure leaves the claim to expire.
    public func release(_ claim: GateClaim) async {
        do {
            try await file.transact { stored in
                if stored.claim?.id == claim.id { stored.claim = nil }
            }
        } catch {
            return
        }
    }
}
