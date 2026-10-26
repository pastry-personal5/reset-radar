import Foundation
import ResetRadarApplication
import ResetRadarStorage
import ResetRadarTestSupport
import Testing
import UIKit

@testable import ResetRadar

@Suite struct ReaderCompositionTests {
    let container = URL(filePath: "/AppGroup", directoryHint: .isDirectory)
    let support = URL(filePath: "/ApplicationSupport", directoryHint: .isDirectory)

    @Test func releaseRequiresTheSharedAppGroupContainer() throws {
        #expect(throws: ReaderComposition.CompositionError.appGroupUnavailable) {
            try ReaderComposition.storageLocations(
                appGroupContainer: nil, applicationSupport: support, build: .release)
        }
        let release = try ReaderComposition.storageLocations(
            appGroupContainer: container, applicationSupport: support, build: .release)
        #expect(release.directory == container)
    }

    @Test func developmentStaysInItsOwnDebugDirectoryEvenWithoutTheAppGroup() throws {
        let shared = try ReaderComposition.storageLocations(
            appGroupContainer: container, applicationSupport: support, build: .development)
        #expect(shared.directory == container.appending(path: "Debug", directoryHint: .isDirectory))
        let unsigned = try ReaderComposition.storageLocations(
            appGroupContainer: nil, applicationSupport: support, build: .development)
        #expect(
            unsigned.directory.path(percentEncoded: false)
                == "/ApplicationSupport/ResetRadar/Debug/")
    }

    @Test func theKeychainGroupMustBeTheExpandedSharedGroup() throws {
        let expanded = "TEAMID.group.com.unidentifiedstealthstartup.ResetRadar"
        #expect(try ReaderComposition.keychainAccessGroup(infoValue: expanded) == expanded)
        for invalid: Any? in [
            nil, 7, "$(AppIdentifierPrefix)group.com.unidentifiedstealthstartup.ResetRadar",
            "TEAMID.group.example.Other",
        ] {
            #expect(throws: ReaderComposition.CompositionError.keychainGroupUnavailable) {
                try ReaderComposition.keychainAccessGroup(infoValue: invalid)
            }
        }
    }

    @Test func releasePreferencesFailClosedWithoutTheAppGroupSuite() throws {
        #expect(throws: ReaderComposition.CompositionError.preferencesUnavailable) {
            try ReaderComposition.preferenceStore(appGroupSuite: nil, build: .release)
        }
    }

    @Test func onlyADevelopmentTestLaunchSelectsASyntheticOrHostedMode() {
        let scenario = ReaderLaunch.current(
            arguments: ["app", ReaderLaunch.scenarioArgument, "paired"], environment: [:])
        guard case .synthetic(.paired) = scenario else {
            Issue.record("expected the synthetic paired scenario")
            return
        }
        let hosted = ReaderLaunch.current(
            arguments: ["app"], environment: ["XCTestConfigurationFilePath": "/tmp/x"])
        guard case .unitTestHost = hosted else {
            Issue.record("expected the unit-test host mode")
            return
        }
        let unknown = ReaderLaunch.current(
            arguments: ["app", ReaderLaunch.scenarioArgument, "unknown"], environment: [:])
        guard case .live = unknown else {
            Issue.record("an unknown scenario must launch normally")
            return
        }
    }

    @Test func theBackgroundAssertionBracketsEachTransactionOnly() async throws {
        let assertion = RecordingAssertion()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = BackgroundTaskReaderStore(
            store: FileReaderStore(locations: StorageLocations(root: root, flavor: .debug)),
            assertion: assertion)
        _ = try await store.load()
        #expect(assertion.events.isEmpty)
        try await store.transact { $0.failureCount = 1 }
        struct Refused: Error {}
        await #expect(throws: Refused.self) {
            try await store.transact { _ in throw Refused() }
        }
        #expect(assertion.events == ["begin", "end", "begin", "end"])
        #expect(try await store.load().failureCount == 1)
    }
}

final class RecordingAssertion: BackgroundAssertion, @unchecked Sendable {
    private let log = Locked<[String]>([])
    var events: [String] { log.snapshot }

    func begin() async -> UIBackgroundTaskIdentifier {
        log.withLock { $0.append("begin") }
        return UIBackgroundTaskIdentifier(rawValue: 1)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) async {
        log.withLock { $0.append("end") }
    }
}
