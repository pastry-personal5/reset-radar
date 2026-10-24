import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain

enum RelayOperation {
    case putSnapshot
    case getSnapshot
    case activateReader
    case postRefreshRequest
    case listRefreshRequests
    case deleteRefreshRequest
    case registerReader
    case listReaders
    case revokeReader
    case destroyRelay
}

extension RelayOperation {
    var isRefresh: Bool {
        switch self {
        case .postRefreshRequest, .listRefreshRequests, .deleteRefreshRequest: true
        default: false
        }
    }
}

enum RelayMappedResult {
    case outcome(RelayOutcome)
    case refreshRequests([PendingRefreshRequest])
    case readers([RelayReader])
    case registration(Date)

    var outcome: RelayOutcome {
        if case .outcome(let value) = self { return value }
        return .protocolFailure
    }
}

struct RelayResponseContext {
    let operation: RelayOperation
    let status: Int
    let body: Data
    let etag: String?
    let conditionalETag: String?
    let submittedEnvelope: Data?
}

enum ResponseMapper {
    static func map(_ response: RelayResponseContext) -> RelayMappedResult {
        let status = response.status
        if mapPlatformQuota(response) { return .outcome(.quotaLimited) }
        if (500...599).contains(status) { return .outcome(.offline) }
        if (300...399).contains(status), status != 304 {
            return .outcome(.protocolFailure)
        }
        if status >= 400 { return .outcome(mapError(response)) }

        switch response.operation {
        case .putSnapshot, .getSnapshot: return mapSnapshot(response)
        case .activateReader, .registerReader, .listReaders, .revokeReader:
            return mapReader(response)
        case .postRefreshRequest, .listRefreshRequests, .deleteRefreshRequest:
            return mapRefresh(response)
        case .destroyRelay:
            return response.status == 204 && response.body.isEmpty
                ? .outcome(.deleted) : .outcome(.protocolFailure)
        }
    }

    private static func mapSnapshot(_ response: RelayResponseContext) -> RelayMappedResult {
        let status = response.status
        switch (response.operation, status) {
        case (.putSnapshot, 200):
            guard let sent = response.submittedEnvelope,
                let outer = EnvelopeOuter.parse(sent),
                let body = decode(SequenceBody.self, response.body), body.protocolVersion == 1,
                body.sequence == outer.sequence, response.etag == strongETag(sent)
            else { return .outcome(.protocolFailure) }
            return .outcome(.accepted(sequence: body.sequence))
        case (.getSnapshot, 200):
            guard let outer = EnvelopeOuter.parse(response.body),
                response.etag == strongETag(response.body)
            else { return .outcome(.protocolFailure) }
            return .outcome(
                .snapshot(response.body, etag: response.etag!, sequence: outer.sequence))
        case (.getSnapshot, 304):
            guard response.body.isEmpty,
                response.conditionalETag == nil || response.etag == response.conditionalETag
            else { return .outcome(.protocolFailure) }
            return .outcome(.notModified)
        default: return .outcome(.protocolFailure)
        }
    }

    private static func mapReader(_ response: RelayResponseContext) -> RelayMappedResult {
        switch (response.operation, response.status) {
        case (.activateReader, 200):
            guard let body = decode(ActivationBody.self, response.body),
                body.protocolVersion == 1, body.activated
            else { return .outcome(.protocolFailure) }
            return .outcome(.accepted(sequence: nil))
        case (.registerReader, 200):
            guard let body = decode(ExpiryBody.self, response.body), body.protocolVersion == 1
            else { return .outcome(.protocolFailure) }
            return .registration(body.expiresAt)
        case (.listReaders, 200):
            guard let body = decode(ReaderListBody.self, response.body),
                body.protocolVersion == 1, body.readers.count <= 3,
                body.readers.map(\.readerID.hex).lexicographicallyPrecedesOrEqualsSorted()
            else { return .outcome(.protocolFailure) }
            return .readers(
                body.readers.map {
                    RelayReader(id: $0.readerID, activated: $0.activated)
                })
        case (.revokeReader, 204):
            guard response.body.isEmpty else { return .outcome(.protocolFailure) }
            return .outcome(.deleted)
        default:
            return .outcome(.protocolFailure)
        }
    }

    private static func mapRefresh(_ response: RelayResponseContext) -> RelayMappedResult {
        switch (response.operation, response.status) {
        case (.postRefreshRequest, 202):
            guard let body = decode(ExpiryBody.self, response.body), body.protocolVersion == 2
            else { return .outcome(.protocolFailure) }
            return .outcome(.refreshAccepted(expiresAt: body.expiresAt))
        case (.listRefreshRequests, 200):
            guard let body = decode(RefreshListBody.self, response.body),
                body.protocolVersion == 2, body.requests.count <= 3,
                body.requests.map({ "\($0.readerID.hex)/\($0.requestID.hex)" })
                    .lexicographicallyPrecedesOrEqualsSorted(),
                body.requests.allSatisfy(\.hasValidTarget)
            else { return .outcome(.protocolFailure) }
            return .refreshRequests(
                body.requests.compactMap {
                    guard let target = $0.targetValue else { return nil }
                    return PendingRefreshRequest(
                        id: $0.requestID, readerID: $0.readerID, target: target,
                        expiresAt: $0.expiresAt)
                })
        case (.deleteRefreshRequest, 204):
            return response.body.isEmpty ? .outcome(.deleted) : .outcome(.protocolFailure)
        default: return .outcome(.protocolFailure)
        }
    }

