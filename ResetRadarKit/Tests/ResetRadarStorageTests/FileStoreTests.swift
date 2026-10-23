import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarStorage

private struct Boom: Error {}

private func bytesOf(_ directory: TemporaryDirectory, _ name: String) throws -> Data {
    try Data(contentsOf: directory.url.appending(path: name))
}

private func locations(_ directory: TemporaryDirectory) -> StorageLocations {
    StorageLocations(root: directory.url, flavor: .release)
}

struct FilePublisherStoreTests {
    @Test func throwingClosureLeavesTheBytesIdentical() async throws {
        let directory = TemporaryDirectory()
        let store = FilePublisherStore(locations: locations(directory))
        _ = try await store.nextSequence()
        let before = try bytesOf(directory, "publisher.json")
        await #expect(throws: Boom.self) {
            try await store.transact { state in
                state.lifecycle = .active
                throw Boom()
            }
        }
        #expect(try bytesOf(directory, "publisher.json") == before)
    }

    @Test func writeFailureKeepsThePreviousFileAndDoesNotReturnTheSequence() async throws {
        let directory = TemporaryDirectory()
        let fault = WriteFault()
        let store = FilePublisherStore(locations: locations(directory), writer: fault.writer)
        #expect(try await store.nextSequence() == 1)
        fault.failing = true
        await #expect(throws: StorageFailure.self) { try await store.nextSequence() }
        await #expect(throws: StorageFailure.self) {
            try await store.transact { $0.lifecycle = .active }
        }
        fault.failing = false
        let relaunched = FilePublisherStore(locations: locations(directory))
        let state = try await relaunched.load()
        #expect(state.sequence == 1)
        #expect(state.lifecycle == .notConfigured)
    }

    @Test func sequenceIncreasesAcrossRelaunches() async throws {
        let directory = TemporaryDirectory()
        var last: UInt64 = 0
        for _ in 0..<4 {
            let next = try await FilePublisherStore(locations: locations(directory)).nextSequence()
            #expect(next > last)
            last = next
        }
        #expect(last == 4)
    }

    @Test func exhaustedSequenceThrowsWithoutReplacingTheFile() async throws {
        let directory = TemporaryDirectory()
        let store = FilePublisherStore(locations: locations(directory))
        try await store.transact { $0.sequence = UInt64.max }
        let before = try bytesOf(directory, "publisher.json")
        await #expect(throws: StorageFailure.io(code: Int(EOVERFLOW))) {
            try await store.nextSequence()
        }
        #expect(try bytesOf(directory, "publisher.json") == before)
    }

    @Test func fiftyConcurrentIncrementsOverTwoInstancesLoseNothing() async throws {
        let directory = TemporaryDirectory()
        let stores = [
            FilePublisherStore(locations: locations(directory)),
            FilePublisherStore(locations: locations(directory)),
        ]
        let results = try await withThrowingTaskGroup(of: UInt64.self) { group in
            for index in 0..<50 {
                group.addTask { try await stores[index % 2].nextSequence() }
            }
            return try await group.reduce(into: [UInt64]()) { $0.append($1) }
        }
        #expect(Set(results) == Set(1...50))
        #expect(try await stores[0].load().sequence == 50)
    }

    @Test func lifecycleSurvivesRelaunch() async throws {
        let directory = TemporaryDirectory()
        let store = FilePublisherStore(locations: locations(directory))
        try await store.transact {
            $0.lifecycle = .setupPending
            $0.handledRequests = [requestID(7): at(60)]
        }
        let relaunched = FilePublisherStore(locations: locations(directory))
        let state = try await relaunched.load()
        #expect(state.lifecycle == .setupPending)
        #expect(state.handledRequests == [requestID(7): at(60)])
        try await relaunched.transact { $0.lifecycle = .destroyPending }
        #expect(
            try await FilePublisherStore(locations: locations(directory)).load().lifecycle
                == .destroyPending)
    }

    @Test func acceptedSequenceAboveTheAllocatedSequenceIsRefused() async throws {
        let directory = TemporaryDirectory()
        let store = FilePublisherStore(locations: locations(directory))
        _ = try await store.nextSequence()
        let before = try bytesOf(directory, "publisher.json")
        await #expect(throws: StorageFailure.corrupt) {
            try await store.transact {
                $0.sequence = 2
                $0.lastPublishedSequence = 9
            }
        }
        #expect(try bytesOf(directory, "publisher.json") == before)
    }

    @Test func onePublisherCannotReuseAllocatedOrAcceptedSequences() async throws {
        let directory = TemporaryDirectory()
        let store = FilePublisherStore(locations: locations(directory))
        try await store.transact { $0.publisherID = publisher }
        #expect(try await store.nextSequence() == 1)
        #expect(try await store.nextSequence() == 2)
        try await store.transact { $0.lastPublishedSequence = 1 }
        let before = try bytesOf(directory, "publisher.json")
        let relaunched = FilePublisherStore(locations: locations(directory))
        await #expect(throws: StorageFailure.corrupt) {
            try await relaunched.transact { $0.sequence = 1 }
        }
        await #expect(throws: StorageFailure.corrupt) {
            try await relaunched.transact { $0.lastPublishedSequence = 0 }
        }
        #expect(try bytesOf(directory, "publisher.json") == before)
        #expect(try await relaunched.nextSequence() == 3)
    }
}

