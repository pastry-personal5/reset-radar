import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct ManualRefreshResultTests {
    typealias Refresh = ManualRefreshResult

    func make(_ reader: ReaderID, _ id: UInt8, completedAt: TimeInterval = 0) -> Refresh {
        ManualRefreshResult(
            readerID: reader, requestID: requestID(id), completedAt: at(completedAt),
            outcome: .codexRead)
    }

    @Test func roundTrips() throws {
        let value = make(readerA, 1)
        let data = try WireCoding.encoder().encode(value)
        #expect(try WireCoding.decoder().decode(ManualRefreshResult.self, from: data) == value)
    }

    @Test func retainedExactlyAt120sExpiredAfter() {
        #expect(ManualRefreshResults.retained([make(readerA, 1)], now: at(120)).count == 1)
        #expect(ManualRefreshResults.retained([make(readerA, 1)], now: at(120.001)).isEmpty)
    }

    @Test func fifthPerReaderDropsOldest() {
        let items = (1...5).map { make(readerA, UInt8($0), completedAt: TimeInterval($0)) }
        let kept = ManualRefreshResults.retained(items, now: at(10))
        #expect(kept.map(\.requestID) == (2...5).map { requestID(UInt8($0)) })
    }

    @Test func thirteenthOverallDropsOldest() {
        let readers = (1...4).map { ReaderID(data: bytes(16, UInt8($0)))! }
        let items = (0..<13).map {
            make(readers[$0 % 4], UInt8($0), completedAt: TimeInterval($0))
        }
        let kept = ManualRefreshResults.retained(items, now: at(20))
        #expect(kept.count == 12)
        #expect(!kept.contains { $0.requestID == requestID(0) })
    }

    @Test func otherReaderDoesNotMatch() {
        let items = [make(readerA, 1)]
        #expect(
            ManualRefreshResults.result(
                for: readerB, requestID: requestID(1), in: items, now: at(1)) == nil)
        #expect(
            ManualRefreshResults.result(
                for: readerA, requestID: requestID(1), in: items, now: at(1)) == items[0])
        #expect(
            ManualRefreshResults.result(
                for: readerA, requestID: requestID(2), in: items, now: at(1)) == nil)
    }

    @Test func futureCompletionBeyondSkewIsDropped() {
        #expect(
            ManualRefreshResults.retained([make(readerA, 1, completedAt: 300)], now: at(0)).count
                == 1)
        #expect(
            ManualRefreshResults.retained([make(readerA, 1, completedAt: 300.001)], now: at(0))
                .isEmpty)
    }
}
