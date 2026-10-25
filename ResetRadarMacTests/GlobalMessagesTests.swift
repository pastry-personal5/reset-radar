import Foundation
import ResetRadarApplication
import ResetRadarProviderAdapters
import ResetRadarStorage
import Testing

@testable import ResetRadarMac

@Suite("Global messages")
struct GlobalMessagesTests {
    @MainActor
    @Test func keepsNewestMessagesInOrderWithinTheSessionBound() {
        let messages = GlobalMessageCenter()
        messages.post("")
        for index in 0..<205 {
            messages.post("Event \(index)")
        }

        #expect(messages.entries.count == GlobalMessageCenter.maximumEntries)
        #expect(messages.entries.first?.text == "Event 5")
        #expect(messages.entries.last?.text == "Event 204")
        #expect(messages.entries.first?.id == 6)
        #expect(messages.entries.last?.id == 205)
    }

    @MainActor
    @Test func displaysEachTypedPublicationStopReason() {
        let messages = GlobalMessageCenter()
        messages.reportPublication(.blocked(.stopped(.snapshotConflict)))
        messages.reportPublication(.blocked(.stopped(.authorizationRequired)))
        messages.reportPublication(.blocked(.stopped(.payloadRejected)))
        messages.reportPublication(.blocked(.stopped(.incompatible)))
        messages.reportPublication(.blocked(.envelopeTooLarge))
        messages.reportPublication(.blocked(.secretsUnavailable))
        messages.reportPublication(.blocked(.paused))
        messages.reportPublication(.blocked(.backoff(until: Date())))

        #expect(messages.entries.count == 7)
        #expect(messages.entries[0].text.contains("publisher conflict"))
        #expect(messages.entries[1].text.contains("write token"))
        #expect(messages.entries[2].text.contains("payload was rejected"))
        #expect(messages.entries[3].text.contains("protocol is incompatible"))
        #expect(messages.entries[4].text.contains("size limit"))
        #expect(messages.entries[5].text.contains("secrets could not be read"))
        #expect(messages.entries[6].text.contains("publisher state is unavailable"))
        #expect(messages.entries[6].text.contains("Local readings remain on this Mac"))
    }

    @MainActor
    @Test func startupFailureUsesSafeCategoryInsteadOfRawErrorDetails() {
        let bootstrap = MacBootstrap()
        #expect(
            bootstrap.startupFailureReason(ProviderAccountCatalogStoreError.unsafeLocation)
                .contains("unsafe location"))
        let reason = bootstrap.startupFailureReason(StorageError.io(code: 12_345))
        #expect(reason.contains("publisher state"))
        #expect(!reason.contains("12345"))
    }

    @MainActor
    @Test func publicationTimeUpdatesWithoutAddingRoutineMessages() {
        let messages = GlobalMessageCenter()
        let publishedAt = Date(timeIntervalSince1970: 1_800_000_000)
        messages.reportPublication(.blocked(.secretsUnavailable))
        messages.reportPublication(.recovered)
        messages.reportPublication(.published(date: publishedAt))

        #expect(messages.lastPublishedAt == publishedAt)
        #expect(messages.publicationProblem == nil)
        #expect(messages.entries.count == 2)
    }
}
