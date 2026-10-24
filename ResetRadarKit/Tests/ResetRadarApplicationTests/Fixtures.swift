import Foundation
import ResetRadarDomain

@testable import ResetRadarApplication

/// Whole-second instants keep Date arithmetic exact in boundary tests.
let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)

func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }
func bytes(_ count: Int, _ value: UInt8) -> Data { Data(repeating: value, count: count) }

let publisher = PublisherID(data: bytes(32, 0x01))!
let otherPublisher = PublisherID(data: bytes(32, 0x02))!
let readerA = ReaderID(data: bytes(16, 0x0A))!
let readerB = ReaderID(data: bytes(16, 0x0B))!
let installation = InstallationID(data: bytes(16, 0x0C))!
let otherInstallation = InstallationID(data: bytes(16, 0x0D))!
let scopeA = AccountScope(data: bytes(16, 0xA1))!
let scopeB = AccountScope(data: bytes(16, 0xB2))!
let codexAccountID = AccountID(data: bytes(16, 0xC1))!
let otherCodexAccountID = AccountID(data: bytes(16, 0xC3))!
let claudeAccountID = AccountID(data: bytes(16, 0xC2))!
let codexFiveHour = AccountWindow(accountID: codexAccountID, window: .fiveHour)
let codexWeekly = AccountWindow(accountID: codexAccountID, window: .weekly)
let claudeFiveHour = AccountWindow(accountID: claudeAccountID, window: .fiveHour)
let claudeWeekly = AccountWindow(accountID: claudeAccountID, window: .weekly)
let endpoint = URL(string: "https://relay.workers.dev")!

func requestID(_ value: UInt8) -> RequestID { RequestID(data: bytes(16, value))! }

/// One validated window. Defaults describe a reported Codex five-hour Home window.
func window(
    accountID: AccountID? = nil, product: ProductID = .codex, scope: AccountScope? = nil,
    limitID: String? = nil, minutes: Int? = 300, isDefault: Bool = true,
    state: ReportState = .reported, resetsAt: Date? = at(7_200), percent: Double? = 42,
    observedAt: Date = at(0)
) -> AllowanceWindow {
    let raw = RawWindow(
        accountID: (accountID ?? (product == .codex ? codexAccountID : claudeAccountID)).hex,
        product: product.rawValue, accountScope: scope?.hex,
        limitID: limitID ?? product.rawValue, durationMinutes: minutes,
        isDefaultLimit: isDefault, reportState: state,
        resetsAt: resetsAt,
        observation: percent.map {
            RawObservation(
                usedPercent: $0, observedAt: observedAt, sourceVersion: "1.0", fractionDigits: 0)
        })
    // swiftlint:disable:next force_try
    return try! AllowanceWindow(validating: raw)
}

func source(
    _ product: ProductID = .codex, accountID: AccountID? = nil,
    state: SourceState = .reporting
) -> AccountSource {
    AccountSource(
        accountID: accountID ?? (product == .codex ? codexAccountID : claudeAccountID),
        product: product,
        kind: product == .codex ? .codexAppServer : .claudeCodeStatusLine, version: "1.0",
        state: state)
}

func report(
    _ product: ProductID = .codex, accountID: AccountID? = nil,
    state: SourceState = .reporting,
    windows: [AllowanceWindow] = [], complete: Bool = true
) -> SourceSnapshot {
    SourceSnapshot(
        source: source(product, accountID: accountID, state: state), windows: windows,
        isCompleteReport: complete)
}

func snapshot(
    windows: [AllowanceWindow], sources: [AccountSource]? = nil, generatedAt: Date = at(0),
    results: [ManualRefreshResult] = [], publisherID: PublisherID = publisher
) -> UsageSnapshot {
    // swiftlint:disable:next force_try
    try! UsageSnapshot(
        publisherID: publisherID, generatedAt: generatedAt, heartbeatSeconds: 300,
        accounts: [
            AccountMetadata(id: codexAccountID, product: .codex, number: 1),
            AccountMetadata(id: claudeAccountID, product: .claudeCode, number: 2),
        ], sources: sources ?? [source(.codex), source(.claudeCode)], windows: windows,
        manualRefreshResults: results)
}