    static func strongETag(_ envelope: Data) -> String {
        let hex = SHA256.hash(data: envelope).map { String(format: "%02x", $0) }.joined()
        return "\"\(hex)\""
    }

    private static func mapError(_ response: RelayResponseContext) -> RelayOutcome {
        let expectedVersion = response.operation.isRefresh ? 2 : 1
        guard let body = decode(ErrorBody.self, response.body),
            body.protocolVersion == expectedVersion
        else { return .protocolFailure }
        switch response.status {
        case 400: return body.code == "badRequest" ? .badRequest : .protocolFailure
        case 401: return body.code == "unauthorized" ? .unauthorized : .protocolFailure
        case 404:
            return body.code == "awaitingFirstPublish" && response.operation == .getSnapshot
                ? .awaitingFirstPublish : .protocolFailure
        case 409: return mapConflict(code: body.code, operation: response.operation)
        case 413: return body.code == "payloadTooLarge" ? .payloadTooLarge : .protocolFailure
        case 422: return body.code == "unsupportedVersion" ? .unsupportedVersion : .protocolFailure
        case 429: return mapRateLimit(code: body.code, operation: response.operation)
        default: return .protocolFailure
        }
    }

    private static func mapConflict(code: String, operation: RelayOperation) -> RelayOutcome {
        switch (operation, code) {
        case (.putSnapshot, "publisherMismatch"), (.putSnapshot, "sequenceConflict"):
            return .publisherConflict
        case (.registerReader, "readerCapReached"): return .readerCapReached
        case (.postRefreshRequest, "requestAlreadyCompleted"): return .requestAlreadyCompleted
        default: return .protocolFailure
        }
    }

    private static func mapRateLimit(code: String, operation: RelayOperation) -> RelayOutcome {
        if code == "quotaLimited" { return .quotaLimited }
        if code == "requestRateLimited", operation == .postRefreshRequest {
            return .requestRateLimited
        }
        return .protocolFailure
    }

    private static func mapPlatformQuota(_ response: RelayResponseContext) -> Bool {
        guard (400...599).contains(response.status),
            let body = try? JSONDecoder().decode(PlatformQuotaBody.self, from: response.body)
        else { return false }
        return body.cloudflareError && body.errorCategory == "rate_limit"
            && body.errorCode == 1027 && body.status == response.status
    }

    private static func decode<T: Codable>(_ type: T.Type, _ data: Data) -> T? {
        guard let value = try? WireCoding.decoder().decode(type, from: data),
            let encoded = try? WireCoding.encoder().encode(value), encoded == data
        else { return nil }
        return value
    }
}

extension Array where Element: Comparable {
    fileprivate func lexicographicallyPrecedesOrEqualsSorted() -> Bool {
        guard self == sorted() else { return false }
        return !zip(self, dropFirst()).contains { pair in pair.0 == pair.1 }
    }
}

private struct SequenceBody: Codable {
    let protocolVersion: Int
    let sequence: UInt64
}

private struct PlatformQuotaBody: Decodable {
    let cloudflareError: Bool
    let errorCategory: String
    let errorCode: Int
    let status: Int

    enum CodingKeys: String, CodingKey {
        case cloudflareError = "cloudflare_error"
        case errorCategory = "error_category"
        case errorCode = "error_code"
        case status
    }
}

private struct ActivationBody: Codable {
    let activated: Bool
    let protocolVersion: Int
}

private struct ExpiryBody: Codable {
    let expiresAt: Date
    let protocolVersion: Int
}

private struct RefreshListBody: Codable {
    let protocolVersion: Int
    let requests: [RefreshWire]
}

private struct RefreshWire: Codable {
    let accountID: AccountID?
    let expiresAt: Date
    let readerID: ReaderID
    let requestID: RequestID
    let target: String

    var targetValue: ManualRefreshTarget? {
        switch (target, accountID) {
        case ("account", .some(let accountID)): .account(accountID)
        case ("allCodex", .none): .allCodex
        default: nil
        }
    }

    var hasValidTarget: Bool { targetValue != nil }
}

private struct ReaderListBody: Codable {
    let protocolVersion: Int
    let readers: [ReaderWire]
}

private struct ReaderWire: Codable {
    let activated: Bool
    let readerID: ReaderID
}

private struct ErrorBody: Codable {
    let code: String
    let protocolVersion: Int
}
