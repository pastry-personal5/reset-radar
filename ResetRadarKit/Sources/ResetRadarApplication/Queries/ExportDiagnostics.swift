public enum ExportDiagnosticsError: Error, Equatable, Sendable {
    case confirmationRequired
}

/// A confirmed, redacted export of the diagnostics history.
public struct ExportDiagnostics: Sendable {
    private let diagnostics: any DiagnosticsSink
    private let clock: any AppClock

    public init(diagnostics: any DiagnosticsSink, clock: any AppClock) {
        self.diagnostics = diagnostics
        self.clock = clock
    }

    public func export(confirmed: Bool) async throws -> DiagnosticsExport {
        guard confirmed else { throw ExportDiagnosticsError.confirmationRequired }
        return DiagnosticsExport(events: await diagnostics.history(), exportedAt: clock.now)
    }
}
