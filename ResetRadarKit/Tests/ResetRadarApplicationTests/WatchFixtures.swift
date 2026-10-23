import Foundation
import ResetRadarDomain
import ResetRadarTestSupport

@testable import ResetRadarApplication

/// A payload builder for the Watch-side tests.
func watchPayload(
    _ revision: UInt64, installationID: InstallationID = installation, percent: Double = 10,
    cleared: Bool = false
) -> WatchPayload {
    // swiftlint:disable:next force_try
    try! WatchPayload(
        installationID: installationID, deliveryRevision: revision,
        snapshot: cleared ? nil : snapshot(windows: [window(percent: percent)]),
        relaySequence: cleared ? nil : revision, transportStatus: cleared ? .notPaired : .current,
        lastRelayContactAt: nil, lastCommitAt: nil, cleared: cleared)
}

/// An iPhone with a paired Mac, a committed snapshot, and a Watch.
final class WatchForwardRig: @unchecked Sendable {
    let clock = FakeAppClock(start: epoch)
    let store = FakeReaderStore(installationID: installation)
    let preferences = FakePreferenceStore()
    let link = FakeWatchLink()

    init() {
        store.seed { state in
            state.pairing = ReaderPairing(
                endpoint: endpoint, publisherID: publisher, readerID: readerA, minimumSequence: 0,
                keyVersion: 1, registrationExpiresAt: epoch)
            state.committedSequence = 5
            state.transportStatus = .current
            state.lastContactAt = epoch
            state.lastCommitAt = epoch
        }
    }

    func makeForward() -> ForwardToWatch {
        ForwardToWatch(reader: store, preferences: preferences, watch: link, clock: clock)
    }

    func event(percent: Double = 42, results: [ManualRefreshResult] = []) -> CommitEvent {
        CommitEvent(
            snapshot: snapshot(windows: [window(percent: percent)], results: results),
            process: .app)
    }
}
