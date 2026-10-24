import Foundation
import ResetRadarDomain

/// Snapshot, reader, and manual-refresh relay operations. Every call returns a typed result and
/// never throws for an HTTP result.
public protocol RelayGateway: Sendable {
    func putSnapshot(_ envelope: Data, endpoint: URL, writeToken: SecretValue) async -> RelayOutcome
    func getSnapshot(endpoint: URL, readToken: SecretValue, etag: String?) async -> RelayOutcome
    func activateReader(endpoint: URL, readToken: SecretValue) async -> RelayOutcome
    func postRefreshRequest(
        _ id: RequestID, target: ManualRefreshTarget, endpoint: URL,
        readToken: SecretValue
    ) async -> RelayOutcome
    func listRefreshRequests(
        endpoint: URL, writeToken: SecretValue
    ) async -> RelayResponse<[PendingRefreshRequest]>
    func deleteRefreshRequest(
        _ id: RequestID, endpoint: URL, writeToken: SecretValue
    ) async -> RelayOutcome
    /// Returns the relay-assigned registration expiry.
    func registerReader(
        _ id: ReaderID, digest: Data, endpoint: URL, adminToken: SecretValue
    ) async -> RelayResponse<Date>
    func listReaders(endpoint: URL, adminToken: SecretValue) async -> RelayResponse<[RelayReader]>
    func revokeReader(_ id: ReaderID, endpoint: URL, adminToken: SecretValue) async -> RelayOutcome
    func destroyRelay(endpoint: URL, adminToken: SecretValue) async -> RelayOutcome
}
