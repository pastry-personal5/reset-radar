import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

/// A snapshot with all four Home windows; the five-hour windows reset after the given seconds.
func fullSnapshot(
    generatedAt: Date = epoch, observedAt: Date = epoch, fiveHourReset: TimeInterval = 3_600,
    codexScope: AccountScope? = nil, codexState: SourceState = .reporting
) -> UsageSnapshot {
    let windows = [
        window(
            scope: codexScope, minutes: 300, resetsAt: epoch.addingTimeInterval(fiveHourReset),
            percent: 20, observedAt: observedAt),
        window(
            scope: codexScope, limitID: "weekly", minutes: 10_080,
            resetsAt: epoch.addingTimeInterval(500_000), percent: 30, observedAt: observedAt),
        window(
            product: .claudeCode, minutes: 300, resetsAt: epoch.addingTimeInterval(1_800),
            percent: 40, observedAt: observedAt),
        window(
            product: .claudeCode, limitID: "weekly", minutes: 10_080,
            resetsAt: epoch.addingTimeInterval(400_000), percent: 50, observedAt: observedAt),
    ]
    return snapshot(
        windows: windows,
        sources: [source(.codex, state: codexState), source(.claudeCode)], generatedAt: generatedAt)
}

@Suite struct QueriesTests {
    let clock = FakeAppClock(start: epoch)
    let store = FakeSnapshotStore(snapshot: fullSnapshot())

    func home() -> LoadHome {
        LoadHome(visible: VisibleSnapshot(snapshots: store), clock: clock)
    }

    @Test func fourCellsInFixedSlotOrder() async {
        let model = await home().load()
        #expect(model.cells.map(\.slot) == HomeSlot.allCases)
        #expect(model.cells.map(\.usedPercent) == [20, 30, 40, 50])
        #expect(model.cells.allSatisfy { $0.presentation == .current })
    }

    @Test func aMissingSnapshotGivesFourUnavailableCells() async {
        try? await store.clear()
        let model = await home().load()
        #expect(model.cells.count == 4)
        #expect(model.cells.allSatisfy { $0.presentation == .unavailable && $0.usedPercent == nil })
        #expect(model.nextChange == nil)
    }

    @Test func theNextChangeIsTheEarliestCellChangeAndReloadingThereChangesACell() async {
        let first = await home().load()
        let earliest = first.cells.compactMap(\.nextChange).min()
        #expect(first.nextChange == earliest)
        guard let next = first.nextChange else {
            Issue.record("expected a next change")
            return
        }
        clock.set(next)
        let second = await home().load()
        #expect(second.cells.map(\.presentation) != first.cells.map(\.presentation))
    }

    @Test func presentationCrossesEachThresholdAtItsInstant() async {
        var states: [PresentationState] = []
        var current = await home().load().cells[0]
        states.append(current.presentation)
        while let next = current.nextChange {
            clock.set(next)
            current = await home().load().cells[0]
            states.append(current.presentation)
        }
        #expect(states == [.current, .stale(reason: .observationOld), .resetAwaitingRefresh])
        clock.set(epoch.addingTimeInterval(3_599.999))
        #expect(await home().load().cells[0].presentation == .stale(reason: .observationOld))
        clock.set(epoch.addingTimeInterval(3_600))
        #expect(await home().load().cells[0].presentation == .resetAwaitingRefresh)
    }

    @Test func theFiveMinuteSkewEdgeIsCrossedAtItsInstant() async {
        let future = FakeSnapshotStore(snapshot: fullSnapshot(observedAt: at(600)))
        let use = LoadHome(visible: VisibleSnapshot(snapshots: future), clock: clock)
        let before = await use.load().cells[0]
        #expect(before.presentation == .stale(reason: .observationInFuture))
        #expect(before.nextChange == at(300))
        clock.set(at(300))
        #expect(await use.load().cells[0].presentation == .current)
    }

