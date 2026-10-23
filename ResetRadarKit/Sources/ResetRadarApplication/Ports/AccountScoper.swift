import ResetRadarDomain

/// Turns a provider account identifier into an `AccountScope` without retaining it. Only
/// ProviderAdapters' Codex source calls it; Application defines the port and the fake.
public protocol AccountScoper: Sendable {
    func scope(forAccountIdentifier identifier: String) async throws -> AccountScope
}
