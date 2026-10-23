import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct TaxonomyTests {
    static let sample = Data([1, 2, 3])
    static let later = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// One row per `RelayOutcome` case: the transport status it sets, or `nil` for a no-op.
    struct Row {
        let outcome: RelayOutcome
        let validated: Bool
        let status: TransportStatus?
    }

    static let rows: [Row] = [
        Row(
            outcome: .snapshot(sample, etag: "\"e\"", sequence: 1), validated: true,
            status: .current),
        Row(
            outcome: .snapshot(sample, etag: "\"e\"", sequence: 1), validated: false,
            status: .invalidSnapshot),
        Row(outcome: .notModified, validated: true, status: .current),
        Row(outcome: .awaitingFirstPublish, validated: true, status: .awaitingFirstPublish),
        Row(outcome: .badRequest, validated: true, status: .invalidSnapshot),
        Row(outcome: .accepted(sequence: 2), validated: true, status: nil),
        Row(outcome: .refreshAccepted(expiresAt: later), validated: true, status: nil),
        Row(outcome: .deleted, validated: true, status: nil),
        Row(outcome: .unauthorized, validated: true, status: .authorizationRequired),
        Row(outcome: .publisherConflict, validated: true, status: nil),
        Row(outcome: .readerCapReached, validated: true, status: nil),
        Row(outcome: .requestAlreadyCompleted, validated: true, status: nil),
        Row(outcome: .payloadTooLarge, validated: true, status: .incompatible),
        Row(outcome: .unsupportedVersion, validated: true, status: .incompatible),
        Row(outcome: .requestRateLimited, validated: true, status: nil),
        Row(outcome: .quotaLimited, validated: true, status: .quotaLimited),
        Row(outcome: .protocolFailure, validated: true, status: .invalidSnapshot),
        Row(outcome: .offline, validated: true, status: .offline),
    ]

    @Test(arguments: rows.indices) func mappingTable(index: Int) {
        let row = Self.rows[index]
        let context = MappingContext(snapshotValidated: row.validated)
        #expect(TransportStatusMapping.status(for: row.outcome, context: context) == row.status)
    }

    /// Fails to compile when a `RelayOutcome` case is added without a row above.
    @Test func everyCaseHasARow() {
        for row in Self.rows {
            switch row.outcome {
            case .snapshot, .notModified, .awaitingFirstPublish, .badRequest, .accepted,
                .refreshAccepted, .deleted, .unauthorized, .publisherConflict, .readerCapReached,
                .requestAlreadyCompleted, .payloadTooLarge, .unsupportedVersion,
                .requestRateLimited, .quotaLimited, .protocolFailure, .offline:
                break
            }
        }
        #expect(
            Set(Self.rows.map { RelayOutcomeKind(of: $0.outcome) })
                == Set(RelayOutcomeKind.allCases))
    }

    @Test func statusContractNamesEveryRelayStatus() {
        let statuses = Set(RelayStatusContract.rows.map(\.status))
        #expect(statuses.isSuperset(of: [200, 202, 204, 304, 400, 401, 404, 409, 413, 422, 429]))
        #expect(statuses.contains { (300...399).contains($0) && $0 != 304 })
        let kinds = Set(RelayStatusContract.rows.map { RelayOutcomeKind(of: $0.outcome) })
        #expect(kinds == Set(RelayOutcomeKind.allCases))
        let conflicts = RelayStatusContract.rows.filter { $0.status == 409 }
        #expect(conflicts.count == 3)
        #expect(RelayStatusContract.rows.filter { $0.status == 404 }.count == 2)
        #expect(RelayStatusContract.rows.filter { $0.status == 429 }.count == 2)
    }

    @Test func secretStoreErrorIsComparableAndRedacted() {
        #expect(SecretStoreError.unexpected(statusClass: 2) != .interactionRequired)
        #expect(!String(describing: SecretStoreError.notFound).contains("0x"))
    }
}
