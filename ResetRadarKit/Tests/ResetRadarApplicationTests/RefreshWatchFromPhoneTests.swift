import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct RefreshWatchFromPhoneTests {
    @Test func deadlineRepliesFromCommittedCacheWhileLateIngestContinues() async {
        let rig = ReaderRig()
        let committed = snapshot(windows: [window(percent: 25)])
        rig.store.seed {
            $0.snapshot = committed
            $0.committedSequence = 5
            $0.transportStatus = .current
        }
        rig.relay.queueGet(rig.envelope(sequence: 6, windows: [window(percent: 60)]))
        rig.relay.holdNext(.getSnapshot)
        let forward = ForwardToWatch(
            reader: rig.store, preferences: FakePreferenceStore(), watch: FakeWatchLink(),
            clock: rig.clock)
        let use = RefreshWatchFromPhone(
            ingest: rig.makeIngest(), forward: forward, clock: rig.clock)

        let request = Task { await use.request() }
        await rig.relay.waitForCalls(.getSnapshot)
        await rig.clock.waitForSleepers()
        rig.clock.advance(by: 10)
        let reply = await request.value
        #expect(reply?.snapshot?.windows.first?.observation?.usedPercent == 25)

        rig.relay.release(.getSnapshot)
        for _ in 0..<1_000 {
            if rig.store.state.committedSequence == 6 { break }
            await Task.yield()
        }
        #expect(rig.store.state.snapshot?.windows.first?.observation?.usedPercent == 60)
    }
}
