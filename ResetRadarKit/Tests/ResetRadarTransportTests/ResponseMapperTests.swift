import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarTransport

private typealias TransportRelayOperation = ResetRadarTransport.RelayOperation

private struct OperationFixture: Decodable {
    let responseBody: String
    let requestBody: String
    let status: Int
    let etag: String?
}

private struct ErrorFixture: Decodable {
    let body: String
    let status: Int
}

private struct PlatformErrorFixture: Decodable {
    let body: String
    let status: Int
}

private struct ScenarioFixture: Decodable {
    let operation: String
    let status: Int
    let requestBody: String
    let responseBody: String
}

private struct ErrorCase {
    let name: String
    let operation: TransportRelayOperation
    let expected: RelayOutcome

    init(_ name: String, _ operation: TransportRelayOperation, _ expected: RelayOutcome) {
        self.name = name
        self.operation = operation
        self.expected = expected
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Protocol/\(name).json")
    return try Data(contentsOf: url)
}

private func mapOperation(
    _ name: String, _ operation: TransportRelayOperation
) throws -> RelayMappedResult {
    let fixture = try JSONDecoder().decode(
        OperationFixture.self, from: fixtureData("operation-\(name)"))
    return ResponseMapper.map(
        RelayResponseContext(
            operation: operation, status: fixture.status,
            body: Data(fixture.responseBody.utf8), etag: fixture.etag,
            conditionalETag: nil,
            submittedEnvelope: fixture.requestBody.isEmpty ? nil : Data(fixture.requestBody.utf8)))
}

@Test func everySharedOperationFixtureMapsToItsPortResult() throws {
    #expect(try mapOperation("snapshot-put", .putSnapshot).outcome == .accepted(sequence: 7))
    let snapshot = try mapOperation("snapshot-get", .getSnapshot).outcome
    if case .snapshot(let bytes, let etag, let sequence) = snapshot {
        #expect(bytes == Data((try fixtureString("envelope", "outerJSON")).utf8))
        #expect(etag == (try fixtureString("envelope", "etag")))
        #expect(sequence == 7)
    } else {
        Issue.record("Expected snapshot response")
    }
    #expect(
        try mapOperation("reader-activate", .activateReader).outcome == .accepted(sequence: nil))
    #expect(
        try mapOperation("refresh-post", .postRefreshRequest).outcome
            == .refreshAccepted(expiresAt: Date(timeIntervalSince1970: 1_700_000_300)))
    let refreshList = try mapOperation("refresh-list", .listRefreshRequests)
    if case .refreshRequests(let requests) = refreshList {
        #expect(requests.count == 1)
    } else {
        Issue.record("Expected refresh list")
    }
    #expect(try mapOperation("refresh-delete", .deleteRefreshRequest).outcome == .deleted)
    if case .registration(let expiry) = try mapOperation("reader-register", .registerReader) {
        #expect(expiry == Date(timeIntervalSince1970: 1_700_000_300))
    } else {
        Issue.record("Expected registration expiry")
    }
    if case .readers(let readers) = try mapOperation("reader-list", .listReaders) {
        #expect(readers.count == 1)
        #expect(readers[0].activated)
    } else {
        Issue.record("Expected reader list")
    }
    #expect(try mapOperation("reader-revoke", .revokeReader).outcome == .deleted)
    #expect(try mapOperation("relay-destroy", .destroyRelay).outcome == .deleted)
}

private func fixtureString(_ name: String, _ field: String) throws -> String {
    let fields = try JSONDecoder().decode([String: String].self, from: fixtureData(name))
    return fields[field]!
}

@Test func sharedErrorFixturesMapByStatusCodeAndOperation() throws {
    let rows: [ErrorCase] = [
        .init("bad-request", .putSnapshot, .badRequest),
        .init("unauthorized", .getSnapshot, .unauthorized),
        .init("awaiting-first-publish", .getSnapshot, .awaitingFirstPublish),
        .init("unknown-route", .getSnapshot, .protocolFailure),
        .init("publisher-mismatch", .putSnapshot, .publisherConflict),
        .init("sequence-conflict", .putSnapshot, .publisherConflict),
        .init("reader-cap-reached", .registerReader, .readerCapReached),
        .init("request-already-completed", .postRefreshRequest, .requestAlreadyCompleted),
        .init("payload-too-large", .putSnapshot, .payloadTooLarge),
        .init("unsupported-version", .putSnapshot, .unsupportedVersion),
        .init("request-rate-limited", .postRefreshRequest, .requestRateLimited),
        .init("quota-limited", .getSnapshot, .quotaLimited),
    ]
    for row in rows {
        let fixture = try JSONDecoder().decode(
            ErrorFixture.self,
            from: fixtureData("error\(row.operation.isRefresh ? "-refresh" : "")-\(row.name)"))
        let actual = ResponseMapper.map(
            RelayResponseContext(
                operation: row.operation, status: fixture.status, body: Data(fixture.body.utf8),
                etag: nil, conditionalETag: nil, submittedEnvelope: nil))
        #expect(actual.outcome == row.expected)
    }
}

