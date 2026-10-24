import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

@Suite("Codex app-server source scheduling")
struct CodexAppServerSourceSchedulingTests: CodexSourceTestHarness {
    @Test("reset plus thirty seconds starts a new read")
    func resetDeadline() async throws {
        let rig = makeRig()
        try await rig.source.start()
        await rig.clock.waitForSleepers()
        rig.clock.advance(by: 130)
        await waitForRateLimitReads(2, session: rig.session)
        #expect(rig.session.rateLimitReads == 2)
        await rig.source.stop()
    }

    @Test("notification refetch is immediate, then limited to once per minute")
    func notifications() async throws {
        let rig = makeRig()
        try await rig.source.start()
        rig.session.notify(generation: 1)
        await waitForRateLimitReads(2, session: rig.session)
        #expect(rig.session.rateLimitReads == 2)

        rig.clock.advance(by: 1)
        rig.session.notify(generation: 1)
        await rig.clock.waitForSleepers()
        rig.clock.advance(by: 59)
        await waitForRateLimitReads(3, session: rig.session)
        #expect(rig.session.rateLimitReads == 3)
        await rig.source.stop()
    }

    @Test("notification before rate-limit request send is satisfied by that request")
    func notificationBeforeRequestSend() async throws {
        let rig = makeRig()
        try await rig.source.start()
        rig.session.holdStatusReads()
        let read = Task { await rig.source.refresh() }
        await waitForStatusReads(2, session: rig.session)
        rig.session.notify(generation: 1)
        rig.session.releaseStatusRead()
        _ = await read.value
        for _ in 0..<100 { await Task.yield() }
        #expect(rig.session.rateLimitReads == 2)
        await rig.source.stop()
    }

    @Test("notification after request send leaves one trailing refetch")
    func notificationAfterRequestSend() async throws {
        let rig = makeRig()
        try await rig.source.start()
        rig.session.holdRateLimitReads()
        let read = Task { await rig.source.refresh() }
        await waitForRateLimitReads(2, session: rig.session)
        rig.session.notify(generation: 1)
        rig.session.releaseRateLimitRead()
        _ = await read.value
        await waitForRateLimitReads(3, session: rig.session)
        #expect(rig.session.rateLimitReads == 3)
        await rig.source.stop()
    }

    @Test("notification while the response is being scoped leaves one trailing refetch")
    func notificationDuringScoping() async throws {
        let scoper = GatedAccountScoper()
        let rig = makeRig(scoper: scoper)
        try await rig.source.start()
        scoper.hold()
        let read = Task { await rig.source.refresh() }
        for _ in 0..<5_000 where scoper.entered < 2 { await Task.yield() }
        #expect(scoper.entered == 2)
        rig.session.notify(generation: 1)
        for _ in 0..<200 { await Task.yield() }
        scoper.release()
        _ = await read.value
        await waitForRateLimitReads(3, session: rig.session)
        #expect(rig.session.rateLimitReads == 3)
        await rig.source.stop()
    }

    @Test("a blocked source restarts when its executable becomes inspectable or changes")
    func blockedSourceRestartsOnExecutableChange() async throws {
        let inspector = ScriptedCodexRuntimeInspector([
            .failure(.incompatible), .success(runtimeMetadata(version: "codex 0.165.0")),
        ])
        let rig = makeRig(runtimeInspector: inspector)
        try await rig.source.start()
        #expect(rig.session.rateLimitReads == 0)
        let receipt = await rig.source.refresh()
        #expect(receipt.performedSuccessfully)
        #expect(rig.session.rateLimitReads == 1)
        await rig.source.stop()
    }

    @Test("configuration change replaces the session generation before reading")
    func configurationChange() async throws {
        let rig = makeRig()
        try await rig.source.start()
        await rig.source.configurationChanged()
        await waitForRateLimitReads(2, session: rig.session)
        #expect(rig.session.stops == 1)
        #expect(rig.session.initializeParameters.count == 2)
        await rig.source.stop()
    }

    @Test("runtime executable metadata drift replaces the child and source version")
    func runtimeMetadataDrift() async throws {
        let inspector = FakeCodexRuntimeInspector([
            runtimeMetadata(version: "codex 0.164.0"),
            runtimeMetadata(version: "codex 0.165.0"),
        ])
        let rig = makeRig(runtimeInspector: inspector)
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        let first = try #require(await updates.next())
        _ = await rig.source.refresh()
        let second = try #require(await updates.next())
        #expect(first.source.version == "codex 0.164.0")
        #expect(second.source.version == "codex 0.165.0")
        #expect(rig.session.stops == 1)
        #expect(rig.session.initializeParameters.count == 2)
        await rig.source.stop()
    }

    @Test("a late response after stop cannot publish")
    func staleResponseAfterStop() async throws {
        let rig = makeRig()
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        _ = try #require(await updates.next())
        rig.session.holdRateLimitReads()
        let read = Task { await rig.source.refresh() }
        await waitForRateLimitReads(2, session: rig.session)
        await rig.source.stop()
        rig.session.releaseRateLimitRead()
        #expect(await read.value == .unavailable(sourceState: .unavailable))
        #expect(await updates.next() == nil)
    }

    @Test("stop is idempotent, finishes updates, and makes start terminal")
    func terminalStop() async throws {
        let rig = makeRig()
        try await rig.source.start()
        await rig.source.stop()
        await rig.source.stop()
        #expect(rig.session.stops == 1)
        await #expect(throws: CodexAppServerSourceError.stopped) {
            try await rig.source.start()
        }
    }
}
