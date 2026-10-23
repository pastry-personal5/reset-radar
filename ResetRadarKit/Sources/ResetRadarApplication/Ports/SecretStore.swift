/// Non-interactive access to named secrets. Fails with `interactionRequired` instead of prompting.
public protocol SecretStore: Sendable {
    func read(_ name: SecretName) async throws(SecretStoreError) -> SecretValue
    func write(_ name: SecretName, value: SecretValue) async throws(SecretStoreError)
    func delete(_ name: SecretName) async throws(SecretStoreError)
    /// Drops every per-process cached secret.
    func invalidateCache() async
}
