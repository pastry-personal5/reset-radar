import Foundation
import Testing

@testable import ResetRadarMac

private final class ActivationSpy: FirstInstanceActivating, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func activateFirstInstance() { lock.withLock { count += 1 } }
    var activations: Int { lock.withLock { count } }
}

private actor ActivitySpy: ProcessActivityControlling {
    var begins = 0
    var ends = 0

    func begin() -> UUID {
        begins += 1
        return UUID()
    }

    func end(_ token: UUID) { ends += 1 }
}

@Suite("Mac lifecycle drivers")
struct LifecycleDriverTests {
    @Test func secondInstanceActivatesFirstAndReleasePermitsNext() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "collector.lock")
        let activator = ActivationSpy()
        let first = SingleInstanceLock(fileURL: url, activator: activator)
        let second = SingleInstanceLock(fileURL: url, activator: activator)
        #expect(first.acquire())
        #expect(!second.acquire())
        #expect(activator.activations == 1)
        first.release()
        #expect(second.acquire())
        second.release()
    }

    @Test func appNapGuardBalancesAndIsIdempotent() async {
        let activity = ActivitySpy()
        let guardDriver = AppNapGuard(controller: activity)
        await guardDriver.start()
        await guardDriver.start()
        await guardDriver.stop()
        await guardDriver.stop()
        #expect(await activity.begins == 1)
        #expect(await activity.ends == 1)
    }
}
