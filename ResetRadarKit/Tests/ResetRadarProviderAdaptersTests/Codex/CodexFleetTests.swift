import Foundation
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

@Suite("Codex two-account fleet")
struct CodexFleetTests {
    private let firstID = AccountID(data: Data(repeating: 0x11, count: 16))!
    private let secondID = AccountID(data: Data(repeating: 0x22, count: 16))!
    private let thirdID = AccountID(data: Data(repeating: 0x33, count: 16))!
    private let origin = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("duplicate provider scope always keeps the lower global account number")
    func duplicateScope() async throws {
        let lower = source(accountID: firstID, providerID: "same")
        let higher = source(accountID: secondID, providerID: "same")
        let fleet = try CodexFleet(accounts: [
            CodexFleetAccount(accountID: secondID, accountNumber: 2, source: higher.source),
            CodexFleetAccount(accountID: firstID, accountNumber: 1, source: lower.source),
        ])
        var updates = fleet.updates.makeAsyncIterator()
        await fleet.start()
        let reports = try await nextReports(2, from: &updates)

        #expect(
            reports.contains {
                $0.source.accountID == firstID && $0.source.state == .reporting
            })
        let eviction = try #require(
            reports.first {
                $0.source.accountID == secondID && $0.source.state == .incompatible
            })
        #expect(eviction.clearsWindows)
        #expect(higher.session.stops == 1)
        #expect(
            await fleet.refresh(accountID: secondID)
                == .unavailable(sourceState: .incompatible))
        #expect(await fleet.refresh(accountID: firstID).performedSuccessfully)
        await fleet.stop()
    }

    @Test("different provider scopes refresh concurrently and remain independent")
    func distinctScopes() async throws {
        let first = source(accountID: firstID, providerID: "first")
        let second = source(accountID: secondID, providerID: "second")
        let fleet = try CodexFleet(accounts: [
            CodexFleetAccount(accountID: firstID, accountNumber: 1, source: first.source),
            CodexFleetAccount(accountID: secondID, accountNumber: 2, source: second.source),
        ])
        await fleet.start()
        let results = await fleet.refreshAll()
        #expect(results.count == 2)
        #expect(results.values.allSatisfy { $0.performedSuccessfully })
        #expect(first.session.rateLimitReads == 2)
        #expect(second.session.rateLimitReads == 2)
        await fleet.stop()
    }

    @Test("a duplicate row can become active after a relevant configuration change")
    func duplicateReactivation() async throws {
        let lower = source(accountID: firstID, providerID: "same")
        let higher = source(accountID: secondID, providerID: "same")
        let fleet = try CodexFleet(accounts: [
            CodexFleetAccount(accountID: firstID, accountNumber: 1, source: lower.source),
            CodexFleetAccount(accountID: secondID, accountNumber: 2, source: higher.source),
        ])
        var updates = fleet.updates.makeAsyncIterator()
        await fleet.start()
        _ = try await nextReports(2, from: &updates)

        let receipt = await fleet.configurationChanged(accountID: secondID)
        #expect(receipt.performedSuccessfully)
        var reactivated: SourceSnapshot?
        for _ in 0..<3 where reactivated == nil {
            let report = try #require(await updates.next())
            if report.source.accountID == secondID && report.source.state == .reporting {
                reactivated = report
            }
        }
        #expect(reactivated != nil)
        #expect(higher.session.rateLimitReads == 2)
        #expect(await fleet.refresh(accountID: secondID).performedSuccessfully)
        await fleet.stop()
    }

    @Test("fleet rejects duplicate local identity, duplicate number, and a third account")
    func invalidFleet() {
        let first = source(accountID: firstID, providerID: "first").source
        let second = source(accountID: secondID, providerID: "second").source
        let third = source(accountID: thirdID, providerID: "third").source
        #expect(throws: CodexFleetError.invalidAccounts) {
            try CodexFleet(accounts: [
                CodexFleetAccount(accountID: firstID, accountNumber: 1, source: first),
                CodexFleetAccount(accountID: firstID, accountNumber: 2, source: first),
            ])
        }
        #expect(throws: CodexFleetError.invalidAccounts) {
            try CodexFleet(accounts: [
                CodexFleetAccount(accountID: firstID, accountNumber: 1, source: first),
                CodexFleetAccount(accountID: secondID, accountNumber: 1, source: second),
            ])
        }
        #expect(throws: CodexFleetError.invalidAccounts) {
            try CodexFleet(accounts: [
                CodexFleetAccount(accountID: firstID, accountNumber: 1, source: first),
                CodexFleetAccount(accountID: secondID, accountNumber: 2, source: second),
                CodexFleetAccount(accountID: thirdID, accountNumber: 3, source: third),
            ])
        }
    }

    private func source(
        accountID: AccountID, providerID: String
    ) -> (source: CodexAppServerSource, session: FakeCodexRPCSession) {
        let limits = JSONValue.object([
            "accountId": .string(providerID),
            "rateLimits": .object([
                "limitId": .string("codex"),
                "primary": .object([
                    "usedPercent": .integer(25),
                    "windowDurationMins": .integer(300),
                    "resetsAt": .integer(2_000_000_100),
                ]),
            ]),
        ])
        let session = FakeCodexRPCSession(
            statuses: [.success(FakeCodexRPCSession.authenticated)],
            rateLimits: [.success(limits)])
        let source = CodexAppServerSource(
            accountID: accountID, sourceVersion: "codex 0.164.0",
            factory: FakeCodexRPCSessionFactory(session: session),
            scoper: FakeAccountScoper(), diagnostics: FakeDiagnosticsSink(),
            clock: FakeAppClock(start: origin))
        return (source, session)
    }

    private func nextReports(
        _ count: Int, from iterator: inout AsyncStream<SourceSnapshot>.Iterator
    ) async throws -> [SourceSnapshot] {
        var reports: [SourceSnapshot] = []
        while reports.count < count {
            reports.append(try #require(await iterator.next()))
        }
        return reports
    }
}
