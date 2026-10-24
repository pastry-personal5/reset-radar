import Foundation
import ResetRadarApplication
import ResetRadarDomain

public final class HTTPRelayGateway: RelayGateway, @unchecked Sendable {
    private let session: URLSession

    public init(protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        session = URLSession(configuration: configuration)
    }

    public func putSnapshot(
        _ envelope: Data, endpoint: URL, writeToken: SecretValue
    ) async -> RelayOutcome {
        guard envelope.count <= AESGCMEnvelopeCipher.maximumEnvelopeBytes else {
            return .payloadTooLarge
        }
        guard EnvelopeOuter.parse(envelope) != nil else { return .badRequest }
        return await perform(
            .putSnapshot, method: "PUT", path: "/v1/snapshot", endpoint: endpoint,
            token: writeToken, body: envelope
        ).outcome
    }

    public func getSnapshot(
        endpoint: URL, readToken: SecretValue, etag: String?
    ) async -> RelayOutcome {
        if let etag, !Self.validETag(etag) { return .protocolFailure }
        return await perform(
            .getSnapshot, method: "GET", path: "/v1/snapshot", endpoint: endpoint,
            token: readToken, conditionalETag: etag
        ).outcome
    }

    public func activateReader(endpoint: URL, readToken: SecretValue) async -> RelayOutcome {
        await perform(
            .activateReader, method: "POST", path: "/v1/readers/activate",
            endpoint: endpoint, token: readToken
        ).outcome
    }

    public func postRefreshRequest(
        _ id: RequestID, target: ManualRefreshTarget, endpoint: URL,
        readToken: SecretValue
    ) async -> RelayOutcome {
        let body = try? WireCoding.encoder().encode(
            RefreshRequestBody(requestID: id, target: target))
        guard let body, body.count <= 192 else { return .protocolFailure }
        return await perform(
            .postRefreshRequest, method: "POST", path: "/v2/refresh-requests",
            endpoint: endpoint, token: readToken, body: body
        ).outcome
    }

    public func listRefreshRequests(
        endpoint: URL, writeToken: SecretValue
    ) async -> RelayResponse<[PendingRefreshRequest]> {
        let mapped = await perform(
            .listRefreshRequests, method: "GET", path: "/v2/refresh-requests",
            endpoint: endpoint, token: writeToken)
        if case .refreshRequests(let requests) = mapped { return .value(requests) }
        return .outcome(mapped.outcome)
    }

    public func deleteRefreshRequest(
        _ id: RequestID, endpoint: URL, writeToken: SecretValue
    ) async -> RelayOutcome {
        await perform(
            .deleteRefreshRequest, method: "DELETE",
            path: "/v2/refresh-requests/\(id.hex)", endpoint: endpoint,
            token: writeToken
        ).outcome
    }

    public func registerReader(
        _ id: ReaderID, digest: Data, endpoint: URL, adminToken: SecretValue
    ) async -> RelayResponse<Date> {
        guard digest.count == 32,
            let body = try? WireCoding.encoder().encode(DigestBody(digest: digest))
        else { return .outcome(.protocolFailure) }
        let mapped = await perform(
            .registerReader, method: "PUT", path: "/v1/readers/\(id.hex)",
            endpoint: endpoint, token: adminToken, body: body)
        if case .registration(let expiry) = mapped { return .value(expiry) }
        return .outcome(mapped.outcome)
    }

    public func listReaders(
        endpoint: URL, adminToken: SecretValue
    ) async -> RelayResponse<[RelayReader]> {
        let mapped = await perform(
            .listReaders, method: "GET", path: "/v1/readers", endpoint: endpoint,
            token: adminToken)
        if case .readers(let readers) = mapped { return .value(readers) }
        return .outcome(mapped.outcome)
    }

    public func revokeReader(
        _ id: ReaderID, endpoint: URL, adminToken: SecretValue
    ) async -> RelayOutcome {
        await perform(
            .revokeReader, method: "DELETE", path: "/v1/readers/\(id.hex)",
            endpoint: endpoint, token: adminToken
        ).outcome
    }

    public func destroyRelay(endpoint: URL, adminToken: SecretValue) async -> RelayOutcome {
        await perform(
            .destroyRelay, method: "DELETE", path: "/v1/relay", endpoint: endpoint,
            token: adminToken
        ).outcome
    }

    private func perform(
        _ operation: RelayOperation, method: String, path: String, endpoint: URL,
        token: SecretValue, body: Data? = nil, conditionalETag: String? = nil
    ) async -> RelayMappedResult {
        guard OriginGuard.accepts(endpoint), token.reveal().count == 32,
            let url = URL(string: endpoint.absoluteString + path)
        else { return .outcome(.protocolFailure) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Bearer \(Base64URL.encode(token.reveal()))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let conditionalETag {
            request.setValue(conditionalETag, forHTTPHeaderField: "If-None-Match")
        }
        let redirectGuard = RedirectRejector()
        do {
            let (stream, response) = try await session.bytes(for: request, delegate: redirectGuard)
            guard let http = response as? HTTPURLResponse, response.url == url else {
                return .outcome(.protocolFailure)
            }
            let limit = operation == .getSnapshot && http.statusCode == 200 ? 65_536 : 4_096
            if response.expectedContentLength > Int64(limit) {
                return .outcome(.protocolFailure)
            }
            let received: Data
            do {
                received = try await BoundedBodyReader.read(stream, maximumBytes: limit)
            } catch BodyLimitError.tooLarge {
                return .outcome(.protocolFailure)
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")
            guard received.isEmpty || Self.isJSONContentType(contentType) else {
                return .outcome(.protocolFailure)
            }
            return ResponseMapper.map(
                RelayResponseContext(
                    operation: operation, status: http.statusCode, body: received,
                    etag: http.value(forHTTPHeaderField: "ETag"),
                    conditionalETag: conditionalETag, submittedEnvelope: body))
        } catch {
            return .outcome(redirectGuard.wasRedirected ? .protocolFailure : .offline)
        }
    }

    private static func validETag(_ value: String) -> Bool {
        let characters = Array(value.utf8)
        guard characters.count == 66, characters.first == UInt8(ascii: "\""),
            characters.last == UInt8(ascii: "\"")
        else { return false }
        return characters.dropFirst().dropLast().allSatisfy {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0)
        }
    }

    private static func isJSONContentType(_ value: String?) -> Bool {
        guard let mediaType = value?.split(separator: ";", maxSplits: 1).first else { return false }
        return mediaType.trimmingCharacters(in: .whitespaces).lowercased() == "application/json"
    }
}

private final class RedirectRejector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirected = false

    var wasRedirected: Bool { lock.withLock { redirected } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.withLock { redirected = true }
        completionHandler(nil)
    }
}

private struct RefreshRequestBody: Encodable {
    let protocolVersion = 2
    let requestID: RequestID
    let target: String
    let accountID: AccountID?

    init(requestID: RequestID, target: ManualRefreshTarget) {
        self.requestID = requestID
        switch target {
        case .account(let accountID):
            self.target = "account"
            self.accountID = accountID
        case .allCodex:
            self.target = "allCodex"
            self.accountID = nil
        }
    }
}

private struct DigestBody: Encodable {
    let protocolVersion = 1
    let tokenDigest: String

    init(digest: Data) {
        tokenDigest = digest.map { String(format: "%02x", $0) }.joined()
    }
}
