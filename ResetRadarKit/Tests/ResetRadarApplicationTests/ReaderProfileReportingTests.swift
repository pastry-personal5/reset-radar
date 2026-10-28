import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

private actor PausedSecretStore: SecretStore {
    private let base: FakeSecretStore
    private var pausedRead: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    init(base: FakeSecretStore) { self.base = base }

    func read(_ name: SecretName) async throws(SecretStoreError) -> SecretValue {
        if name == .contentKey {
            await withCheckedContinuation { continuation in
                pausedRead = continuation
                observer?.resume()
                observer = nil
            }
        }
        return try await base.read(name)
    }

    func waitUntilPaused() async {
        if pausedRead != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resume() {
        pausedRead?.resume()
        pausedRead = nil
    }

    func write(_ name: SecretName, value: SecretValue) async throws(SecretStoreError) {
        try await base.write(name, value: value)
    }

    func delete(_ name: SecretName) async throws(SecretStoreError) {
        try await base.delete(name)
    }

    func invalidateCache() async { await base.invalidateCache() }
}

private struct ProfileCipherStub: ReaderProfileCipher {
    func seal(
        _ profile: ReaderProfile, header: ReaderProfileHeader, key: SecretValue
    ) throws(ReaderProfileCipherError) -> Data {
        Data(UUID().uuidString.utf8)
    }

    func open(
        _ envelope: Data, expected: ReaderProfileHeader?, key: SecretValue
    ) throws(ReaderProfileCipherError) -> (header: ReaderProfileHeader, profile: ReaderProfile) {
        throw .malformed
    }
}

@Suite struct ReaderProfileReportingTests {
    @Test func staleProfileCannotBeInstalledAfterPairingChanges() async throws {
        let rig = ReaderRig()
        let name = try ReaderProfileName(validating: "My iPhone")
        rig.store.seed {
            $0.readerProfile = ReaderProfileState(
                name: name, namingMode: .custom, deviceClass: .phone)
        }
        let secrets = PausedSecretStore(base: rig.secrets)
        let report = ReportReaderProfile(
            reader: rig.store, secrets: secrets, relay: rig.relay,
            cipher: ProfileCipherStub())
        let task = Task { await report.retry() }
        await secrets.waitUntilPaused()
        rig.store.seed { state in
            state.pairing?.readerID = readerB
            state.pairing?.publisherID = otherPublisher
        }
        await secrets.resume()
        #expect(await task.value == .waiting)
        #expect(rig.store.state.readerProfile?.revision == 0)
        #expect(rig.store.state.readerProfile?.pendingEnvelope == nil)
    }
}