    @Test func macLivenessEndsAfterThreeHeartbeatsAndTheObservationStaysStale() async {
        let details = LoadUsageDetails(visible: VisibleSnapshot(snapshots: store), clock: clock)
        clock.set(at(900))
        let live = await details.load()
        #expect(live.macLive == true)
        #expect(live.products.flatMap(\.windows).first?.presentation == .current)
        clock.set(at(901))
        let silent = await details.load()
        #expect(silent.macLive == false)
        #expect(
            silent.products.first?.windows.first?.presentation == .stale(reason: .observationOld))
        #expect(silent.products.map(\.product) == [.codex, .claudeCode])
        #expect(silent.transport == .current)
    }

    @Test func usageIsHiddenWhileActivationIsPendingOrCleanupIsUnfinished() async {
        let reader = FakeReaderStore(installationID: installation)
        reader.seed { state in
            state.pairing = ReaderPairing(
                endpoint: endpoint, publisherID: publisher, readerID: readerA, minimumSequence: 0,
                keyVersion: 1, registrationExpiresAt: epoch)
            state.awaitingActivation = true
        }
        let hidden = LoadHome(
            visible: VisibleSnapshot(snapshots: store, reader: reader), clock: clock)
        #expect(await hidden.load().cells.allSatisfy { $0.presentation == .unavailable })
        reader.seed {
            $0.awaitingActivation = false
            $0.forgetCleanupPending = true
        }
        #expect(await hidden.load().cells.allSatisfy { $0.presentation == .unavailable })
        reader.seed { $0.forgetCleanupPending = false }
        #expect(await hidden.load().cells[0].presentation == .current)
    }

    @Test func pairingStatusDistinguishesCleanupPendingAndWatchErasure() async {
        let reader = FakeReaderStore(installationID: installation)
        let phone = LoadPairingStatus(reader: reader, hasWatchStage: true)
        let ipad = LoadPairingStatus(reader: reader, hasWatchStage: false)
        #expect(
            await phone.load()
                == PairingStatusReadModel(state: .notPaired, cleanupPending: false, watchErase: nil)
        )
        reader.seed {
            $0.forgetCleanupPending = true
            $0.watchErasePending = WatchErasure(clear: watchPayload(5, cleared: true))
        }
        let pending = await phone.load()
        #expect(pending?.cleanupPending == true && pending?.watchErase == .pending(revision: 5))
        #expect(await ipad.load()?.watchErase == nil)
        reader.seed {
            $0.forgetCleanupPending = false
            $0.watchErasePending = nil
            $0.confirmedWatchErasure = ConfirmedWatchErasure(revision: 5, confirmedAt: at(9))
        }
        let confirmed = await phone.load()
        #expect(confirmed?.cleanupPending == false)
        #expect(confirmed?.watchErase == .confirmed(revision: 5, confirmedAt: at(9)))
        let labels = Mirror(reflecting: confirmed as Any).children.compactMap(\.label)
        #expect(!String(describing: labels).localizedCaseInsensitiveContains("complication"))
    }

    @Test func pairingStatusReportsAwaitingActivation() async {
        let reader = FakeReaderStore(installationID: installation)
        reader.seed { state in
            state.pairing = ReaderPairing(
                endpoint: endpoint, publisherID: publisher, readerID: readerA, minimumSequence: 0,
                keyVersion: 1, registrationExpiresAt: epoch)
            state.awaitingActivation = true
        }
        #expect(
            await LoadPairingStatus(reader: reader, hasWatchStage: true).load()?.state
                == .awaitingActivation)
    }

    @Test func exportingDiagnosticsNeedsConfirmationAndReturnsRedactedEvents() async throws {
        let sink = FakeDiagnosticsSink()
        await sink.record(.secretsUnavailable(at: epoch))
        let use = ExportDiagnostics(diagnostics: sink, clock: clock)
        await #expect(throws: ExportDiagnosticsError.confirmationRequired) {
            try await use.export(confirmed: false)
        }
        let export = try await use.export(confirmed: true)
        #expect(export.events.map(\.category) == [.secretsUnavailable])
        let decoded = try WireCoding.decoder().decode(
            [DiagnosticEvent].self, from: export.encoded())
        #expect(decoded == export.events)
    }
}
