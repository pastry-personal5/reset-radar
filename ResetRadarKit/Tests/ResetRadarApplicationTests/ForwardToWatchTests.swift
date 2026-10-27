import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct ForwardToWatchTests {
    let rig = WatchForwardRig()

    @Test func theWatchCopyDropsManualRefreshResults() async throws {
        let result = try ManualRefreshResult(
            readerID: readerB, requestID: requestID(1), completedAt: epoch,
            target: .allCodex,
            accountResults: [
                ManualRefreshAccountResult(accountID: codexAccountID, outcome: .codexRead)
            ])
        await rig.makeForward().send(after: rig.event(results: [result]))
        let sent = rig.link.contexts.first?.snapshot
        #expect(sent != nil && sent?.manualRefreshResults.isEmpty == true)
        #expect(rig.store.state.snapshot == nil)
    }

    @Test func oneRevisionPerDistinctPayloadAndIdenticalPayloadsReuseIt() async {
        let forward = rig.makeForward()
        await forward.send(after: rig.event(percent: 10))
        await forward.send(after: rig.event(percent: 10))
        await forward.send(after: rig.event(percent: 11))
        #expect(rig.link.contexts.map(\.deliveryRevision) == [5 - 4, 1, 2])
        #expect(rig.store.state.watchDeliveryRevision == 2)
        #expect(rig.store.state.hasSentToWatch)
        #expect(rig.store.state.lastWatchPayload?.deliveryRevision == 2)
    }

    @Test func aTransportStatusChangeIsADistinctPayload() async {
        let forward = rig.makeForward()
        await forward.send(after: rig.event())
        rig.store.seed { $0.transportStatus = .offline }
        await forward.send(after: rig.event())
        #expect(rig.link.contexts.map(\.transportStatus) == [.current, .offline])
        #expect(rig.link.contexts.map(\.deliveryRevision) == [1, 2])
    }

    @Test func aLateOldCommitEventSendsTheNewestLockedReaderSnapshot() async {
        let oldEvent = rig.event(percent: 10)
        let newest = rig.event(percent: 88).snapshot
        rig.store.seed { $0.snapshot = newest }
        await rig.makeForward().send(after: oldEvent)
        #expect(rig.link.contexts.first?.snapshot?.windows.first?.observation?.usedPercent == 88)
    }

    @Test func contextAndComplicationTransferCarryTheSameRevision() async {
        await rig.preferences.setComplicationEnabled(true)
        await rig.makeForward().send(after: rig.event())
        #expect(
            rig.link.transfers.map(\.deliveryRevision) == rig.link.contexts.map(\.deliveryRevision))
        #expect(rig.link.transfers.count == 1)
    }

    @Test func aDisabledComplicationReceivesNoTransfer() async {
        await rig.makeForward().send(after: rig.event())
        #expect(rig.link.contexts.count == 1 && rig.link.transfers.isEmpty)
    }

    @Test func exhaustedSystemBudgetNeverSuppressesApplicationContext() async {
        await rig.preferences.setComplicationEnabled(true)
        rig.link.setState(
            WatchLinkState(
                activated: true, paired: true, watchAppInstalled: true,
                complicationEnabled: true, remainingComplicationTransfers: 0))
        await rig.makeForward().send(after: rig.event())
        #expect(rig.link.contexts.count == 1 && rig.link.transfers.isEmpty)
        #expect(rig.store.state.complicationTransfers.isEmpty)
    }

    @Test func transfersNeedAChangeAndThirtyMinutes() async {
        await rig.preferences.setComplicationEnabled(true)
        let forward = rig.makeForward()
        await forward.send(after: rig.event(percent: 10))
        rig.clock.advance(by: 600)
        await forward.send(after: rig.event(percent: 10))  // nothing changed
        await forward.send(after: rig.event(percent: 20))  // changed, but under 30 minutes
        #expect(rig.link.transfers.count == 1)
        rig.clock.advance(by: 1_200)
        await forward.send(after: rig.event(percent: 30))
        #expect(rig.link.transfers.count == 2)
        rig.clock.advance(by: 7_200)
        await forward.send(after: rig.event(percent: 30))  // nothing changed since the last
        #expect(rig.link.transfers.count == 2)
    }

    @Test func the49thTransferOfADayIsDenied() async {
        await rig.preferences.setComplicationEnabled(true)
        rig.store.seed { state in
            state.complicationTransfers = (0..<48).map {
                epoch.addingTimeInterval(-1_900 - Double($0) * 1_700)
            }
        }
        await rig.makeForward().send(after: rig.event())
        #expect(rig.link.contexts.count == 1 && rig.link.transfers.isEmpty)
    }

    @Test func aFailedComplicationTransferSpendsTheAttemptButKeepsTheChangeEligible() async {
        await rig.preferences.setComplicationEnabled(true)
        rig.link.failComplications(true)
        let forward = rig.makeForward()
        #expect(await forward.afterCommitOutcome(rig.event(percent: 20)) == .retryable)
        #expect(rig.store.state.complicationTransfers == [epoch])
        #expect(rig.store.state.lastComplicationValues == nil)

        rig.link.failComplications(false)
        rig.clock.advance(by: ComplicationBudgetPolicy.minimumInterval)
        #expect(await forward.afterCommitOutcome(rig.event(percent: 20)) == .complete)
        #expect(rig.link.transfers.count == 1)
        #expect(rig.store.state.lastComplicationValues != nil)
    }

    @Test func aPendingEraseResendsOnlyTheSavedClear() async {
        await rig.preferences.setComplicationEnabled(true)
        let clear = watchPayload(9, cleared: true)
        rig.store.seed {
            $0.watchErasePending = WatchErasure(clear: clear)
            $0.watchDeliveryRevision = 9
        }
        let forward = rig.makeForward()
        await forward.send(after: rig.event())
        await forward.send(after: rig.event(percent: 77))
        #expect(rig.link.contexts == [clear, clear])
        #expect(rig.link.transfers.isEmpty)
        #expect(rig.store.state.watchDeliveryRevision == 9)
    }

    @Test func sessionActivationReplaysAPendingClearWithoutAUsageSnapshot() async {
        let clear = watchPayload(9, cleared: true)
        rig.store.seed {
            $0.snapshot = nil
            $0.watchErasePending = WatchErasure(clear: clear)
            $0.watchDeliveryRevision = 9
        }
        #expect(await rig.makeForward().reconcileCurrent() == .complete)
        #expect(rig.link.contexts == [clear])
    }

    @Test func aLockedOrUnpairedReaderSendsNothing() async {
        rig.store.seed { $0.forgetCleanupPending = true }
        await rig.makeForward().send(after: rig.event())
        let unpaired = WatchForwardRig()
        unpaired.store.seed { $0.pairing = nil }
        await unpaired.makeForward().send(after: unpaired.event())
        #expect(rig.link.contexts.isEmpty && unpaired.link.contexts.isEmpty)
    }

    @Test func usageNeverReachesTheWatchWhileActivationIsPending() async {
        rig.store.seed { $0.awaitingActivation = true }
        await rig.makeForward().send(after: rig.event())
        #expect(rig.link.contexts.isEmpty && rig.link.transfers.isEmpty)
        #expect(rig.store.state.watchDeliveryRevision == 0)
    }
}