@Test func everyRelayStatusContractRowHasItsExpectedMappedOutcome() throws {
    let mapped: [String: RelayOutcome] = [
        "snapshot read": try mapOperation("snapshot-get", .getSnapshot).outcome,
        "snapshot write": try mapOperation("snapshot-put", .putSnapshot).outcome,
        "idempotent activation": try mapOperation("reader-activate", .activateReader).outcome,
        "refresh request accepted": try mapOperation("refresh-post", .postRefreshRequest).outcome,
        "delete": try mapOperation("relay-destroy", .destroyRelay).outcome,
        "conditional read unchanged": mappedSnapshot(status: 304, body: Data(), etag: nil),
        "unexpected redirect": mappedSnapshot(status: 302, body: Data(), etag: nil),
        "malformed request": try mappedError("bad-request", operation: .putSnapshot),
        "missing, unknown, or revoked token": try mappedError(
            "unauthorized", operation: .getSnapshot),
        "authenticated snapshot read before first publish": try mappedError(
            "awaiting-first-publish", operation: .getSnapshot),
        "unknown route": try mappedError("unknown-route", operation: .getSnapshot),
        "snapshot write conflict": try mappedError("publisher-mismatch", operation: .putSnapshot),
        "reader registration at cap": try mappedError(
            "reader-cap-reached", operation: .registerReader),
        "manual request already completed": try mappedError(
            "request-already-completed", operation: .postRefreshRequest),
        "payload over 64 KiB": try mappedError("payload-too-large", operation: .putSnapshot),
        "unsupported mandatory version": try mappedError(
            "unsupported-version", operation: .putSnapshot),
        "manual request rate limit": try mappedError(
            "request-rate-limited", operation: .postRefreshRequest),
        "free-tier daily limit": try mappedError("quota-limited", operation: .getSnapshot),
        "Worker or Durable Object failure": mappedSnapshot(status: 503, body: Data(), etag: nil),
        "network or TLS failure": .offline,
    ]
    #expect(mapped.count == RelayStatusContract.rows.count)
    for row in RelayStatusContract.rows {
        #expect(RelayOutcomeKind(of: mapped[row.scenario]!) == RelayOutcomeKind(of: row.outcome))
    }
}

private func mappedError(
    _ name: String, operation: TransportRelayOperation
) throws -> RelayOutcome {
    let fixture = try JSONDecoder().decode(
        ErrorFixture.self,
        from: fixtureData("error\(operation.isRefresh ? "-refresh" : "")-\(name)"))
    return ResponseMapper.map(
        RelayResponseContext(
            operation: operation, status: fixture.status, body: Data(fixture.body.utf8),
            etag: nil, conditionalETag: nil, submittedEnvelope: nil)
    ).outcome
}

private func mappedSnapshot(status: Int, body: Data, etag: String?) -> RelayOutcome {
    ResponseMapper.map(
        RelayResponseContext(
            operation: .getSnapshot, status: status, body: body, etag: etag,
            conditionalETag: nil, submittedEnvelope: nil)
    ).outcome
}

private func platformQuotaBody(
    cloudflareError: Bool = true,
    category: String = "rate_limit",
    code: Int = 1027,
    status: Int = 429
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "cloudflare_error": cloudflareError,
        "error_category": category,
        "error_code": code,
        "status": status,
    ])
}

@Test func malformedResponseAndUnexpectedStatusCannotBecomeSuccess() throws {
    let fixture = try JSONDecoder().decode(
        OperationFixture.self, from: fixtureData("operation-snapshot-get"))
    let badETag = ResponseMapper.map(
        RelayResponseContext(
            operation: .getSnapshot, status: 200, body: Data(fixture.responseBody.utf8),
            etag: "\"wrong\"", conditionalETag: nil, submittedEnvelope: nil))
    #expect(badETag.outcome == .protocolFailure)
    let wrongRoute = ResponseMapper.map(
        RelayResponseContext(
            operation: .listReaders, status: 404,
            body: Data("{\"code\":\"awaitingFirstPublish\",\"protocolVersion\":1}".utf8),
            etag: nil, conditionalETag: nil, submittedEnvelope: nil))
    #expect(wrongRoute.outcome == .protocolFailure)
    let unexpectedQuota = ResponseMapper.map(
        RelayResponseContext(
            operation: .getSnapshot, status: 429, body: Data("quota".utf8), etag: nil,
            conditionalETag: nil, submittedEnvelope: nil))
    #expect(unexpectedQuota.outcome == .protocolFailure)
}

