import ResetRadarDomain

/// Local setup of one source: Codex discovery or the Claude Code status line.
public protocol SourceConfigurator: Sendable {
    var product: ProductID { get }
    func inspect(accountID: AccountID?) async -> ConfigurationState
    func discover() async throws -> [ConfigurationOption]
    func preview(
        optionID: ConfigurationOptionID, intent: ConfigurationIntent
    ) async throws -> ConfigurationPreview
    func apply(_ preview: ConfigurationPreview) async throws
    func remove(accountID: AccountID) async throws
    func restore() async throws
}
