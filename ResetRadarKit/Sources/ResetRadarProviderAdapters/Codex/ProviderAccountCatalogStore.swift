import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain

public enum ProviderAccountCatalogStoreError: Error, Equatable, Sendable {
    case unsafeLocation
    case unavailable
    case incompatibleCatalog
    case incompatibleConfiguration
    case accountNotFound
    case accountAlreadyExists
    case labelConflict
}

public struct CodexStoredConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let accountID: AccountID
    public let revision: ConfigurationPreviewRevision
    public let executable: CodexValidatedExecutable
    public let environment: [String: String]

    public init(
        accountID: AccountID, revision: ConfigurationPreviewRevision,
        executable: CodexValidatedExecutable, environment: [String: String]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.accountID = accountID
        self.revision = revision
        self.executable = executable
        self.environment = environment
    }

    fileprivate var isValid: Bool {
        guard schemaVersion == Self.currentSchemaVersion,
            Set(environment.keys).isSubset(of: CodexProcessLaunchConfiguration.allowedEnvironment),
            CodexProcessLaunchConfiguration.requiredEnvironment.isSubset(of: Set(environment.keys)),
            environment.values.allSatisfy({ !$0.contains("\0") }),
            environment["HOME"].map({ $0.hasPrefix("/") }) == true,
            environment["USER"].map({ !$0.isEmpty }) == true,
            environment["LANG"].map({ !$0.isEmpty }) == true,
            environment["CODEX_HOME"].map({ $0.hasPrefix("/") }) ?? true,
            let path = environment["PATH"]
        else { return false }
        let components = path.split(separator: ":", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0.hasPrefix("/") }
    }
}

private struct StoredAccountEntry: Codable, Equatable {
    let metadata: AccountMetadata
    let configurationRevision: ConfigurationPreviewRevision
}

private struct StoredAccountIndex: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var accounts: [StoredAccountEntry]

    init(accounts: [StoredAccountEntry] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.accounts = accounts
    }

    var catalog: AccountCatalog? {
        guard schemaVersion == Self.currentSchemaVersion else { return nil }
        return try? AccountCatalog(validating: accounts.map(\.metadata))
    }
}

