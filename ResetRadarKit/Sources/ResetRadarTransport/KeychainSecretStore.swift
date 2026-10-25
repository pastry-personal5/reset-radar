import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Security

#if os(macOS)
    import LocalAuthentication
#endif

/// A narrow SecItem seam so Transport tests never touch a real Keychain.
public protocol SecItemBackend: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

public struct SystemSecItemBackend: SecItemBackend {
    public init() {}

    public func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

public actor KeychainSecretStore: SecretStore {
    public enum Build: Sendable {
        case debug
        case release
    }

    enum Policy: Sendable {
        case macLogin
        case iosDataProtection(accessGroup: String)
    }

    private let backend: any SecItemBackend
    private let service: String
    private let policy: Policy
    private var cache: [SecretName: SecretValue] = [:]

    #if os(iOS)
        public init(
            backend: any SecItemBackend = SystemSecItemBackend(),
            build: Build = {
                #if DEBUG
                    .debug
                #else
                    .release
                #endif
            }(),
            accessGroup: String
        ) {
            self.backend = backend
            service =
                build == .debug
                ? "com.unidentifiedstealthstartup.ResetRadar.transport.debug"
                : "com.unidentifiedstealthstartup.ResetRadar.transport"
            policy = .iosDataProtection(accessGroup: accessGroup)
        }
    #else
        public static let macReleaseService =
            "com.unidentifiedstealthstartup.ResetRadarMac.transport"
        public static let macDevelopmentService =
            "com.unidentifiedstealthstartup.ResetRadarMac.transport.dev"

        public init(
            backend: any SecItemBackend = SystemSecItemBackend(),
            build: Build = {
                #if DEBUG
                    .debug
                #else
                    .release
                #endif
            }()
        ) {
            self.backend = backend
            service =
                build == .debug
                ? Self.macDevelopmentService
                : Self.macReleaseService
            policy = .macLogin
        }
    #endif

    init(backend: any SecItemBackend, build: Build, policy: Policy) {
        self.backend = backend
        service =
            build == .debug
            ? "com.unidentifiedstealthstartup.ResetRadar.transport.debug"
            : "com.unidentifiedstealthstartup.ResetRadar.transport"
        self.policy = policy
    }

    public func read(_ name: SecretName) throws(SecretStoreError) -> SecretValue {
        if case .macLogin = policy, let cached = cache[name] { return cached }
        var query = baseQuery(for: name)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = backend.copyMatching(query)
        guard status == errSecSuccess else { throw map(status) }
        guard let data else { throw .unexpected(statusClass: 1) }
        let value = SecretValue(data)
        if case .macLogin = policy { cache[name] = value }
        return value
    }

    public func write(_ name: SecretName, value: SecretValue) throws(SecretStoreError) {
        cache[name] = nil
        let query = baseQuery(for: name)
        var attributes = query
        attributes[kSecValueData as String] = value.reveal()
        if case .iosDataProtection = policy {
            attributes[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = backend.add(attributes)
        if status == errSecDuplicateItem {
            var changes: [String: Any] = [kSecValueData as String: value.reveal()]
            if case .iosDataProtection = policy {
                changes[kSecAttrAccessible as String] =
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let updateStatus = backend.update(query, attributes: changes)
            guard updateStatus == errSecSuccess else { throw map(updateStatus) }
        } else if status != errSecSuccess {
            throw map(status)
        }
    }

    public func delete(_ name: SecretName) throws(SecretStoreError) {
        cache[name] = nil
        let status = backend.delete(baseQuery(for: name))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw map(status) }
    }

    public func invalidateCache() { cache.removeAll() }

    private func baseQuery(for name: SecretName) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: name),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        switch policy {
        case .macLogin:
            #if os(macOS)
                let context = LAContext()
                context.interactionNotAllowed = true
                query[kSecUseAuthenticationContext as String] = context
            #else
                break
            #endif
        case .iosDataProtection(let accessGroup):
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func account(for name: SecretName) -> String {
        switch name {
        case .contentKey: "content-key"
        case .writeToken: "write-token"
        case .adminToken: "admin-token"
        case .readToken: "read-token"
        case .readerToken(let id): "reader-token.\(id.hex)"
        case .accountScopeKey: "account-scope-key"
        }
    }

    private func map(_ status: OSStatus) -> SecretStoreError {
        switch status {
        case errSecItemNotFound: .notFound
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            .interactionRequired
        default: .unexpected(statusClass: Int(status))
        }
    }
}
