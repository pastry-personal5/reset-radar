import Foundation
import Testing

@testable import ResetRadarApplication

@Suite struct ComplicationBudgetPolicyTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func allows(
        enabled: Bool = true, agesInSeconds: [TimeInterval], changed: Bool = true
    ) -> Bool {
        let transfers = agesInSeconds.map { Self.now.addingTimeInterval(-$0) }
        return ComplicationBudgetPolicy.allows(
            state: ComplicationBudgetState(enabled: enabled, transfers: transfers),
            changedSince: changed, now: Self.now)
    }

    @Test func thirtyMinutesApartIsTheEdge() {
        #expect(!allows(agesInSeconds: [1_799]))
        #expect(allows(agesInSeconds: [1_800]))
    }

    @Test func aFirstTransferIsAllowed() {
        #expect(allows(agesInSeconds: []))
    }

    @Test func nothingChangedDenies() {
        #expect(!allows(agesInSeconds: [5_000], changed: false))
    }

    @Test func disabledDenies() {
        #expect(!allows(enabled: false, agesInSeconds: []))
    }

    @Test func theFortyEighthIsTheLastOfARolling24Hours() {
        let spread = (0..<47).map { 1_800 + TimeInterval($0) * 1_800 }
        #expect(allows(agesInSeconds: spread))
        let full = (0..<48).map { 1_800 + TimeInterval($0) * 1_700 }
        #expect(!allows(agesInSeconds: full))
    }

    @Test func theWindowRollsWhenTheOldestTransferIsADayOld() {
        let recent = (0..<47).map { 1_800 + TimeInterval($0) * 600 }
        #expect(!allows(agesInSeconds: recent + [86_399]))
        #expect(allows(agesInSeconds: recent + [86_400]))
    }
}
