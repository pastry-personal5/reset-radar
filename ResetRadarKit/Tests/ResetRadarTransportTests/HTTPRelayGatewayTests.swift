import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTransport
import Testing

private final class RelayHarnessState: @unchecked Sendable {
    struct ResponseSpec {
        let status: Int
        let body: Data
        let headers: [String: String]
        let redirectURL: URL?
        let failure: URLError?
    }

    private let lock = NSLock()
    private var status = 200
    private var body = Data()
    private var headers: [String: String] = [:]
    private var redirectURL: URL?
    private var failure: URLError?
    private var recorded: [URLRequest] = []
    private var bodies: [Data] = []

    func configure(
        status: Int, body: Data, headers: [String: String], redirectURL: URL? = nil,
        failure: URLError? = nil
    ) {
        lock.withLock {
            self.status = status
            self.body = body
            self.headers = headers
            self.redirectURL = redirectURL
            self.failure = failure
            recorded = []
            bodies = []
        }
    }

    func take(_ request: URLRequest) -> ResponseSpec {
        lock.withLock {
            recorded.append(request)
            bodies.append(Self.body(from: request))
            return ResponseSpec(
                status: status, body: body, headers: headers, redirectURL: redirectURL,
                failure: failure)
        }
    }

    var requests: [URLRequest] { lock.withLock { recorded } }
    var requestBodies: [Data] { lock.withLock { bodies } }

