/// A non-interactive secret-store failure. Carries no secret, label, or OS message.
public enum SecretStoreError: Error, Equatable, Sendable {
    case notFound
    /// The store would have to prompt (locked Keychain, changed signing identity, first unlock).
    case interactionRequired
    case unexpected(statusClass: Int)
}
