import Testing

@testable import ResetRadarApplication

@Suite struct BackoffPolicyTests {
    static let ceilings: [Double] = [30, 60, 120, 240, 480, 900, 900, 900]

    @Test(arguments: 1...8) func fullJitterBetweenZeroAndTheCeiling(failures: Int) {
        let ceiling = Self.ceilings[failures - 1]
        #expect(BackoffPolicy.delay(afterFailures: failures, randomUnit: 0) == 0)
        #expect(BackoffPolicy.delay(afterFailures: failures, randomUnit: 1) == ceiling)
        #expect(BackoffPolicy.delay(afterFailures: failures, randomUnit: 0.5) == ceiling / 2)
    }

    @Test func theCapIsReachedAtTheSixthFailureAndHeldForever() {
        #expect(BackoffPolicy.delay(afterFailures: 5, randomUnit: 1) == 480)
        #expect(BackoffPolicy.delay(afterFailures: 6, randomUnit: 1) == 900)
        for failures in 7...26 {
            #expect(BackoffPolicy.delay(afterFailures: failures, randomUnit: 1) == 900)
        }
        #expect(BackoffPolicy.delay(afterFailures: Int.max, randomUnit: 1) == 900)
    }

    @Test func successResetsToZero() {
        #expect(BackoffPolicy.delay(afterFailures: 0, randomUnit: 1) == 0)
        #expect(BackoffPolicy.delay(afterFailures: -3, randomUnit: 1) == 0)
    }

    @Test func randomUnitOutsideTheRangeIsClamped() {
        #expect(BackoffPolicy.delay(afterFailures: 1, randomUnit: -4) == 0)
        #expect(BackoffPolicy.delay(afterFailures: 1, randomUnit: 7) == 30)
        #expect(BackoffPolicy.delay(afterFailures: 1, randomUnit: .nan) == 0)
    }
}
