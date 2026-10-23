import Foundation
import ResetRadarApplication

/// Deterministic generator: bytes count up from 1, jitter comes from a scripted queue.
public final class FakeSecretGenerator: SecretGenerator, @unchecked Sendable {
    private struct State {
        var counter: UInt8 = 0
        var units: [Double] = []
        var fallbackUnit = 0.5
        var randomUnitCalls = 0
        var failNextRandomBytes = false
    }

    private let state = Locked(State())

    public init() {}

    public func queueUnits(_ units: [Double], then fallback: Double? = nil) {
        state.withLock {
            $0.units = units
            if let fallback { $0.fallbackUnit = fallback }
        }
    }

    public func failNextRandomBytes() { state.withLock { $0.failNextRandomBytes = true } }
    public var randomUnitCalls: Int { state.withLock { $0.randomUnitCalls } }

    public func randomBytes(count: Int) throws -> SecretValue {
        let fail = state.withLock { state -> Bool in
            defer { state.failNextRandomBytes = false }
            return state.failNextRandomBytes
        }
        if fail { throw SecretGeneratorError.wrongLength }
        let value = state.withLock { state -> UInt8 in
            state.counter &+= 1
            return state.counter
        }
        return SecretValue(Data(repeating: value, count: count))
    }

    public func randomUnit() -> Double {
        state.withLock { state in
            state.randomUnitCalls += 1
            return state.units.isEmpty ? state.fallbackUnit : state.units.removeFirst()
        }
    }

    public func digest(of secret: SecretValue) -> Data {
        Data(secret.reveal().map { ~$0 })
    }
}

/// In-memory secrets with injectable failures and read counting.
public final class FakeSecretStore: SecretStore, @unchecked Sendable {
    private struct State {
        var values: [SecretName: SecretValue] = [:]
        var readFailure: SecretStoreError?
        var writeFailure: SecretStoreError?
        var reads: [SecretName] = []
        var invalidations = 0
    }

    private let state = Locked(State())

    public init() {}

    public func setReadFailure(_ error: SecretStoreError?) {
        state.withLock { $0.readFailure = error }
    }
    public func setWriteFailure(_ error: SecretStoreError?) {
        state.withLock { $0.writeFailure = error }
    }
    public var reads: [SecretName] { state.withLock { $0.reads } }
    public var readCount: Int { reads.count }
    public var invalidations: Int { state.withLock { $0.invalidations } }
    public var names: Set<SecretName> { state.withLock { Set($0.values.keys) } }

    public func seed(_ name: SecretName, _ value: SecretValue) {
        state.withLock { $0.values[name] = value }
    }

    public func read(_ name: SecretName) async throws(SecretStoreError) -> SecretValue {
        let result = state.withLock { state -> Result<SecretValue, SecretStoreError> in
            state.reads.append(name)
            if let failure = state.readFailure { return .failure(failure) }
            guard let value = state.values[name] else { return .failure(.notFound) }
            return .success(value)
        }
        return try result.get()
    }

    public func write(_ name: SecretName, value: SecretValue) async throws(SecretStoreError) {
        let failure = state.withLock { state -> SecretStoreError? in
            if let failure = state.writeFailure { return failure }
            state.values[name] = value
            return nil
        }
        if let failure { throw failure }
    }

    public func delete(_ name: SecretName) async throws(SecretStoreError) {
        let failure = state.withLock { state -> SecretStoreError? in
            if let failure = state.writeFailure { return failure }
            state.values[name] = nil
            return nil
        }
        if let failure { throw failure }
    }

    public func invalidateCache() async { state.withLock { $0.invalidations += 1 } }
}
