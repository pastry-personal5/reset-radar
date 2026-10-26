import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarUI

@Suite struct SetupStepTests {
    let reporting = [source(codexA)]

    func derive(
        _ pairing: PairingStatusReadModel?, transport: TransportStatus = .current,
        visible: Bool = true, sources: [AccountSource]? = nil
    ) -> ReaderSetupStep? {
        ReaderSetupStep.derive(
            pairing: pairing, transport: transport, hasVisibleSnapshot: visible,
            sources: sources ?? reporting)
    }

    @Test func pairingStatesOutrankDeliveryAndNeverReadTheEmptyListAsNoAccounts() {
        #expect(derive(nil) == .storageUnavailable)
        #expect(derive(pairingStatus(.paired, cleanupPending: true)) == .cleanupPending)
        #expect(derive(pairingStatus(.notPaired), visible: false, sources: []) == .pairMac)
        #expect(
            derive(pairingStatus(.awaitingActivation), visible: false, sources: [])
                == .confirmingPairing)
        #expect(
            derive(
                pairingStatus(.paired), transport: .awaitingFirstPublish, visible: false,
                sources: [])
                == .waitingForMacData)
    }

    @Test func theArchitecturePriorityOrdersEveryLaterBlocker() {
        let paired = pairingStatus(.paired)
        let signedOut = [source(codexA, state: .signedOut), source(claude, state: .incompatible)]
        #expect(
            derive(paired, transport: .secretsUnavailable, sources: signedOut)
                == .secretsUnavailable)
        #expect(
            derive(paired, transport: .authorizationRequired, sources: signedOut)
                == .authorizationRequired)
        #expect(derive(paired, sources: []) == .sourceNotSetUp)
        #expect(
            derive(paired, transport: .incompatible, sources: signedOut) == .sourceSignedOut(.codex)
        )
        #expect(derive(paired, sources: [source(claude, state: .incompatible)]) == .incompatible)
        #expect(derive(paired, transport: .offline) == .syncProblem(.offline))
        #expect(derive(paired) == nil)
    }

    @Test func aDeliveryFailureBeforeTheFirstPublicationIsNotWaitingForData() {
        let paired = pairingStatus(.paired)
        #expect(
            derive(paired, transport: .offline, visible: false, sources: [])
                == .syncProblem(.offline))
        #expect(
            derive(paired, transport: .incompatible, visible: false, sources: []) == .incompatible)
    }

    @Test func onlyPairingBlockersOpenPairingAndEveryStepHasCopy() {
        let steps: [ReaderSetupStep] = [
            .storageUnavailable, .cleanupPending, .pairMac, .confirmingPairing, .secretsUnavailable,
            .authorizationRequired, .waitingForMacData, .sourceNotSetUp, .sourceSignedOut(.codex),
            .incompatible, .syncProblem(.offline),
        ]
        #expect(Set(steps.map(\.title)).count == steps.count)
        #expect(steps.allSatisfy { !$0.message.isEmpty && !$0.symbolName.isEmpty })
        #expect(
            steps.filter(\.opensPairing)
                == [.cleanupPending, .pairMac, .confirmingPairing, .authorizationRequired])
        #expect(ReaderSetupStep.waitingForMacData.title == "Waiting for Mac Data")
        #expect(ReaderSetupStep.confirmingPairing.title == "Confirming Pairing")
        #expect(ReaderSetupStep.syncProblem(.offline).title == "Sync Problem")
    }
}

@Suite struct RefreshFeedbackTests {
    func line(
        _ product: ProductID, _ id: AccountID, _ phase: RefreshActivity.Phase,
        scope: RefreshActivity.Scope = .home
    ) -> String? {
        RefreshFeedback.line(
            for: product, accountID: id, in: RefreshActivity(scope: scope, phase: phase))
    }

    @Test func relayContactAndTheAcceptedRequestAreNotMacCompletion() {
        let contacted = line(.codex, codexA, .relayContacted)
        let waiting = line(.codex, codexA, .waitingForMac(deadline: at(45)))
        let done = line(
            .codex, codexA,
            .finished(
                .completed([ManualRefreshAccountResult(accountID: codexA, outcome: .codexRead)])))
        #expect(Set([contacted, waiting, done]).count == 3)
        #expect(waiting?.contains("Waiting") == true)
        #expect(done == "The Collector Mac read this account.")
    }