struct FileReaderStoreTests {
    @Test func installationIDIsGeneratedOnceAndSurvivesRelaunch() async throws {
        let directory = TemporaryDirectory()
        let first = try await FileReaderStore(locations: locations(directory)).load().installationID
        let second = try await FileReaderStore(locations: locations(directory)).load()
            .installationID
        #expect(first == second)
        let other = TemporaryDirectory()
        #expect(
            try await FileReaderStore(locations: locations(other)).load().installationID != first)
    }

    @Test func installationIDIsRetainedWhenPairingIsCleared() async throws {
        let directory = TemporaryDirectory()
        let store = FileReaderStore(locations: locations(directory))
        let id = try await store.load().installationID
        try await store.transact {
            $0.pairing = pairing
            $0.snapshot = snapshot()
            $0.committedSequence = 5
        }
        try await store.transact {
            $0.pairing = nil
            $0.snapshot = nil
            $0.committedSequence = nil
            $0.forgetCleanupPending = true
        }
        let state = try await FileReaderStore(locations: locations(directory)).load()
        #expect(state.installationID == id)
        #expect(state.forgetCleanupPending)
    }

    @Test func wholeStateRoundTrips() async throws {
        let directory = TemporaryDirectory()
        let store = FileReaderStore(locations: locations(directory))
        try await store.transact {
            $0.snapshot = snapshot()
            $0.pairing = pairing
            $0.committedSequence = 5
            $0.etag = "\"abc\""
            $0.lease = FetchClaim(id: UUID(), expiresAt: at(30))
            $0.pendingManualRequest = PendingManualRequest(requestID: requestID(2), deadline: at(9))
            $0.watchErasePending = WatchErasure(clear: watchPayload(4, cleared: true))
            $0.lastWatchPayload = watchPayload(3)
            $0.complicationTransfers = [at(1), at(2)]
            $0.needsAppReconcile = true
        }
        let expected = try await store.load()
        let reloaded = try await FileReaderStore(locations: locations(directory)).load()
        #expect(reloaded == expected)
        #expect(reloaded.snapshot == snapshot())
    }

    @Test func interruptedReplacementNeverSplitsSnapshotAndSequence() async throws {
        let directory = TemporaryDirectory()
        let fault = WriteFault()
        let store = FileReaderStore(locations: locations(directory), writer: fault.writer)
        try await store.transact {
            $0.snapshot = snapshot(percent: 10)
            $0.committedSequence = 1
        }
        fault.failing = true
        await #expect(throws: StorageFailure.self) {
            try await store.transact {
                $0.snapshot = snapshot(percent: 20)
                $0.committedSequence = 2
            }
        }
        let state = try await FileReaderStore(locations: locations(directory)).load()
        #expect(state.snapshot == snapshot(percent: 10))
        #expect(state.committedSequence == 1)
    }

    @Test func concurrentWritersLoseNoUpdate() async throws {
        let directory = TemporaryDirectory()
        let stores = [
            FileReaderStore(locations: locations(directory)),
            FileReaderStore(locations: locations(directory)),
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { try await stores[index % 2].transact { $0.failureCount += 1 } }
            }
            try await group.waitForAll()
        }
        #expect(try await stores[0].load().failureCount == 50)
    }

    @Test func corruptFileThrowsOnceInsteadOfSilentlyResetting() async throws {
        let directory = TemporaryDirectory()
        let store = FileReaderStore(locations: locations(directory))
        let id = try await store.load().installationID
        try Data().write(to: directory.url.appending(path: "reader.json"))
        await #expect(throws: StorageFailure.corrupt) { try await store.load() }
        #expect(
            FileManager.default.fileExists(
                atPath: directory.url.appending(path: "reader.json.corrupt").path))
        #expect(try await store.load().installationID != id)
    }
}

