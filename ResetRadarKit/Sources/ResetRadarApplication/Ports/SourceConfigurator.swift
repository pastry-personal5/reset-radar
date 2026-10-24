import ResetRadarDomain

public enum SourceConfigurationError: Error, Equatable, Sendable {
    /// The current setting no longer equals what Reset Radar installed; nothing was changed and
    /// the owner must resolve it.
    case restoreConflict
    /// An account's source is still installed; restore it before removing the account.
    case installationActive
}

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
