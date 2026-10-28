import Foundation
import ResetRadarApplication
import ResetRadarDomain

public enum CodexFleetError: Error, Equatable, Sendable {
    case invalidAccounts
}

public struct CodexFleetAccount: Sendable {
    public let accountID: AccountID
    public let accountNumber: Int
    public let source: CodexAppServerSource

    public init(accountID: AccountID, accountNumber: Int, source: CodexAppServerSource) {
        self.accountID = accountID
        self.accountNumber = accountNumber
        self.source = source
    }
}

public actor CodexFleet {
    public nonisolated let updates: AsyncStream<SourceSnapshot>

    private let accounts: [CodexFleetAccount]
    private let updateContinuation: AsyncStream<SourceSnapshot>.Continuation
    private var listenerTasks: [Task<Void, Never>] = []
    private var inactiveAccounts = Set<AccountID>()
    private var providerScopes: [AccountID: AccountScope] = [:]
    private var started = false
    private var stopped = false

    public init(accounts: [CodexFleetAccount]) throws {
        let ids = Set(accounts.map(\.accountID))
        let numbers = Set(accounts.map(\.accountNumber))
        guard ids.count == accounts.count, numbers.count == accounts.count,
            accounts.allSatisfy({ $0.accountNumber > 0 }),
            accounts.allSatisfy({ $0.source.accountID == $0.accountID })
        else { throw CodexFleetError.invalidAccounts }
        let pair = AsyncStream<SourceSnapshot>.makeStream()
        self.accounts = accounts.sorted { $0.accountNumber < $1.accountNumber }
        updates = pair.stream
        updateContinuation = pair.continuation
    }

    deinit {
        for task in listenerTasks { task.cancel() }
        updateContinuation.finish()
    }

    public func start() async {
        guard !started, !stopped else { return }
        started = true
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { try? await account.source.start() }
            }
        }
        await resolveCurrentDuplicateScopes()
        listenForUpdates()
    }

    public func stop() async {
        guard !stopped else { return }
        stopped = true
        for task in listenerTasks { task.cancel() }
        listenerTasks.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { await account.source.stop() }
            }
        }
        updateContinuation.finish()
    }

    public func refresh(accountID: AccountID) async -> ReadReceipt {
        guard !inactiveAccounts.contains(accountID),
            let source = accounts.first(where: { $0.accountID == accountID })?.source
        else { return .unavailable(sourceState: .incompatible) }
        return await source.refresh()
    }

    public func refreshAll() async -> [AccountID: ReadReceipt] {
        await withTaskGroup(of: (AccountID, ReadReceipt).self) { group in
            for account in accounts {
                group.addTask {
                    let receipt = await self.refresh(accountID: account.accountID)
                    return (account.accountID, receipt)
                }
            }
            var results: [AccountID: ReadReceipt] = [:]
            for await (accountID, receipt) in group { results[accountID] = receipt }
            return results
        }
    }

    /// Re-enables one row after its owner-confirmed configuration or executable metadata changes.
    /// A row evicted for a duplicate provider scope is allowed to prove that it is distinct again.
    public func configurationChanged(accountID: AccountID) async -> ReadReceipt {
        guard let account = accounts.first(where: { $0.accountID == accountID }) else {
            return .unavailable(sourceState: .unavailable)
        }
        inactiveAccounts.remove(accountID)
        providerScopes[accountID] = nil
        await account.source.configurationChanged()
        return await account.source.refresh()
    }

    private func listenForUpdates() {
        for account in accounts {
            listenerTasks.append(
                Task { [weak self] in
                    for await report in account.source.updates {
                        await self?.receive(report, from: account)
                    }
                })
        }
    }

    private func receive(_ report: SourceSnapshot, from account: CodexFleetAccount) async {
        guard !stopped else { return }
        if report.isCompleteReport, let scope = report.source.providerScope {
            let previousScope = providerScopes.updateValue(scope, forKey: account.accountID)
            if let previousScope, previousScope != scope {
                await reactivateInactiveAccounts(except: account.accountID)
            }
            let duplicates = await accountsWithScope(scope)
            if duplicates.count > 1, let winner = duplicates.min(by: numberOrder) {
                for duplicate in duplicates where duplicate.accountID != winner.accountID {
                    await deactivate(duplicate)
                }
            }
        }
        if inactiveAccounts.contains(account.accountID), report.source.state == .reporting {
            return
        }
        updateContinuation.yield(report)
    }

    private func resolveCurrentDuplicateScopes() async {
        var groups: [AccountScope: [CodexFleetAccount]] = [:]
        for account in accounts {
            if let scope = await account.source.providerScope {
                groups[scope, default: []].append(account)
            }
        }
        for duplicates in groups.values where duplicates.count > 1 {
            guard let winner = duplicates.min(by: numberOrder) else { continue }
            for duplicate in duplicates where duplicate.accountID != winner.accountID {
                await deactivate(duplicate)
            }
        }
    }

    private func accountsWithScope(_ scope: AccountScope) async -> [CodexFleetAccount] {
        var matches: [CodexFleetAccount] = []
        for account in accounts where await account.source.providerScope == scope {
            matches.append(account)
        }
        return matches
    }

    private func deactivate(_ account: CodexFleetAccount) async {
        guard inactiveAccounts.insert(account.accountID).inserted else { return }
        await account.source.rejectDuplicateProviderScope()
    }

    private func reactivateInactiveAccounts(except accountID: AccountID) async {
        var reactivated: [CodexFleetAccount] = []
        for account in accounts where account.accountID != accountID {
            if inactiveAccounts.remove(account.accountID) != nil { reactivated.append(account) }
        }
        for account in reactivated {
            providerScopes[account.accountID] = nil
            await account.source.configurationChanged()
            _ = await account.source.refresh()
        }
    }

    private func numberOrder(_ left: CodexFleetAccount, _ right: CodexFleetAccount) -> Bool {
        left.accountNumber < right.accountNumber
    }
}
