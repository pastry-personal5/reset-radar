import Foundation
import ResetRadarApplication
import ResetRadarStorage
import ResetRadarTransport
import Testing

@testable import ResetRadarMac

private struct StubSignatureReader: SignatureReading {
    let signature: RunningSignature?

    func runningSignature() throws -> RunningSignature {
        guard let signature else { throw CocoaError(.fileReadUnknown) }
        return signature
    }
}

private actor StubSecretStore: SecretStore {
    var values: [SecretName: SecretValue] = [:]
    var error: SecretStoreError?
    var reads = 0

    func read(_ name: SecretName) throws(SecretStoreError) -> SecretValue {
        reads += 1
        if let error { throw error }
        guard let value = values[name] else { throw .notFound }
        return value
    }

    func write(_ name: SecretName, value: SecretValue) { values[name] = value }
    func delete(_ name: SecretName) { values[name] = nil }
    func invalidateCache() {}
    func setError(_ value: SecretStoreError?) { error = value }
    func readCount() -> Int { reads }
}

@Suite("Mac signing and secrets")
struct SigningAndSecretsTests {
    @Test func signingOutcomesAreTyped() {
        #expect(
            SigningCheck(
                reader: StubSignatureReader(signature: .init(teamIdentifier: "A", isAdHoc: false))
            ).evaluate(recordedTeamIdentifier: nil) == .valid(teamIdentifier: "A"))
        #expect(
            SigningCheck(
                reader: StubSignatureReader(signature: .init(teamIdentifier: "A", isAdHoc: true))
            ).evaluate(recordedTeamIdentifier: nil) == .adHoc)
        #expect(
            SigningCheck(
                reader: StubSignatureReader(signature: .init(teamIdentifier: nil, isAdHoc: false))
            ).evaluate(recordedTeamIdentifier: nil) == .missingTeam)
        #expect(
            SigningCheck(
                reader: StubSignatureReader(signature: .init(teamIdentifier: "B", isAdHoc: false))
            ).evaluate(recordedTeamIdentifier: "A") == .changedTeam(recorded: "A", running: "B"))
        #expect(
            SigningCheck(reader: StubSignatureReader(signature: nil)).evaluate(
                recordedTeamIdentifier: nil) == .unreadable)
    }

    @Test func installedAndDevelopmentNamespacesAreSeparated() {
        let release = MacBuildFlavor.release
        let development = MacBuildFlavor.development
        #expect(release.storage.directory.lastPathComponent == "ResetRadar")
        #expect(development.storage.directory.lastPathComponent == "ResetRadar.dev")
        #expect(release.keychainService == "com.unidentifiedstealthstartup.ResetRadarMac.transport")
        #expect(
            development.keychainService
                == "com.unidentifiedstealthstartup.ResetRadarMac.transport.dev")
    }

    @Test func testsUseTemporaryStorageAndNoKeychainNamespace() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let flavor = MacBuildFlavor.test(root: root)
        #expect(flavor.storage.directory == root)
        #expect(flavor.keychainService == nil)
    }

    @Test func cacheSurvivesLaterLockAndInvalidationRequiresARead() async throws {
        let base = StubSecretStore()
        let value = SecretValue(Data(repeating: 7, count: 32))
        await base.write(.contentKey, value: value)
        let cache = SessionSecretCache(store: base)
        #expect(try await cache.read(.contentKey) == value)
        await base.setError(.interactionRequired)
        #expect(try await cache.read(.contentKey) == value)
        #expect(await base.readCount() == 1)
        await cache.invalidateCache()
        await #expect(throws: SecretStoreError.interactionRequired) {
            try await cache.read(.contentKey)
        }
        #expect(await cache.availability == .secretsUnavailable)
    }

    @Test func retryRunsOnActiveSession() async {
        actor Counter {
            var value = 0
            func increment() { value += 1 }
        }
        let counter = Counter()
        let driver = SecretRetryDriver { await counter.increment() }
        await driver.loginSessionBecameActive()
        #expect(await counter.value == 1)
        await driver.stop()
    }
}
