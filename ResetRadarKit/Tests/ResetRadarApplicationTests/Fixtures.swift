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
let endpoint = URL(string: "https://relay.workers.dev")!

func requestID(_ value: UInt8) -> RequestID { RequestID(data: bytes(16, value))! }

/// One validated window. Defaults describe a reported Codex five-hour Home window.
func window(
    product: ProductID = .codex, scope: AccountScope? = nil, limitID: String? = nil,
    minutes: Int? = 300, isDefault: Bool = true, state: ReportState = .reported,
    resetsAt: Date? = at(7_200), percent: Double? = 42, observedAt: Date = at(0)
) -> AllowanceWindow {
    let raw = RawWindow(
        product: product.rawValue, accountScope: scope?.hex, limitID: limitID ?? product.rawValue,
        durationMinutes: minutes, isDefaultLimit: isDefault, reportState: state,
        resetsAt: resetsAt,
        observation: percent.map {
            RawObservation(
                usedPercent: $0, observedAt: observedAt, sourceVersion: "1.0", fractionDigits: 0)
        })
    // swiftlint:disable:next force_try
    return try! AllowanceWindow(validating: raw)
}

func source(_ product: ProductID = .codex, state: SourceState = .reporting) -> ProductSource {
    ProductSource(
        product: product, kind: product == .codex ? .codexAppServer : .claudeCodeStatusLine,
        version: "1.0", state: state)
}

func report(
    _ product: ProductID = .codex, state: SourceState = .reporting,
    windows: [AllowanceWindow] = [], complete: Bool = true
) -> SourceSnapshot {
    SourceSnapshot(
        source: source(product, state: state), windows: windows, isCompleteReport: complete)
}

func snapshot(
    windows: [AllowanceWindow], sources: [ProductSource]? = nil, generatedAt: Date = at(0),
    results: [ManualRefreshResult] = [], publisherID: PublisherID = publisher
) -> UsageSnapshot {
    // swiftlint:disable:next force_try
    try! UsageSnapshot(
        publisherID: publisherID, generatedAt: generatedAt, heartbeatSeconds: 300,
        sources: sources ?? [source(.codex), source(.claudeCode)], windows: windows,
        manualRefreshResults: results)
}
