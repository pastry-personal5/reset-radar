import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport

@testable import ResetRadarStorage

/// A writer that fails every write after the closure ran while `failing` is set, as a crash or a
/// full disk between the temporary write and the rename would.
final class WriteFault: Sendable {
    private struct Injected: Error {}

    private let flag = Locked(false)

    var failing: Bool {
        get { flag.snapshot }
        set { flag.withLock { $0 = newValue } }
    }

    var writer: AtomicFileWriter {
        AtomicFileWriter(
            protection: .ownerOnly,
            beforeRename: { [flag] in
                if flag.snapshot { throw Injected() }
            })
    }
}

func watchPayload(_ revision: UInt64, cleared: Bool = false) -> WatchPayload {
    // swiftlint:disable:next force_try
    try! WatchPayload(
        installationID: installation, deliveryRevision: revision,
        snapshot: cleared ? nil : snapshot(), relaySequence: cleared ? nil : revision,
        transportStatus: cleared ? .notPaired : .current, lastRelayContactAt: nil,
        lastCommitAt: nil, cleared: cleared)
}

let pairing = ReaderPairing(
    endpoint: endpoint, publisherID: publisher, readerID: readerA, minimumSequence: 3,
    keyVersion: 1, registrationExpiresAt: at(100))
