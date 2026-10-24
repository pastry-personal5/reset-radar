import Foundation
import ResetRadarDomain

public protocol CodexRPCSession: Sendable {
    var notifications: AsyncStream<JSONRPCNotification> { get }
    func initialize(params: JSONValue) async throws -> JSONValue
    func accountStatus() async throws -> JSONValue
    func rateLimits() async throws -> JSONValue
    func stop() async
}

extension JSONRPCClient: CodexRPCSession {}

public protocol CodexRPCSessionFactory: Sendable {
    func makeSession(generation: UInt64) async throws -> any CodexRPCSession
}

public enum CodexSourceFailure: Error, Equatable, Sendable {
    case notConfigured
    case notInstalled
    case permissionDenied
    case signedOut
    case incompatible
    case malformed
    case timeout
    case processExited
    case accountScope
    case duplicateProviderScope
    case temporarilyUnavailable
}

public enum CodexAppServerSourceError: Error, Equatable, Sendable {
    case stopped
}

extension CodexSourceFailure {
    init(_ error: JSONRPCClientError) {
        switch error {
        case .requestTimedOut: self = .timeout
        case .processExited, .transportFailure, .stopped, .requestCancelled: self = .processExited
        case .remoteError(let code):
            self =
                code == -32603 || (-32099 ... -32000).contains(code)
                ? .temporarilyUnavailable : .incompatible
        case .protocolViolation, .requestIDExhausted, .notInitialized, .alreadyInitialized:
            self = .incompatible
        }
    }

    init(_ error: CodexRateLimitError) {
        self = error == .accountScopeFailure ? .accountScope : .malformed
    }

    init(thrown error: any Error) {
        switch error {
        case let failure as CodexSourceFailure: self = failure
        case let error as CodexRateLimitError: self.init(error)
        case let error as JSONRPCClientError: self.init(error)
        default: self = .temporarilyUnavailable
        }
    }

    var diagnosticClass: ProviderFailureClass {
        switch self {
        case .notConfigured, .notInstalled: .notInstalled
        case .permissionDenied: .permissionDenied
        case .signedOut: .signedOut
        case .incompatible: .incompatible
        case .malformed: .malformed
        case .timeout: .timeout
        case .processExited: .processExited
        case .accountScope: .accountScope
        case .duplicateProviderScope: .duplicateProviderScope
        case .temporarilyUnavailable: .temporarilyUnavailable
        }
    }
}

extension JSONValue {
    static let codexInitializeParameters = JSONValue.object([
        "clientInfo": .object([
            "name": .string("reset-radar"), "version": .string("1"),
        ])
    ])
}
