import ResetRadarDomain

/// Local setup of one source: Codex discovery or the Claude Code status line.
public protocol SourceConfigurator: Sendable {
    var product: ProductID { get }
    func inspect() async -> ConfigurationState
    func preview() async throws -> ConfigurationPreview
    func apply(_ preview: ConfigurationPreview) async throws
    func restore() async throws
}