struct FileWatchCacheStoreTests {
    @Test func tombstoneHoldAndPendingInstallationSurviveRelaunch() async throws {
        let directory = TemporaryDirectory()
        let store = FileWatchCacheStore(locations: locations(directory))
        try await store.transact {
            $0.cleared = true
            $0.deliveryRevision = 7
            $0.localEraseHold = true
            $0.pendingInstallation = watchPayload(8)
        }
        let state = try await FileWatchCacheStore(locations: locations(directory)).load()
        #expect(state.cleared)
        #expect(state.deliveryRevision == 7)
        #expect(state.localEraseHold)
        #expect(state.pendingInstallation == watchPayload(8))
    }

    @Test func interruptedReplacementNeverSplitsSnapshotAndRevision() async throws {
        let directory = TemporaryDirectory()
        let fault = WriteFault()
        let store = FileWatchCacheStore(locations: locations(directory), writer: fault.writer)
        try await store.transact {
            $0.snapshot = snapshot(percent: 10)
            $0.deliveryRevision = 1
        }
        fault.failing = true
        await #expect(throws: StorageFailure.self) {
            try await store.transact {
                $0.snapshot = nil
                $0.cleared = true
                $0.deliveryRevision = 2
            }
        }
        let state = try await FileWatchCacheStore(locations: locations(directory)).load()
        #expect(state.snapshot == snapshot(percent: 10))
        #expect(state.deliveryRevision == 1)
        #expect(!state.cleared)
    }
}

struct NestedSchemaTests {
    /// A snapshot written by a newer build inside an otherwise current bundle.
    private func bundleWithNewerSnapshot(_ directory: TemporaryDirectory) async throws -> Data {
        let store = FileReaderStore(locations: locations(directory))
        try await store.transact {
            $0.pairing = pairing
            $0.snapshot = snapshot()
        }
        let url = directory.url.appending(path: "reader.json")
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var payload = try #require(object["payload"] as? [String: Any])
        var nested = try #require(payload["snapshot"] as? [String: Any])
        nested["schemaVersion"] = 2
        payload["snapshot"] = nested
        object["payload"] = payload
        let edited = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try edited.write(to: url)
        return edited
    }

    @Test func aNewerNestedSnapshotIsIncompatibleAndLeavesTheBundleUntouched() async throws {
        let directory = TemporaryDirectory()
        let edited = try await bundleWithNewerSnapshot(directory)
        let store = FileReaderStore(locations: locations(directory))
        await #expect(throws: StorageFailure.incompatible(foundVersion: 2)) {
            try await store.load()
        }
        await #expect(throws: StorageFailure.incompatible(foundVersion: 2)) {
            try await store.transact { $0.failureCount += 1 }
        }
        #expect(try bytesOf(directory, "reader.json") == edited)
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.url.appending(path: "reader.json.corrupt").path))
    }
}
