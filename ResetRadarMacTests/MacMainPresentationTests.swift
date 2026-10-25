import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarMac

private actor RefreshRequestRecorder {
    private(set) var requested = [AccountID?]()

    func record(_ accountID: AccountID?) { requested.append(accountID) }
}

@Suite("Mac main presentation")
struct MacMainPresentationTests {
    private func accounts() throws -> [AccountMetadata] {
        let first = try #require(AccountID(data: Data(repeating: 0x31, count: AccountID.byteCount)))
        let second = try #require(
            AccountID(data: Data(repeating: 0x32, count: AccountID.byteCount)))
        return [
            AccountMetadata(id: first, product: .codex, number: 1),
            AccountMetadata(id: second, product: .codex, number: 2),
        ]
    }

    @Test func selectionRestoresTheLastValidAccountAndFallsBackAfterRemoval() throws {
        let name = "MacMainPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let configured = try accounts()

        #expect(MacHomeSelection.restore(from: configured, defaults: defaults) == configured[0].id)
        MacHomeSelection.save(configured[1].id, defaults: defaults)
        #expect(MacHomeSelection.restore(from: configured, defaults: defaults) == configured[1].id)
        #expect(
            MacHomeSelection.restore(from: [configured[0]], defaults: defaults)
                == configured[0].id)
    }

    @MainActor
    @Test func setupBannerAdvancesWithLocalRelayAndReaderState() async throws {
        let configured = try accounts()
        let catalog = FakeAccountCatalogStore(accounts: configured)
        let snapshots = FakeSnapshotStore()
        let publisher = FakePublisherStore()
        let clock = FakeAppClock()
        let publication = PublicationDriver(
            clock: clock, loadSnapshot: { nil },
            publish: { _, _, _ in .paused })
        let model = HomeViewModel(
            catalog: catalog, snapshots: snapshots,
            aliases: UpdateAccountAlias(
                catalogStore: catalog, snapshots: snapshots, clock: clock),
            publication: publication, publisher: publisher)

        await model.load()
        #expect(model.setupStep == .relay)
        publisher.seed { $0.lifecycle = .active }
        await model.load()
        #expect(model.setupStep == .pairing)
        let readerID = try #require(
            ReaderID(data: Data(repeating: 0x41, count: ReaderID.byteCount)))
        publisher.seed {
            $0.devices = [PairedDevice(readerID: readerID, name: "iPhone", pairedAt: clock.now)]
        }
        await model.load()
        #expect(model.setupStep == nil)
    }

    @MainActor
    @Test func detailsRefreshTargetsOnlyTheSelectedAccount() async throws {
        let configured = try accounts()
        let catalog = FakeAccountCatalogStore(accounts: configured)
        let snapshots = FakeSnapshotStore()
        let clock = FakeAppClock()
        let recorder = RefreshRequestRecorder()
        let publication = PublicationDriver(
            clock: clock, loadSnapshot: { nil },
            publish: { _, _, _ in .paused })
        let model = HomeViewModel(
            catalog: catalog, snapshots: snapshots,
            aliases: UpdateAccountAlias(
                catalogStore: catalog, snapshots: snapshots, clock: clock),
            publication: publication,
            refreshSources: { accountID in
                await recorder.record(accountID)
                let second = AccountRefreshResult(
                    accountID: configured[1].id,
                    receipt: ReadReceipt(
                        startedAt: clock.now, finishedAt: clock.now, succeeded: true))
                if accountID != nil { return [second] }
                return [
                    second,
                    AccountRefreshResult(
                        accountID: configured[0].id,
                        receipt: ReadReceipt(
                            startedAt: clock.now, finishedAt: clock.now, succeeded: false)),
                ]
            })
        await model.load()

        await model.refreshAccount(configured[1].id)
        #expect(await recorder.requested == [configured[1].id])
        #expect(model.message == "Refreshed Account #2.")
        await model.refreshAll()
        #expect(await recorder.requested == [configured[1].id, nil])
        #expect(
            model.message
                == "Could not refresh Account #1. Its last reading remains visible.\n"
                + "Refreshed Account #2.")
        #expect(!model.loadFailed)
    }
}