/// Owner-only metadata and isolated Codex launch records. File access is serialized both by this
/// actor and an owner-only advisory lock so a future helper process cannot race an update.
public actor ProviderAccountCatalogStore: AccountCatalogStore {
    public static let maximumFileBytes = 65_536

    private let files: OwnerOnlyConfigurationFiles

    public init(directoryURL: URL) {
        files = OwnerOnlyConfigurationFiles(directoryURL: directoryURL)
    }

    public func loadCatalog() throws -> AccountCatalog {
        try files.withLock {
            let index = try loadIndex()
            guard let catalog = index.catalog else {
                throw ProviderAccountCatalogStoreError.incompatibleCatalog
            }
            return catalog
        }
    }

    public func setAlias(
        accountID: AccountID, alias: AccountAlias?
    ) throws -> AccountCatalog {
        try files.withLock {
            var index = try loadIndex()
            guard let offset = index.accounts.firstIndex(where: { $0.metadata.id == accountID })
            else { throw ProviderAccountCatalogStoreError.accountNotFound }
            let existing = index.accounts[offset]
            index.accounts[offset] = StoredAccountEntry(
                metadata: existing.metadata.replacingAlias(alias),
                configurationRevision: existing.configurationRevision)
            guard let catalog = index.catalog else {
                throw ProviderAccountCatalogStoreError.incompatibleCatalog
            }
            try saveIndex(index)
            return catalog
        }
    }

    public func addCodexAccount(
        id: AccountID, revision: ConfigurationPreviewRevision,
        executable: CodexValidatedExecutable, environment: [String: String]
    ) throws -> AccountMetadata {
        try files.withLock {
            var index = try loadIndex()
            guard !index.accounts.contains(where: { $0.metadata.id == id }) else {
                throw ProviderAccountCatalogStoreError.accountAlreadyExists
            }
            guard let current = index.catalog else {
                throw ProviderAccountCatalogStoreError.incompatibleCatalog
            }
            let metadata = AccountMetadata(
                id: id, product: .codex, number: current.smallestUnusedNumber)
            let configuration = CodexStoredConfiguration(
                accountID: id, revision: revision, executable: executable,
                environment: environment)
            guard configuration.isValid else {
                throw ProviderAccountCatalogStoreError.incompatibleConfiguration
            }
            index.accounts.append(
                StoredAccountEntry(metadata: metadata, configurationRevision: revision))
            guard index.catalog != nil else {
                // The prior catalog was valid, so the new default label repeats an alias.
                throw ProviderAccountCatalogStoreError.labelConflict
            }
            try files.write(
                try encode(configuration), named: configurationFileName(for: id))
            do {
                try saveIndex(index)
            } catch {
                try? files.remove(named: configurationFileName(for: id))
                throw error
            }
            return metadata
        }
    }

    public func replaceCodexAccount(
        id: AccountID, revision: ConfigurationPreviewRevision,
        executable: CodexValidatedExecutable, environment: [String: String]
    ) throws -> AccountMetadata {
        try files.withLock {
            var index = try loadIndex()
            guard let offset = index.accounts.firstIndex(where: { $0.metadata.id == id }),
                index.accounts[offset].metadata.product == .codex
            else { throw ProviderAccountCatalogStoreError.accountNotFound }
            let configuration = CodexStoredConfiguration(
                accountID: id, revision: revision, executable: executable,
                environment: environment)
            guard configuration.isValid else {
                throw ProviderAccountCatalogStoreError.incompatibleConfiguration
            }
            let metadata = index.accounts[offset].metadata
            let fileName = configurationFileName(for: id)
            var previousData: Data?
            do {
                previousData = try files.read(named: fileName)
            } catch {
                previousData = nil
            }
            index.accounts[offset] = StoredAccountEntry(
                metadata: metadata, configurationRevision: revision)
            try files.write(try encode(configuration), named: fileName)
            do {
                try saveIndex(index)
            } catch {
                if let previousData {
                    try? files.write(previousData, named: fileName)
                } else {
                    try? files.remove(named: fileName)
                }
                throw error
            }
            return metadata
        }
    }

    public func loadCodexConfiguration(
        accountID: AccountID
    ) throws -> CodexStoredConfiguration {
        try files.withLock {
            let index = try loadIndex()
            guard
                let entry = index.accounts.first(where: { $0.metadata.id == accountID }),
                entry.metadata.product == .codex
            else { throw ProviderAccountCatalogStoreError.accountNotFound }
            let configuration: CodexStoredConfiguration
            do {
                configuration = try decode(
                    CodexStoredConfiguration.self,
                    from: files.read(named: configurationFileName(for: accountID)))
            } catch let error as ProviderAccountCatalogStoreError {
                throw error
            } catch {
                throw ProviderAccountCatalogStoreError.incompatibleConfiguration
            }
            guard configuration.isValid, configuration.accountID == accountID,
                configuration.revision == entry.configurationRevision
            else { throw ProviderAccountCatalogStoreError.incompatibleConfiguration }
            return configuration
        }
    }

    public func removeCodexAccount(accountID: AccountID) throws {
        try files.withLock {
            var index = try loadIndex()
            guard let offset = index.accounts.firstIndex(where: { $0.metadata.id == accountID }),
                index.accounts[offset].metadata.product == .codex
            else { throw ProviderAccountCatalogStoreError.accountNotFound }
            let fileName = configurationFileName(for: accountID)
            var previousData: Data?
            do {
                previousData = try files.read(named: fileName)
                try files.remove(named: fileName)
            } catch ProviderAccountCatalogStoreError.accountNotFound {
                previousData = nil
            } catch {
                // A corrupt, oversized, or unsafe launch file must not make the row permanent.
                previousData = nil
                try? files.remove(named: fileName)
            }
            index.accounts.remove(at: offset)
            guard index.catalog != nil else {
                throw ProviderAccountCatalogStoreError.incompatibleCatalog
            }
            do {
                try saveIndex(index)
            } catch {
                if let previousData { try? files.write(previousData, named: fileName) }
                throw error
            }
        }
    }

    public func configurationState(accountID: AccountID?) throws -> ConfigurationState {
        try files.withLock {
            let index = try loadIndex()
            guard let catalog = index.catalog else {
                throw ProviderAccountCatalogStoreError.incompatibleCatalog
            }
            guard let accountID else {
                return catalog.accounts.contains(where: { $0.product == .codex })
                    ? .configured : .notConfigured
            }
            guard let account = catalog.account(id: accountID), account.product == .codex else {
                return .notConfigured
            }
            do {
                let configuration: CodexStoredConfiguration = try decode(
                    CodexStoredConfiguration.self,
                    from: files.read(named: configurationFileName(for: accountID)))
                guard configuration.isValid, configuration.accountID == accountID,
                    index.accounts.first(where: { $0.metadata.id == accountID })?
                        .configurationRevision == configuration.revision
                else { return .incompatible }
                return .configured
            } catch {
                return .incompatible
            }
        }
    }

    private func loadIndex() throws -> StoredAccountIndex {
        let data: Data
        do {
            data = try files.read(named: "accounts.json")
        } catch ProviderAccountCatalogStoreError.accountNotFound {
            return StoredAccountIndex()
        }
        do {
            return try decode(StoredAccountIndex.self, from: data)
        } catch {
            throw ProviderAccountCatalogStoreError.incompatibleCatalog
        }
    }

    private func saveIndex(_ index: StoredAccountIndex) throws {
        guard index.catalog != nil else {
            throw ProviderAccountCatalogStoreError.incompatibleCatalog
        }
        try files.write(try encode(index), named: "accounts.json")
    }

    private func configurationFileName(for accountID: AccountID) -> String {
        "codex-\(accountID.hex).json"
    }

    private func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            guard data.count <= Self.maximumFileBytes else {
                throw ProviderAccountCatalogStoreError.incompatibleConfiguration
            }
            return data
        } catch let error as ProviderAccountCatalogStoreError {
            throw error
        } catch {
            throw ProviderAccountCatalogStoreError.unavailable
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= Self.maximumFileBytes else {
            throw ProviderAccountCatalogStoreError.incompatibleConfiguration
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ProviderAccountCatalogStoreError.incompatibleConfiguration
        }
    }
}
