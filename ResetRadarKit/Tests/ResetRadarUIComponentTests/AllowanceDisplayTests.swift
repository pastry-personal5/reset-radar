import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarUI

@Suite struct AllowanceDisplayTests {
    @Test func aCurrentReadingShowsItsSourcePrecisionAndFillsFromZeroTowardFull() {
        let codex = AllowanceDisplay(state: .current, window: window(codexA, percent: 42))
        #expect(codex.percentText == "42%")
        #expect(codex.fill == 0.42)
        let claudeCode = AllowanceDisplay(
            state: .current,
            window: window(claude, product: .claudeCode, percent: 42.5, fractionDigits: 1),
            product: .claudeCode)
        #expect(claudeCode.percentText == "42%")
        let unreported = AllowanceDisplay(
            state: .current, window: window(codexA, percent: 42.25, fractionDigits: nil))
        #expect(unreported.percentText == "42.25%")
        let full = AllowanceDisplay(state: .current, window: window(codexA, percent: 100))
        #expect(full.fill == 1)
    }

    @Test func staleKeepsTheLastValueWhileWaitingAndUnavailableShowNoneAndNeverZero() {
        let reading = window(codexA, percent: 0)
        let stale = AllowanceDisplay(state: .stale(reason: .observationOld), window: reading)
        #expect(stale.percentText == "0%")
        #expect(stale.statusText == "Stale")
        let waiting = AllowanceDisplay(state: .resetAwaitingRefresh, window: reading)
        #expect(waiting.percentText == nil)
        #expect(waiting.fill == nil)
        #expect(waiting.statusText == "Waiting for Update")
        let unavailable = AllowanceDisplay(state: .unavailable, window: reading)
        #expect(unavailable.percentText == nil)
        #expect(unavailable.fill == nil)
        #expect(unavailable.statusText == "Unavailable")
    }

    @Test func everyStateHasDistinctTextAndSymbol() {
        let states: [PresentationState] = [
            .current, .stale(reason: .retained), .resetAwaitingRefresh, .unavailable,
        ]
        let displays = states.map { AllowanceDisplay(state: $0, window: window(codexA)) }
        #expect(Set(displays.map(\.statusText)).count == states.count)
        #expect(Set(displays.map(\.symbolName)).count == states.count)
    }

    @Test func anAmbiguousOrMissingRingIsUnavailable() async {
        let duplicate = snapshot(
            accounts: [AccountMetadata(id: codexA, product: .codex, number: 1)],
            sources: [source(codexA)],
            windows: [window(codexA, limitID: "a"), window(codexA, limitID: "b")])
        let rings = await loadHome(duplicate).accounts[0].standardWindows
        #expect(
            rings.map { AllowanceDisplay(ring: $0).statusText } == ["Unavailable", "Unavailable"])
        #expect(rings.allSatisfy { AllowanceDisplay(ring: $0).percentText == nil })
    }

    @Test func accessibilityNamesTheAccountProductWindowReadingAndState() {
        let account = AccountMetadata(id: codexA, product: .codex, number: 2)
        let current = AllowanceDisplay(state: .current, window: window(codexA, percent: 42))
        #expect(
            current.accessibilityLabel(account: account, window: "Five-hour")
                == "Account #2, Codex, Five-hour, 42% used, Current")
        let unavailable = AllowanceDisplay(state: .unavailable, window: nil)
        #expect(
            unavailable.accessibilityLabel(account: account, window: "Weekly")
                == "Account #2, Codex, Weekly, No percentage available, Unavailable")
    }

    @Test func explanationsNameTheReasonAndTheSourceState() {
        let reading = window(codexA)
        #expect(AllowanceDisplay(state: .current, window: reading).explanation(source: nil) == nil)
        let signedOut = source(codexA, state: .signedOut)
        let stale = AllowanceDisplay(state: .stale(reason: .sourceNotReporting), window: reading)
        #expect(
            stale.explanation(source: signedOut)
                == "Codex is signed out on the Collector Mac. This is the last valid reading.")
        let incompatible = source(claude, product: .claudeCode, state: .incompatible)
        #expect(
            AllowanceDisplay(state: .unavailable, window: nil).explanation(source: incompatible)
                == "No reading is available. The Claude Code status line is incompatible.")
        #expect(
            AllowanceDisplay(state: .resetAwaitingRefresh, window: reading)
                .explanation(source: nil)?.contains("reset time passed") == true)
    }
}

