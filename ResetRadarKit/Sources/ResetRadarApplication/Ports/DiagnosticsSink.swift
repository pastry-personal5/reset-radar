import ResetRadarDomain

public protocol DiagnosticsSink: Sendable {
    func record(_ event: DiagnosticEvent) async
    func history() async -> [DiagnosticEvent]
}
