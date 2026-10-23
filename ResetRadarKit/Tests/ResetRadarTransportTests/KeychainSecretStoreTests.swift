import Foundation
import LocalAuthentication
import ResetRadarApplication
import Security
import Testing

@testable import ResetRadarTransport

final class StubSecItemBackend: SecItemBackend, @unchecked Sendable {
    private struct State {
        var values: [String: Data] = [:]
        var readCount = 0
        var lastQuery: [String: Any] = [:]
        var lastUpdateAttributes: [String: Any] = [:]
        var usedAuthenticationContext = false
        var readStatus: OSStatus?
    }

    private let lock = NSLock()
    private var state = State()

    var readCount: Int { lock.withLock { state.readCount } }
    var lastQuery: [String: Any] { lock.withLock { state.lastQuery } }
    var lastUpdateAttributes: [String: Any] { lock.withLock { state.lastUpdateAttributes } }
    var usedAuthenticationContext: Bool { lock.withLock { state.usedAuthenticationContext } }

    func setReadStatus(_ status: OSStatus?) {
        lock.withLock { state.readStatus = status }
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.withLock {
            state.readCount += 1
            state.lastQuery = query
            state.usedAuthenticationContext =
                (query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed
                == true
            if let status = state.readStatus { return (status, nil) }
            guard let data = state.values[key(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            state.lastQuery = attributes
            state.usedAuthenticationContext =
                (attributes[kSecUseAuthenticationContext as String] as? LAContext)?
                .interactionNotAllowed
                == true
            let itemKey = key(attributes)
            guard state.values[itemKey] == nil else { return errSecDuplicateItem }
            state.values[itemKey] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            state.lastQuery = query
            state.lastUpdateAttributes = attributes
            state.usedAuthenticationContext =
                (query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed
                == true
            guard state.values[key(query)] != nil else { return errSecItemNotFound }
            state.values[key(query)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            state.lastQuery = query
            state.usedAuthenticationContext =
                (query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed
                == true
            guard state.values.removeValue(forKey: key(query)) != nil else {
                return errSecItemNotFound
            }
            return errSecSuccess
        }
    }

    private func key(_ query: [String: Any]) -> String {
        guard let service = query[kSecAttrService as String] as? String,
            let account = query[kSecAttrAccount as String] as? String
        else { return "invalid-query" }
        return "\(service)/\(account)"
    }

}

@Test func iosPolicySuppliesAccessGroupAndFirstUnlockOnEveryOperation() async throws {
    let backend = StubSecItemBackend()
    let accessGroup = "TEAMID.group.com.unidentifiedstealthstartup.ResetRadar"
    let store = KeychainSecretStore(
        backend: backend, build: .debug, policy: .iosDataProtection(accessGroup: accessGroup))
    let first = SecretValue(Data(repeating: 0x41, count: 32))
    let second = SecretValue(Data(repeating: 0x42, count: 32))
    try await store.write(.readToken, value: first)
    #expect(backend.lastQuery[kSecAttrAccessGroup as String] as? String == accessGroup)
    #expect(
        backend.lastQuery[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    #expect(try await store.read(.readToken) == first)
    #expect(backend.lastQuery[kSecAttrAccessGroup as String] as? String == accessGroup)
    #expect(try await store.read(.readToken) == first)
    #expect(backend.readCount == 2)
    try await store.write(.readToken, value: second)
    #expect(backend.lastQuery[kSecAttrAccessGroup as String] as? String == accessGroup)
    #expect(
        backend.lastUpdateAttributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    try await store.delete(.readToken)
    #expect(backend.lastQuery[kSecAttrAccessGroup as String] as? String == accessGroup)
}

private func expectReadError(
    _ expected: SecretStoreError, from store: KeychainSecretStore, name: SecretName
) async {
    do {
        _ = try await store.read(name)
        Issue.record("Expected a secret-store error")
    } catch {
        #expect(error == expected)
    }
}

@Test func keychainStubVerifiesCacheMutationAndNoPrompt() async throws {
    let backend = StubSecItemBackend()
    let store = KeychainSecretStore(backend: backend, build: .debug)
    let first = SecretValue(Data(repeating: 0x11, count: 32))
    let replacement = SecretValue(Data(repeating: 0x22, count: 32))
    try await store.write(.contentKey, value: first)
    #expect(backend.usedAuthenticationContext)
    #expect(try await store.read(.contentKey) == first)
    #expect(try await store.read(.contentKey) == first)
    #expect(backend.readCount == 1)
    #expect(backend.usedAuthenticationContext)
    try await store.write(.contentKey, value: replacement)
    #expect(backend.usedAuthenticationContext)
    #expect(try await store.read(.contentKey) == replacement)
    #expect(backend.readCount == 2)
    try await store.delete(.contentKey)
    #expect(backend.usedAuthenticationContext)
    try await store.delete(.contentKey)
    await expectReadError(.notFound, from: store, name: .contentKey)
}

@Test func keychainStubVerifiesBuildIsolationAndLockedRead() async throws {
    let backend = StubSecItemBackend()
    let debugStore = KeychainSecretStore(backend: backend, build: .debug)
    let releaseStore = KeychainSecretStore(backend: backend, build: .release)
    let value = SecretValue(Data(repeating: 0x33, count: 32))
    try await debugStore.write(.writeToken, value: value)
    await expectReadError(.notFound, from: releaseStore, name: .writeToken)
    backend.setReadStatus(errSecInteractionNotAllowed)
    await expectReadError(.interactionRequired, from: debugStore, name: .writeToken)
    backend.setReadStatus(nil)
    #expect(try await debugStore.read(.writeToken) == value)
    backend.setReadStatus(errSecInteractionNotAllowed)
    #expect(try await debugStore.read(.writeToken) == value)
    await debugStore.invalidateCache()
    await expectReadError(.interactionRequired, from: debugStore, name: .writeToken)
}

@Test func concurrentMacReadsShareCacheAndReplacementInvalidatesIt() async throws {
    let backend = StubSecItemBackend()
    let store = KeychainSecretStore(backend: backend, build: .debug)
    let first = SecretValue(Data(repeating: 0x51, count: 32))
    let replacement = SecretValue(Data(repeating: 0x52, count: 32))
    try await store.write(.adminToken, value: first)
    try await withThrowingTaskGroup(of: SecretValue.self) { group in
        for _ in 0..<16 { group.addTask { try await store.read(.adminToken) } }
        for try await value in group { #expect(value == first) }
    }
    #expect(backend.readCount == 1)
    let racingRead = Task { try await store.read(.adminToken) }
    let replacementWrite = Task { try await store.write(.adminToken, value: replacement) }
    _ = try await racingRead.value
    try await replacementWrite.value
    #expect(try await store.read(.adminToken) == replacement)
    #expect(backend.readCount == 2)
}

@Test func unexpectedSecItemStatusIsRedactedToAStatusClass() async {
    let backend = StubSecItemBackend()
    backend.setReadStatus(errSecParam)
    let store = KeychainSecretStore(backend: backend, build: .debug)
    await expectReadError(
        .unexpected(statusClass: Int(errSecParam)), from: store, name: .contentKey)
}