@Test func structuredCloudflareFreeLimitMapsNarrowlyToQuotaLimited() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Platform/cloudflare-free-limit.json")
    let fixture = try JSONDecoder().decode(PlatformErrorFixture.self, from: Data(contentsOf: url))
    #expect(
        mappedSnapshot(status: fixture.status, body: Data(fixture.body.utf8), etag: nil)
            == .quotaLimited)

    for body in try [
        platformQuotaBody(cloudflareError: false),
        platformQuotaBody(category: "worker"),
        platformQuotaBody(code: 1102),
        platformQuotaBody(status: 500),
    ] {
        #expect(mappedSnapshot(status: 429, body: body, etag: nil) == .protocolFailure)
    }
    #expect(
        mappedSnapshot(status: 500, body: try platformQuotaBody(status: 500), etag: nil)
            == .quotaLimited)
}

@Test func conditionalReadAndTransportFailuresHaveDistinctOutcomes() throws {
    let validator = try fixtureString("envelope", "etag")
    func mapped(status: Int, etag: String?, conditional: String?) -> RelayOutcome {
        ResponseMapper.map(
            RelayResponseContext(
                operation: .getSnapshot, status: status, body: Data(), etag: etag,
                conditionalETag: conditional, submittedEnvelope: nil)
        ).outcome
    }
    #expect(mapped(status: 304, etag: validator, conditional: validator) == .notModified)
    #expect(mapped(status: 304, etag: validator, conditional: nil) == .notModified)
    #expect(mapped(status: 304, etag: "\"wrong\"", conditional: validator) == .protocolFailure)
    #expect(mapped(status: 302, etag: nil, conditional: nil) == .protocolFailure)
    #expect(mapped(status: 503, etag: nil, conditional: nil) == .offline)
}

@Test func sharedCollisionAndReplayScenariosUseApprovedGenericCodes() throws {
    let badRequestScenarios = [
        "reader-changed-digest", "reader-reused-digest", "reader-privileged-digest",
        "refresh-expired-id", "refresh-cross-reader-id", "sequence-overflow",
    ]
    for name in badRequestScenarios {
        let scenario = try JSONDecoder().decode(
            ScenarioFixture.self, from: fixtureData("scenario-\(name)"))
        let operation: TransportRelayOperation =
            scenario.operation == "registerReader"
            ? .registerReader
            : scenario.operation == "postRefreshRequest" ? .postRefreshRequest : .putSnapshot
        let mapped = ResponseMapper.map(
            RelayResponseContext(
                operation: operation, status: scenario.status,
                body: Data(scenario.responseBody.utf8), etag: nil,
                conditionalETag: nil, submittedEnvelope: Data(scenario.requestBody.utf8)))
        #expect(mapped.outcome == .badRequest)
        if name == "sequence-overflow" {
            #expect(EnvelopeOuter.parse(Data(scenario.requestBody.utf8)) == nil)
        }
    }
    let completed = try JSONDecoder().decode(
        ScenarioFixture.self, from: fixtureData("scenario-refresh-completed-id"))
    #expect(
        ResponseMapper.map(
            RelayResponseContext(
                operation: .postRefreshRequest, status: completed.status,
                body: Data(completed.responseBody.utf8), etag: nil,
                conditionalETag: nil, submittedEnvelope: Data(completed.requestBody.utf8))
        ).outcome
            == .requestAlreadyCompleted)
    let retry = try JSONDecoder().decode(
        ScenarioFixture.self, from: fixtureData("scenario-reader-retry"))
    let mappedRetry = ResponseMapper.map(
        RelayResponseContext(
            operation: .registerReader, status: retry.status,
            body: Data(retry.responseBody.utf8), etag: nil,
            conditionalETag: nil, submittedEnvelope: Data(retry.requestBody.utf8)))
    if case .registration(let expiry) = mappedRetry {
        #expect(expiry == Date(timeIntervalSince1970: 1_700_000_300))
    } else {
        Issue.record("Expected original registration expiry")
    }
}
