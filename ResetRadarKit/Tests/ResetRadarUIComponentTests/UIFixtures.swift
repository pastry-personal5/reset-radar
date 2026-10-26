import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport

let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)
func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

func accountID(_ value: UInt8) -> AccountID {
    guard let id = AccountID(data: Data(repeating: value, count: AccountID.byteCount)) else {
        preconditionFailure("invalid fixture identifier")
    }
    return id
}

let codexA = accountID(0xC1)
let codexB = accountID(0xC3)
let claude = accountID(0xC2)
let publisherID = PublisherID(data: Data(repeating: 0x01, count: PublisherID.byteCount))!

func window(
    _ account: AccountID, product: ProductID = .codex, limitID: String = "primary",
    label: String? = nil, minutes: Int? = 300, isDefault: Bool = true,
    state: ReportState = .reported, resetsAt: Date? = at(7_200), percent: Double? = 42,
    fractionDigits: Int? = 0, observedAt: Date = at(0)
) -> AllowanceWindow {
    let raw = RawWindow(
        accountID: account.hex, product: product.rawValue, limitID: limitID, label: label,
        durationMinutes: minutes, isDefaultLimit: isDefault, reportState: state,
        resetsAt: resetsAt,
        observation: percent.map {
            RawObservation(
                usedPercent: $0, observedAt: observedAt, sourceVersion: "fixture",
                fractionDigits: fractionDigits)
        })
    do {
        return try AllowanceWindow(validating: raw)
    } catch {
        preconditionFailure("invalid fixture window: \(error)")
    }
}

func source(
    _ account: AccountID, product: ProductID = .codex, state: SourceState = .reporting
) -> AccountSource {
    AccountSource(
        accountID: account, product: product,
        kind: product == .codex ? .codexAppServer : .claudeCodeStatusLine, version: "1.0",
        state: state)
}

func snapshot(
    accounts: [AccountMetadata], sources: [AccountSource], windows: [AllowanceWindow],
    generatedAt: Date = at(0)
) -> UsageSnapshot {
    do {
        return try UsageSnapshot(
            publisherID: publisherID, generatedAt: generatedAt, heartbeatSeconds: 300,
            accounts: accounts, sources: sources, windows: windows)
    } catch {
        preconditionFailure("invalid fixture snapshot: \(error)")
    }
}

/// A Codex account with both standard windows and one additional provider window, and a
/// Claude Code account whose weekly window is missing.
func standardSnapshot(codexState: SourceState = .reporting) -> UsageSnapshot {
    snapshot(
        accounts: [
            AccountMetadata(id: codexA, product: .codex, number: 1),
            AccountMetadata(id: claude, product: .claudeCode, number: 3),
        ],
        sources: [source(codexA, state: codexState), source(claude, product: .claudeCode)],
        windows: [
            window(codexA, percent: 42),
            window(codexA, limitID: "weekly", minutes: 10_080, resetsAt: at(500_000), percent: 7),
            window(
                codexA, limitID: "review", label: "Code review", minutes: 10_080,
                isDefault: false, resetsAt: at(400_000), percent: 12),
            window(claude, product: .claudeCode, percent: 33.5, fractionDigits: 1),
        ])
}

func loadDetails(_ snapshot: UsageSnapshot, now: Date = at(60)) async -> UsageDetailsReadModel {
    let clock = FakeAppClock(start: now)
    return await LoadUsageDetails(
        visible: VisibleSnapshot(snapshots: FakeSnapshotStore(snapshot: snapshot)), clock: clock
    ).load()
}

func loadHome(_ snapshot: UsageSnapshot, now: Date = at(60)) async -> HomeReadModel {
    let clock = FakeAppClock(start: now)
    return await LoadHome(
        visible: VisibleSnapshot(snapshots: FakeSnapshotStore(snapshot: snapshot)), clock: clock
    ).load()
}

func pairingStatus(
    _ state: PairingState, cleanupPending: Bool = false, watchErase: WatchEraseState? = nil
) -> PairingStatusReadModel {
    PairingStatusReadModel(state: state, cleanupPending: cleanupPending, watchErase: watchErase)
}
