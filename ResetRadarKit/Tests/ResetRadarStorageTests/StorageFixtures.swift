import Foundation
import ResetRadarDomain

/// Whole-second instants keep Date arithmetic exact in boundary tests.
let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)

func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }
func bytes(_ count: Int, _ value: UInt8) -> Data { Data(repeating: value, count: count) }

let publisher = PublisherID(data: bytes(32, 0x01))!
let readerA = ReaderID(data: bytes(16, 0x0A))!
let installation = InstallationID(data: bytes(16, 0x0C))!
let endpoint = URL(string: "https://relay.workers.dev")!
let codexAccountID = AccountID(data: bytes(16, 0xC1))!
let codexFiveHour = AccountWindow(accountID: codexAccountID, window: .fiveHour)
let codexWeekly = AccountWindow(accountID: codexAccountID, window: .weekly)
let otherAccountID = AccountID(data: bytes(16, 0xC2))!
let otherWeekly = AccountWindow(accountID: otherAccountID, window: .weekly)

func requestID(_ value: UInt8) -> RequestID { RequestID(data: bytes(16, value))! }

func window(percent: Double = 42, product: ProductID = .codex) -> AllowanceWindow {
    let raw = RawWindow(
        accountID: codexAccountID.hex, product: product.rawValue, accountScope: nil,
        limitID: product.rawValue,
        durationMinutes: 300, isDefaultLimit: true, reportState: .reported, resetsAt: at(7_200),
        observation: RawObservation(
            usedPercent: percent, observedAt: at(0), sourceVersion: "1.0", fractionDigits: 0))
    // swiftlint:disable:next force_try
    return try! AllowanceWindow(validating: raw)
}

func snapshot(percent: Double = 42, generatedAt: Date = at(0)) -> UsageSnapshot {
    // swiftlint:disable:next force_try
    try! UsageSnapshot(
        publisherID: publisher, generatedAt: generatedAt, heartbeatSeconds: 300,
        accounts: [AccountMetadata(id: codexAccountID, product: .codex, number: 1)],
        sources: [
            AccountSource(
                accountID: codexAccountID, product: .codex, kind: .codexAppServer,
                version: "1.0", state: .reporting)
        ],
        windows: [window(percent: percent)])
}
