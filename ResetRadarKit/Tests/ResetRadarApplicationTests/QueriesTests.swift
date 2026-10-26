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

    func rings(_ model: HomeReadModel) -> [AccountRingSummary] {
        model.accounts.flatMap(\.standardWindows)
    }

    @Test func accountRowsContainTwoStandardWindowsInDisplayOrder() async {
        let model = await home().load()
        #expect(model.accounts.map(\.account.id) == [codexAccountID, claudeAccountID])
        #expect(
            rings(model).map(\.accountWindow) == [
                codexFiveHour, codexWeekly, claudeFiveHour, claudeWeekly,
            ])
        #expect(rings(model).map(\.usedPercent) == [20, 30, 40, 50])
        #expect(rings(model).allSatisfy { $0.presentation == .current })
    }

    @Test func accountDisplayOrderUsesLocalizedNaturalLabels() throws {
        let team10 = AccountMetadata(
            id: codexAccountID, product: .codex, number: 10,
            alias: try AccountAlias(validating: "Team 10"))
        let team2 = AccountMetadata(
            id: otherCodexAccountID, product: .codex, number: 2,
            alias: try AccountAlias(validating: "Team 2"))
        #expect(
            AccountDisplayOrder.sorted([team10, team2]).map(\.id)
                == [otherCodexAccountID, codexAccountID])
    }

    @Test func aMissingSnapshotDoesNotFabricateAccountRows() async {
        try? await store.clear()
        let model = await home().load()
        #expect(model.accounts.isEmpty)
        #expect(model.nextChange == nil)
    }

    @Test func theNextChangeIsTheEarliestCellChangeAndReloadingThereChangesACell() async {
        let first = await home().load()
        let earliest = rings(first).compactMap(\.nextChange).min()
        #expect(first.nextChange == earliest)
        guard let next = first.nextChange else {
            Issue.record("expected a next change")
            return
        }
        clock.set(next)
        let second = await home().load()
        #expect(rings(second).map(\.presentation) != rings(first).map(\.presentation))
    }

    @Test func presentationCrossesEachThresholdAtItsInstant() async {
        var states: [PresentationState] = []
        var current = rings(await home().load())[0]
        states.append(current.presentation)
        while let next = current.nextChange {
            clock.set(next)
            current = rings(await home().load())[0]
            states.append(current.presentation)
        }
        #expect(states == [.current, .stale(reason: .observationOld), .resetAwaitingRefresh])
        clock.set(epoch.addingTimeInterval(3_599.999))
        #expect(rings(await home().load())[0].presentation == .stale(reason: .observationOld))
        clock.set(epoch.addingTimeInterval(3_600))
        #expect(rings(await home().load())[0].presentation == .resetAwaitingRefresh)
    }

    @Test func theFiveMinuteSkewEdgeIsCrossedAtItsInstant() async {
        let future = FakeSnapshotStore(snapshot: fullSnapshot(observedAt: at(600)))
        let use = LoadHome(visible: VisibleSnapshot(snapshots: future), clock: clock)
        let before = rings(await use.load())[0]
        #expect(before.presentation == .stale(reason: .observationInFuture))
        #expect(before.nextChange == at(300))
        clock.set(at(300))
        #expect(rings(await use.load())[0].presentation == .current)
    }

    @Test func macLivenessEndsAfterThreeHeartbeatsAndTheObservationStaysStale() async {
        let details = LoadUsageDetails(visible: VisibleSnapshot(snapshots: store), clock: clock)
        clock.set(at(900))
        let live = await details.load()
        #expect(live.macLive == true)
        #expect(live.accounts.flatMap(\.windows).first?.presentation == .current)
        clock.set(at(901))
        let silent = await details.load()
        #expect(silent.macLive == false)
        #expect(
            silent.accounts.first?.windows.first?.presentation
                == .stale(reason: .observationOld))
        #expect(silent.accounts.map(\.account.id) == [codexAccountID, claudeAccountID])
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
        #expect(await hidden.load().accounts.isEmpty)
        reader.seed {
            $0.awaitingActivation = false
            $0.forgetCleanupPending = true
        }
        #expect(await hidden.load().accounts.isEmpty)
        reader.seed { $0.forgetCleanupPending = false }
        #expect(rings(await hidden.load())[0].presentation == .current)
    }

    @Test func lastSyncedIsTheReadersLastSuccessfulReadAndOnlyAccompaniesVisibleUsage() async {
        let reader = FakeReaderStore(installationID: installation)
        reader.seed { state in
            state.pairing = ReaderPairing(
                endpoint: endpoint, publisherID: publisher, readerID: readerA, minimumSequence: 0,
                keyVersion: 1, registrationExpiresAt: epoch)
            state.lastSuccessAt = at(120)
            state.lastCommitAt = at(60)
            state.transportStatus = .offline
        }
        let details = LoadUsageDetails(
            visible: VisibleSnapshot(snapshots: store, reader: reader), clock: clock)
        let visible = await details.load()
        #expect(visible.lastSyncedAt == at(120))
        #expect(visible.transport == .offline)
        #expect(!visible.accounts.isEmpty)
        reader.seed { $0.awaitingActivation = true }
        #expect(await details.load().lastSyncedAt == nil)
        let mac = LoadUsageDetails(visible: VisibleSnapshot(snapshots: store), clock: clock)
        #expect(await mac.load().lastSyncedAt == nil)
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

@Suite struct LoadWindowSelectionTests {
    let clock = FakeAppClock(start: epoch)

    @Test func additionalSelectionsResolveOnlyTheirExactConcreteID() async {
        let additional = window(scope: scopeA, limitID: "extra", minutes: 60, isDefault: false)
        let store = FakeSnapshotStore(snapshot: snapshot(windows: [window(), additional]))
        let query = LoadWindowSelection(
            visible: VisibleSnapshot(snapshots: store), clock: clock)
        let selected = WindowSelection.additional(additional.id)

        guard case .window(_, _, let details) = await query.load(selected) else {
            Issue.record("Expected an exact additional-window match")
            return
        }
        #expect(details.window.id == additional.id)

        try? await store.commitLocal(snapshot(windows: [window()]))
        #expect(await query.load(selected) == .unavailable(selected))
    }
}
