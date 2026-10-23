import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct IngestRelaySnapshotTests {
    let rig = ReaderRig()

    // MARK: triggers

    @Test(arguments: FetchTrigger.allCases)
    func everyTriggerConsultsTheRefreshPolicy(trigger: FetchTrigger) async {
        rig.store.seed { $0.lastAttemptAt = epoch.addingTimeInterval(-5) }
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let outcome = await rig.makeIngest().run(trigger: trigger, inAppProcess: true)
        if trigger == .manual {
            #expect(outcome == .committed)
        } else {
            #expect(outcome == .skipped)
            #expect(rig.relay.calls.isEmpty)
        }
    }

    @Test func awaitingActivationSuppressesEveryTrigger() async {
        rig.store.seed { $0.awaitingActivation = true }
        for trigger in FetchTrigger.allCases {
            #expect(await rig.makeIngest().run(trigger: trigger, inAppProcess: true) == .skipped)
        }
        #expect(rig.relay.calls.isEmpty)
    }

    // MARK: claims across two instances

    @Test func aLateResultFromAnExpiredClaimIsRejected() async {
        let first = rig.makeIngest()
        let second = rig.makeIngest()
        rig.relay.queueGet(rig.envelope(sequence: 5), rig.envelope(sequence: 6))
        rig.relay.holdNext(.getSnapshot)
        let late = Task { await first.run(trigger: .manual, inAppProcess: true) }
        await rig.relay.waitForCalls(.getSnapshot)
        #expect(await second.run(trigger: .manual, inAppProcess: true) == .inProgress)
        rig.clock.advance(by: ReaderClaims.leaseDuration)
        #expect(await second.run(trigger: .manual, inAppProcess: true) == .committed)
        let committed = rig.store.state
        rig.relay.release(.getSnapshot)
        #expect(await late.value == .skipped)
        #expect(rig.store.state.snapshot == committed.snapshot)
        #expect(rig.store.state.etag == committed.etag)
        #expect(rig.store.state.transportStatus == committed.transportStatus)
        #expect(rig.store.state.committedSequence == 5)
    }

    @Test func aLeaseOneSecondFromExpiryIsStillHeld() async {
        let claims = rig.claims()
        guard case .claimed = try? await claims.claim(trigger: .manual) else {
            Issue.record("expected a claim")
            return
        }
        rig.clock.advance(by: ReaderClaims.leaseDuration - 1)
        #expect((try? await claims.claim(trigger: .manual)) == .inProgress)
        rig.clock.advance(by: 1)
        guard case .claimed = try? await claims.claim(trigger: .manual) else {
            Issue.record("expected a new claim")
            return
        }
    }

    // MARK: ETag

    @Test func theStoredETagIsSentOnlyWithAMatchingValidatedSnapshot() async {
        rig.relay.queueGet(rig.envelope(sequence: 5, etag: "\"five\""))
        _ = await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
        rig.relay.queueGet(.notModified)
        #expect(await rig.makeIngest().run(trigger: .manual, inAppProcess: true) == .unchanged)
        #expect(
            rig.relay.calls(.getSnapshot) == [
                .getSnapshot(etag: nil), .getSnapshot(etag: "\"five\""),
            ])
    }

    @Test func anETagWithoutACommittedSnapshotIsNotSentAndAnUnexpected304ReadsOnceMore() async {
        rig.store.seed { $0.etag = "\"stale\"" }
        rig.relay.queueGet(.notModified, rig.envelope(sequence: 5))
        #expect(await rig.makeIngest().run(trigger: .manual, inAppProcess: true) == .committed)
        #expect(
            rig.relay.calls(.getSnapshot) == [
                .getSnapshot(etag: nil), .getSnapshot(etag: nil),
            ])
        #expect(rig.store.state.etag == "\"e5\"")
    }

    @Test func aSecondUnexpected304StopsWithAnInvalidSnapshot() async {
        rig.store.seed { $0.etag = "\"stale\"" }
        rig.relay.queueGet(.notModified, .notModified)
        #expect(
            await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
                == .failed(.invalidSnapshot))
        #expect(rig.store.state.etag == nil)
        #expect(rig.store.state.snapshot == nil)
    }

    // MARK: validation

    @Test func aRejectedEnvelopeKeepsTheCommittedSnapshotAndTheETag() async {
        rig.relay.queueGet(rig.envelope(sequence: 5, etag: "\"good\""))
        _ = await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
        let kept = rig.store.state.snapshot
        let rejected = [
            rig.envelope(sequence: 9, publisherID: otherPublisher, etag: "\"wrong\""),
            rig.envelope(sequence: 9, snapshotPublisher: otherPublisher, etag: "\"mixed\""),
        ]
        for bad in rejected {
            rig.relay.queueGet(bad)
            let outcome = await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
            #expect(outcome == .failed(.invalidSnapshot))
            #expect(rig.store.state.snapshot == kept)
            #expect(rig.store.state.etag == "\"good\"")
        }
    }

    @Test func theFloorIsInclusive() async {
        let belowFloor = ReaderRig(floor: 3)
        belowFloor.relay.queueGet(belowFloor.envelope(sequence: 2))
        let low = await belowFloor.makeIngest().run(trigger: .manual, inAppProcess: true)
        #expect(low == .failed(.invalidSnapshot))
        #expect(belowFloor.store.state.snapshot == nil && belowFloor.store.state.etag == nil)
        let atFloor = ReaderRig(floor: 3)
        atFloor.relay.queueGet(atFloor.envelope(sequence: 3))
        #expect(await atFloor.makeIngest().run(trigger: .manual, inAppProcess: true) == .committed)
    }

    @Test func aWrongKeyIsAnInvalidSnapshot() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        rig.secrets.seed(.contentKey, SecretValue(bytes(32, 0x99)))
        #expect(
            await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
                == .failed(.invalidSnapshot))
    }

    @Test func lockedSecretsReportSecretsUnavailableAndFreeTheLease() async {
        rig.secrets.setReadFailure(.interactionRequired)
        #expect(
            await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
                == .failed(.secretsUnavailable))
        #expect(rig.relay.calls.isEmpty)
        #expect(rig.store.state.lease == nil)
        #expect(rig.store.state.transportStatus == .secretsUnavailable)
    }

    // MARK: commit rule

    @Test func onlyAGreaterSequenceCommits() async {
        rig.relay.queueGet(
            rig.envelope(sequence: 5), rig.envelope(sequence: 5), rig.envelope(sequence: 6))
        let use = rig.makeIngest()
        #expect(await use.run(trigger: .manual, inAppProcess: true) == .committed)
        #expect(await use.run(trigger: .manual, inAppProcess: true) == .unchanged)
        #expect(rig.store.state.committedSequence == 5)
        #expect(await use.run(trigger: .manual, inAppProcess: true) == .committed)
        #expect(rig.store.state.committedSequence == 6)
        #expect(rig.store.state.etag == "\"e6\"")
    }

    // MARK: failures

    @Test func transientFailuresLengthenTheBackoffUpToTheCap() async {
        let use = rig.makeIngest()
        rig.random.queueUnits([], then: 1)
        var delays: [TimeInterval] = []
        for _ in 0..<8 {
            rig.relay.queueGet(.offline)
            #expect(await use.run(trigger: .manual, inAppProcess: true) == .failed(.offline))
            let until = rig.store.state.backoffUntil ?? epoch
            delays.append(until.timeIntervalSince(rig.clock.now))
        }
        #expect(delays == [30, 60, 120, 240, 480, 900, 900, 900])
        rig.relay.queueGet(rig.envelope(sequence: 5))
        #expect(await use.run(trigger: .manual, inAppProcess: true) == .committed)
        #expect(rig.store.state.failureCount == 0 && rig.store.state.backoffUntil == nil)
    }

    @Test func terminalFailuresStopAutomaticFetchesWithoutBackoff() async {
        let use = rig.makeIngest()
        rig.relay.queueGet(.unauthorized)
        #expect(
            await use.run(trigger: .manual, inAppProcess: true) == .failed(.authorizationRequired))
        #expect(rig.store.state.backoffUntil == nil && rig.store.state.failureCount == 0)
        rig.clock.advance(by: 1_000)
        #expect(await use.run(trigger: .backgroundTask, inAppProcess: true) == .skipped)
        rig.relay.queueGet(.unsupportedVersion)
        #expect(await use.run(trigger: .manual, inAppProcess: true) == .failed(.incompatible))
        rig.clock.advance(by: 1_000)
        #expect(await use.run(trigger: .foregroundActivation, inAppProcess: true) == .skipped)
    }

    @Test func aBackoffBlocksAutomaticTriggersUntilItEnds() async {
        let use = rig.makeIngest()
        rig.random.queueUnits([], then: 1)
        rig.relay.queueGet(.offline)
        _ = await use.run(trigger: .manual, inAppProcess: true)
        rig.clock.advance(by: 29)
        #expect(await use.run(trigger: .foregroundActivation, inAppProcess: true) == .skipped)
        rig.clock.advance(by: 1)
        rig.relay.queueGet(rig.envelope(sequence: 5))
        #expect(await use.run(trigger: .foregroundActivation, inAppProcess: true) == .committed)
    }

    // MARK: relay outcomes

    struct OutcomeRow: Sendable {
        let relay: RelayOutcome
        let outcome: IngestOutcome
        let status: TransportStatus
    }

    static let rows: [OutcomeRow] = [
        OutcomeRow(relay: .notModified, outcome: .unchanged, status: .current),
        OutcomeRow(
            relay: .awaitingFirstPublish, outcome: .failed(.awaitingFirstPublish),
            status: .awaitingFirstPublish),
        OutcomeRow(
            relay: .badRequest, outcome: .failed(.invalidSnapshot), status: .invalidSnapshot),
        OutcomeRow(
            relay: .unauthorized, outcome: .failed(.authorizationRequired),
            status: .authorizationRequired),
        OutcomeRow(relay: .payloadTooLarge, outcome: .failed(.incompatible), status: .incompatible),
        OutcomeRow(
            relay: .unsupportedVersion, outcome: .failed(.incompatible), status: .incompatible),
        OutcomeRow(relay: .quotaLimited, outcome: .failed(.quotaLimited), status: .quotaLimited),
        OutcomeRow(
            relay: .protocolFailure, outcome: .failed(.invalidSnapshot), status: .invalidSnapshot),
        OutcomeRow(relay: .offline, outcome: .failed(.offline), status: .offline),
        OutcomeRow(
            relay: .accepted(sequence: nil), outcome: .failed(.invalidSnapshot),
            status: .invalidSnapshot),
    ]

    @Test(arguments: rows.indices) func everyRelayOutcomeMapsThroughTheTable(index: Int) async {
        let row = Self.rows[index]
        let fresh = ReaderRig()
        fresh.store.seed { state in
            state.snapshot = snapshot(windows: [window()])
            state.etag = "\"e1\""
            state.committedSequence = 1
        }
        fresh.relay.queueGet(row.relay)
        let outcome = await fresh.makeIngest().run(trigger: .manual, inAppProcess: true)
        #expect(outcome == row.outcome)
        #expect(fresh.store.state.transportStatus == row.status)
        #expect(fresh.store.state.snapshot != nil)
        #expect(fresh.store.state.lease == nil)
    }

    // MARK: after commit

    @Test func anAppCommitRunsTheWholePipelineInOrderAndAnIPadSkipsTheWatch() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        _ = await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
        #expect(rig.log.all == ["notifications", "liveActivities", "watch"])
        #expect(rig.reloader.widgetReloads == 1)
        let pad = ReaderRig()
        pad.relay.queueGet(pad.envelope(sequence: 5))
        _ = await pad.makeIngest(watch: false).run(trigger: .manual, inAppProcess: true)
        #expect(pad.log.all == ["notifications", "liveActivities"])
    }

    @Test func aWidgetCommitReconcilesNotificationsOnlyAndLeavesTheFlagForTheApp() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let outcome = await rig.makeIngest().run(trigger: .widgetReload, inAppProcess: false)
        #expect(outcome == .committed)
        #expect(rig.log.all == ["notifications"])
        #expect(rig.reloader.widgetReloads == 0)
        #expect(rig.store.state.needsAppReconcile)
        await rig.pipeline().reconcilePending()
        #expect(rig.log.all == ["notifications", "notifications", "liveActivities", "watch"])
        #expect(!rig.store.state.needsAppReconcile)
        await rig.pipeline().reconcilePending()
        #expect(rig.log.all.count == 4)
    }

    @Test func aStatusChangeWithoutACommitStillReloadsWidgetsAndTheWatch() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        _ = await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
        let before = rig.log.all.count
        rig.relay.queueGet(.offline)
        _ = await rig.makeIngest().run(trigger: .manual, inAppProcess: true)
        #expect(rig.log.all.count == before + 1)
        #expect(rig.log.all.last == "watch")
        #expect(rig.reloader.widgetReloads == 2)
    }
}