    private static func body(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { return result }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}

private final class RelayURLProtocol: URLProtocol {
    static let harness = RelayHarnessState()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let spec = Self.harness.take(request)
        if let failure = spec.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: spec.status, httpVersion: "HTTP/1.1",
            headerFields: spec.headers)!
        if let redirectURL = spec.redirectURL {
            client?.urlProtocol(
                self, wasRedirectedTo: URLRequest(url: redirectURL), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: spec.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct GatewayFixture: Decodable {
    let method: String
    let path: String
    let requestBody: String
    let responseBody: String
    let status: Int
    let etag: String?
}

private func gatewayFixture(_ name: String) throws -> GatewayFixture {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Protocol/operation-\(name).json")
    return try JSONDecoder().decode(GatewayFixture.self, from: Data(contentsOf: url))
}

private let relayOrigin = URL(string: "https://reset.example.workers.dev")!
private let writeToken = SecretValue(Data(repeating: 0x11, count: 32))
private let readToken = SecretValue(Data(repeating: 0x22, count: 32))
private let adminToken = SecretValue(Data(repeating: 0x33, count: 32))

@Suite(.serialized) struct GatewayHarnessTests {
    @Test func gatewaySnapshotReadUsesCanonicalPathReadBearerAndETag() async throws {
        let fixture = try gatewayFixture("snapshot-get")
        RelayURLProtocol.harness.configure(
            status: fixture.status, body: Data(fixture.responseBody.utf8),
            headers: ["Content-Type": "application/json", "ETag": fixture.etag!])
        let gateway = HTTPRelayGateway(protocolClasses: [RelayURLProtocol.self])
        let outcome = await gateway.getSnapshot(
            endpoint: relayOrigin, readToken: readToken, etag: nil)
        if case .snapshot(_, let etag, let sequence) = outcome {
            #expect(etag == fixture.etag)
            #expect(sequence == 7)
        } else {
            Issue.record("Expected snapshot")
        }
        let requests = RelayURLProtocol.harness.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == fixture.method)
        #expect(requests[0].url?.path == fixture.path)
        let expectedBearer = Data(repeating: 0x22, count: 32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(
            requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedBearer)")
    }

    @Test func gatewayPreflightRejectsOriginAndOversizedUploadWithoutSending() async {
        RelayURLProtocol.harness.configure(status: 200, body: Data(), headers: [:])
        let gateway = HTTPRelayGateway(protocolClasses: [RelayURLProtocol.self])
        let wrongOrigin = URL(string: "https://reset.example.workers.dev/")!
        let originOutcome = await gateway.getSnapshot(
            endpoint: wrongOrigin, readToken: readToken, etag: nil)
        #expect(originOutcome == .protocolFailure)
        let large = Data(repeating: 0x61, count: 65_537)
        let uploadOutcome = await gateway.putSnapshot(
            large, endpoint: relayOrigin, writeToken: writeToken)
        #expect(uploadOutcome == .payloadTooLarge)
        #expect(RelayURLProtocol.harness.requests.isEmpty)
    }

    @Test func gatewayNeverForwardsAnyRoleBearerOnRedirect() async throws {
        let gateway = HTTPRelayGateway(protocolClasses: [RelayURLProtocol.self])
        let envelope = Data((try gatewayFixture("snapshot-put")).requestBody.utf8)
        for target in [
            URL(string: "https://reset.example.workers.dev/v1/other")!,
            URL(string: "https://other.example.workers.dev/v1/snapshot")!,
        ] {
            RelayURLProtocol.harness.configure(
                status: 302, body: Data(), headers: ["Location": target.absoluteString],
                redirectURL: target)
            let result = await gateway.getSnapshot(
                endpoint: relayOrigin, readToken: readToken, etag: nil)
            #expect(result == .protocolFailure)
            #expect(RelayURLProtocol.harness.requests.count == 1)

            RelayURLProtocol.harness.configure(
                status: 302, body: Data(), headers: ["Location": target.absoluteString],
                redirectURL: target)
            #expect(
                await gateway.putSnapshot(
                    envelope, endpoint: relayOrigin, writeToken: writeToken) == .protocolFailure)
            #expect(RelayURLProtocol.harness.requests.count == 1)

            RelayURLProtocol.harness.configure(
                status: 302, body: Data(), headers: ["Location": target.absoluteString],
                redirectURL: target)
            #expect(
                await gateway.destroyRelay(endpoint: relayOrigin, adminToken: adminToken)
                    == .protocolFailure)
            #expect(RelayURLProtocol.harness.requests.count == 1)
        }
    }

    @Test func gatewayMapsTimeoutAndDeceptiveLengthsWithoutForwardingSecrets() async {
        let gateway = HTTPRelayGateway(protocolClasses: [RelayURLProtocol.self])
        RelayURLProtocol.harness.configure(
            status: 0, body: Data(), headers: [:], failure: URLError(.timedOut))
        #expect(
            await gateway.getSnapshot(endpoint: relayOrigin, readToken: readToken, etag: nil)
                == .offline)
        #expect(RelayURLProtocol.harness.requests.count == 1)
        #expect(RelayURLProtocol.harness.requests[0].timeoutInterval == 10)

        RelayURLProtocol.harness.configure(
            status: 400, body: Data(repeating: 0x20, count: 4_097),
            headers: ["Content-Type": "application/json", "Content-Length": "1"])
        #expect(
            await gateway.getSnapshot(endpoint: relayOrigin, readToken: readToken, etag: nil)
                == .protocolFailure)
        #expect(RelayURLProtocol.harness.requests.count == 1)
        let request = RelayURLProtocol.harness.requests[0]
        #expect(request.url?.host == "reset.example.workers.dev")
        #expect(request.url?.query == nil)
    }

    @Test func gatewayUsesSnapshotAndRefreshFixtures() async throws {
        let gateway = HTTPRelayGateway(protocolClasses: [RelayURLProtocol.self])
        let requestID = RequestID(data: Data(repeating: 0x56, count: 16))!

        let put = try prepared("snapshot-put")
        #expect(
            await gateway.putSnapshot(
                Data(put.requestBody.utf8), endpoint: relayOrigin, writeToken: writeToken)
                == .accepted(sequence: 7))
        try checkRequest("snapshot-put", token: writeToken)

        _ = try prepared("snapshot-get")
        let get = await gateway.getSnapshot(endpoint: relayOrigin, readToken: readToken, etag: nil)
        if case .snapshot = get {} else { Issue.record("Expected snapshot") }
        try checkRequest("snapshot-get", token: readToken)

        _ = try prepared("reader-activate")
        #expect(
            await gateway.activateReader(endpoint: relayOrigin, readToken: readToken)
                == .accepted(sequence: nil))
        try checkRequest("reader-activate", token: readToken)

        _ = try prepared("refresh-post")
        let refresh = await gateway.postRefreshRequest(
            requestID, endpoint: relayOrigin, readToken: readToken)
        if case .refreshAccepted = refresh {} else { Issue.record("Expected refresh acceptance") }
        try checkRequest("refresh-post", token: readToken)

        _ = try prepared("refresh-list")
        let listed = await gateway.listRefreshRequests(
            endpoint: relayOrigin, writeToken: writeToken)
        if case .value(let requests) = listed {
            #expect(requests.count == 1)
        } else {
            Issue.record("Expected refresh list")
        }
        try checkRequest("refresh-list", token: writeToken)

        _ = try prepared("refresh-delete")
        #expect(
            await gateway.deleteRefreshRequest(
                requestID, endpoint: relayOrigin, writeToken: writeToken) == .deleted)
        try checkRequest("refresh-delete", token: writeToken)
    }

    @Test func gatewayUsesReaderAndDestroyFixtures() async throws {
        let gateway = HTTPRelayGateway(protocolClasses: [RelayURLProtocol.self])
        let readerID = ReaderID(data: Data(repeating: 0x45, count: 16))!
        let digest = Data(SHA256.hash(data: Data(repeating: 0x89, count: 32)))

        _ = try prepared("reader-register")
        let registered = await gateway.registerReader(
            readerID, digest: digest, endpoint: relayOrigin, adminToken: adminToken)
        if case .value = registered {} else { Issue.record("Expected reader registration") }
        try checkRequest("reader-register", token: adminToken)

        _ = try prepared("reader-list")
        let listed = await gateway.listReaders(
            endpoint: relayOrigin, adminToken: adminToken)
        if case .value(let readers) = listed {
            #expect(readers.count == 1)
        } else {
            Issue.record("Expected reader list")
        }
        try checkRequest("reader-list", token: adminToken)

        _ = try prepared("reader-revoke")
        #expect(
            await gateway.revokeReader(readerID, endpoint: relayOrigin, adminToken: adminToken)
                == .deleted)
        try checkRequest("reader-revoke", token: adminToken)

        _ = try prepared("relay-destroy")
        #expect(
            await gateway.destroyRelay(endpoint: relayOrigin, adminToken: adminToken) == .deleted)
        try checkRequest("relay-destroy", token: adminToken)
    }

    private func prepared(_ name: String) throws -> GatewayFixture {
        let fixture = try gatewayFixture(name)
        var headers: [String: String] = [:]
        if !fixture.responseBody.isEmpty { headers["Content-Type"] = "application/json" }
        if let etag = fixture.etag { headers["ETag"] = etag }
        RelayURLProtocol.harness.configure(
            status: fixture.status, body: Data(fixture.responseBody.utf8), headers: headers)
        return fixture
    }

    private func checkRequest(_ name: String, token: SecretValue) throws {
        let fixture = try gatewayFixture(name)
        let requests = RelayURLProtocol.harness.requests
        #expect(requests.count == 1)
        guard let request = requests.first else { return }
        #expect(request.httpMethod == fixture.method)
        #expect(request.url?.path == fixture.path)
        #expect(RelayURLProtocol.harness.requestBodies.first == Data(fixture.requestBody.utf8))
        let encoded = token.reveal().base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(encoded)")
    }
}