@Suite struct WindowSectionTests {
    @Test func standardWindowsComeFirstEvenWithoutAReadingThenAdditionalWindows() async {
        let details = await loadDetails(standardSnapshot())
        let codex = WindowSection.ordered(details.accounts.first { $0.account.id == codexA }!)
        #expect(codex.map(\.title) == ["Five-hour", "Weekly", "Code review"])
        #expect(codex.map(\.display.percentText) == ["42%", "7%", "12%"])
        let claudeCode = WindowSection.ordered(details.accounts.first { $0.account.id == claude }!)
        #expect(claudeCode.map(\.title) == ["Five-hour", "Weekly"])
        #expect(claudeCode[0].display.percentText == "33%")
        #expect(claudeCode[1].details == nil)
        #expect(claudeCode[1].display.statusText == "Unavailable")
    }

    @Test func duplicateDefaultWindowsAreNotPresentedAsTheStandardWindow() async {
        let duplicate = snapshot(
            accounts: [AccountMetadata(id: codexA, product: .codex, number: 1)],
            sources: [source(codexA)],
            windows: [
                window(codexA, limitID: "a", label: "Primary A"),
                window(codexA, limitID: "b", label: "Primary B"),
            ])
        let sections = WindowSection.ordered(await loadDetails(duplicate).accounts[0])
        #expect(sections[0].ambiguous)
        #expect(sections[0].display.percentText == nil)
        #expect(sections.map(\.title) == ["Five-hour", "Weekly", "Primary A", "Primary B"])
    }

    @Test func nextResetUsesOnlyUniqueFutureStandardsAndFiveHourWinsATie() async {
        let details = await loadDetails(standardSnapshot())
        let account = details.accounts.first { $0.account.id == codexA }!
        let sections = WindowSection.ordered(account)
        let future = sections.compactMap { $0.details?.window.resetsAt }.min()!
        let selected = NextResetDerivation.derive(
            from: sections, now: future.addingTimeInterval(-1))
        #expect(selected?.date == future)
        #expect(
            NextResetDerivation.derive(from: sections, now: .distantFuture) == nil)
    }
}

@Suite struct PercentageUsedFormatterTests {
    @Test func claudeFloorsWhileCodexRetainsProviderPrecisionAndLegacyRetainsOldFormatting() {
        #expect(
            PercentageUsedFormatter.text(96.9, product: .claudeCode, fractionDigits: 1) == "96%")
        #expect(PercentageUsedFormatter.text(96.9, product: .codex, fractionDigits: 1) == "96.9%")
        #expect(PercentageUsedFormatter.text(96.9, product: nil, fractionDigits: 1) == "96.9%")
    }
}

@Suite struct VocabularyTests {
    @Test func productAndSourceNamesFollowTheUXTerms() {
        #expect(ReaderVocabulary.productName(.codex) == "Codex")
        #expect(ReaderVocabulary.productName(.claudeCode) == "Claude Code")
        #expect(ReaderVocabulary.sourceName(.codexAppServer) == "Codex app-server")
        #expect(ReaderVocabulary.sourceName(.claudeCodeStatusLine) == "Claude Code status line")
    }

    @Test func everyTransportStatusHasDistinctTextAndOnlyFailuresAreSyncProblems() {
        let texts = TransportStatus.allCases.map(ReaderVocabulary.transport)
        #expect(Set(texts).count == TransportStatus.allCases.count)
        #expect(
            TransportStatus.allCases.filter { !ReaderVocabulary.isSyncProblem($0) }
                == [.notPaired, .awaitingFirstPublish, .current])
    }

    @Test func macPublicationDistinguishesUnknownFromSilent() {
        #expect(ReaderVocabulary.macPublication(true) == "Publishing")
        #expect(ReaderVocabulary.macPublication(false) == "Not publishing recently")
        #expect(ReaderVocabulary.macPublication(nil) != ReaderVocabulary.macPublication(false))
    }
}