    @Test func eachCodexAccountReportsItsOwnOutcomeSoAFailureCannotHideASibling() {
        let outcome = MacRefreshOutcome.completed([
            ManualRefreshAccountResult(accountID: codexA, outcome: .codexRead),
            ManualRefreshAccountResult(accountID: codexB, outcome: .sourceUnavailable),
        ])
        #expect(line(.codex, codexA, .finished(outcome)) == "The Collector Mac read this account.")
        #expect(
            line(.codex, codexB, .finished(outcome))
                == "The Collector Mac could not read Codex for this account.")
        #expect(
            line(.codex, accountID(0xC9), .finished(outcome))
                == "The Collector Mac returned no result for this account.")
    }

    @Test func claudeCodeReportsTheOrdinaryReadWithoutClaimingAForcedReading() {
        let read = line(.claudeCode, claude, .finished(.notRequested), scope: .account(claude))
        #expect(read?.contains("Relay read completed") == true)
        #expect(read?.contains("cannot request") == true)
        let homeTimeout = line(.claudeCode, claude, .finished(.timedOut))
        #expect(homeTimeout == read)
        #expect(
            line(.claudeCode, claude, .finished(.relayUnavailable))
                == "The relay could not be reached. The last valid reading stays visible.")
    }

    @Test func unfinishedOrUnmatchedWaitsKeepTheLastValidReading() {
        for outcome in [MacRefreshOutcome.timedOut, .macAsleepOrPending, .relayUnavailable] {
            #expect(line(.codex, codexA, .finished(outcome))?.contains("stays visible") == true)
        }
        #expect(line(.codex, codexA, .cancelled)?.contains("left the foreground") == true)
        #expect(
            line(.codex, codexA, .finished(.rateLimited))
                == "Refresh is rate limited. Try again shortly.")
    }

    @Test func anAccountRefreshConcernsOnlyThatAccount() {
        let activity = RefreshActivity(scope: .account(codexA), phase: .readingRelay)
        #expect(activity.concerns(codexA))
        #expect(!activity.concerns(codexB))
        #expect(RefreshFeedback.line(for: .codex, accountID: codexB, in: activity) == nil)
        #expect(activity.isRunning)
        #expect(!RefreshActivity(scope: .home, phase: .cancelled).isRunning)
    }
}

@Suite struct PairingSyncTextTests {
    @Test func watchErasureIsPendingUntilAReceiptAndThenNamesOnlyTheRespondingWatch() {
        let pending = PairingSyncText.watchErasure(.pending(revision: 2))
        #expect(pending.contains("pending"))
        #expect(pending.contains("may remain"))
        let confirmed = PairingSyncText.watchErasure(.confirmed(revision: 2, confirmedAt: epoch))
        #expect(confirmed.contains("confirmed for the responding Watch cache"))
        #expect(confirmed.contains("does not cover another paired Watch"))
    }

    @Test func pairingAndForgetAvailabilityFollowTheReaderState() {
        #expect(PairingSyncText.acceptsPairingPackage(pairingStatus(.notPaired)))
        #expect(
            !PairingSyncText.acceptsPairingPackage(pairingStatus(.notPaired, cleanupPending: true)))
        #expect(!PairingSyncText.acceptsPairingPackage(pairingStatus(.paired)))
        #expect(!PairingSyncText.acceptsPairingPackage(nil))
        #expect(!PairingSyncText.offersForgetMac(pairingStatus(.notPaired)))
        #expect(PairingSyncText.offersForgetMac(pairingStatus(.notPaired, cleanupPending: true)))
        #expect(PairingSyncText.offersForgetMac(pairingStatus(.awaitingActivation)))
        #expect(PairingSyncText.status(pairingStatus(.awaitingActivation)) == "Confirming Pairing")
        #expect(
            PairingSyncText.status(pairingStatus(.paired, cleanupPending: true))
                == "Local Cleanup Pending")
    }

    @Test func pairingFailuresExplainWhatWasAndWasNotSaved() {
        let errors: [PairingError] = [
            .codec(.expired), .codec(.malformed), .codec(.endpointNotAllowed), .forgetRequired,
            .cleanupPending, .secretsUnavailable, .storageFailed, .preflightFailed(.offline),
            .confirmationRequired, .nothingToResume, .codec(.unsupportedVersion),
        ]
        #expect(Set(errors.map(PairingSyncText.pairingError)).count == errors.count)
        #expect(
            PairingSyncText.pairingError(.preflightFailed(.offline)).contains("Nothing was saved"))
        #expect(PairingSyncText.pairingError(.storageFailed).contains("Nothing was activated"))
        #expect(PairingSyncText.pairingOutcome(.activationRejected).contains("new Pairing Package"))
        #expect(PairingSyncText.forgetOutcome(.complete).contains("revoke it there"))
    }
}

@Suite struct AccountSelectionTests {
    let ordered = [codexA, codexB, claude]

    @Test func aListedSelectionIsKeptOrRestoredAndOtherwiseTheFirstAccountIsChosen() {
        #expect(
            AccountSelection.resolve(current: codexB, stored: claude, ordered: ordered) == codexB)
        #expect(AccountSelection.resolve(current: nil, stored: claude, ordered: ordered) == claude)
        let removed = accountID(0xEE)
        #expect(
            AccountSelection.resolve(current: removed, stored: removed, ordered: ordered) == codexA)
        #expect(AccountSelection.resolve(current: codexA, stored: codexA, ordered: []) == nil)
    }

    @Test func aRenamedAliasKeepsTheSameAccountSelected() async throws {
        let alias = try AccountAlias(validating: "Zed")
        let before = await loadHome(standardSnapshot()).accounts.map(\.account.id)
        let renamed = snapshot(
            accounts: [
                AccountMetadata(id: codexA, product: .codex, number: 1, alias: alias),
                AccountMetadata(id: claude, product: .claudeCode, number: 3),
            ],
            sources: standardSnapshot().sources, windows: standardSnapshot().windows)
        let after = await loadHome(renamed).accounts.map(\.account.id)
        #expect(before != after)
        #expect(AccountSelection.resolve(current: codexA, stored: nil, ordered: after) == codexA)
    }
}
