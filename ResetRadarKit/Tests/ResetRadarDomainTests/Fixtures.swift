import Foundation

@testable import ResetRadarDomain

/// Whole-second instants keep Date arithmetic exact in boundary tests.
let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)

func text(_ data: Data) -> String { String(data: data, encoding: .utf8) ?? "" }

func wire(_ value: some Encodable) throws -> String { text(try WireCoding.encoder().encode(value)) }

func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

func bytes(_ count: Int, _ value: UInt8 = 0xAB) -> Data { Data(repeating: value, count: count) }

let publisher = PublisherID(data: bytes(32, 0x01))!
let readerA = ReaderID(data: bytes(16, 0x0A))!
let readerB = ReaderID(data: bytes(16, 0x0B))!
let installation = InstallationID(data: bytes(16, 0x0C))!

func requestID(_ value: UInt8) -> RequestID { RequestID(data: bytes(16, value))! }

func rawWindow(
    product: String = "codex", limitID: String = "codex", minutes: Int? = 300,
    isDefault: Bool = true, state: ReportState = .reported, resetsAt: Date? = at(7_200),
    percent: Double? = 42, observedAt: Date = at(0), fractionDigits: Int? = 0
) -> RawWindow {
    RawWindow(
        product: product, limitID: limitID, durationMinutes: minutes, isDefaultLimit: isDefault,
        reportState: state, resetsAt: resetsAt,
        observation: percent.map {
            RawObservation(
                usedPercent: $0, observedAt: observedAt, sourceVersion: "1.0",
                fractionDigits: fractionDigits)
        })
}

func window(
    product: ProductID = .codex, limitID: String? = nil, minutes: Int? = 300,
    isDefault: Bool = true, state: ReportState = .reported, resetsAt: Date? = at(7_200),
    percent: Double? = 42, observedAt: Date = at(0)
) -> AllowanceWindow {
    // swiftlint:disable:next force_try
    try! AllowanceWindow(
        validating: rawWindow(
            product: product.rawValue, limitID: limitID ?? product.rawValue, minutes: minutes,
            isDefault: isDefault, state: state, resetsAt: resetsAt, percent: percent,
            observedAt: observedAt))
}

func source(_ product: ProductID = .codex, state: SourceState = .reporting) -> ProductSource {
    ProductSource(
        product: product, kind: product == .codex ? .codexAppServer : .claudeCodeStatusLine,
        version: "1.0", state: state)
}

func snapshot(
    windows: [AllowanceWindow], heartbeat: Int = 300, generatedAt: Date = at(0),
    results: [ManualRefreshResult] = []
) -> UsageSnapshot {
    // swiftlint:disable:next force_try
    try! UsageSnapshot(
        publisherID: publisher, generatedAt: generatedAt, heartbeatSeconds: heartbeat,
        sources: [source(.codex), source(.claudeCode)], windows: windows,
        manualRefreshResults: results)
}
