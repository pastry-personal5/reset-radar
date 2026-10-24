import Foundation
import ResetRadarApplication
import ResetRadarDomain

public struct CodexDiscoveryContext: Equatable, Sendable {
    public let explicitExecutablePath: String?
    public let loginShellURL: URL?
    public let environment: [String: String]
    public let workingDirectoryURL: URL

    public init(
        explicitExecutablePath: String?, loginShellURL: URL?, environment: [String: String],
        workingDirectoryURL: URL
    ) {
        self.explicitExecutablePath = explicitExecutablePath
        self.loginShellURL = loginShellURL
        self.environment = environment
        self.workingDirectoryURL = workingDirectoryURL
    }
}

/// Supplies owner-selected profile environments. A production composition root may use an
/// owner-present discovery helper, but the adapter never consults it after configuration.
public protocol CodexDiscoveryContextProviding: Sendable {
    func contexts() async throws -> [CodexDiscoveryContext]
}

public struct FixedCodexDiscoveryContexts: CodexDiscoveryContextProviding, Sendable {
    private let values: [CodexDiscoveryContext]

    public init(_ values: [CodexDiscoveryContext]) {
        self.values = values
    }

    public func contexts() async throws -> [CodexDiscoveryContext] { values }
}

public protocol CodexAccountIDGenerating: Sendable {
    func makeAccountID() throws -> AccountID
}

public struct RandomCodexAccountIDGenerator: CodexAccountIDGenerating, Sendable {
    public init() {}

    public func makeAccountID() throws -> AccountID {
        var bytes = UUID().uuid
        let data = withUnsafeBytes(of: &bytes) { Data($0) }
        guard let identifier = AccountID(data: data) else {
            throw CodexConfiguratorError.accountIDGenerationFailed
        }
        return identifier
    }
}

public enum CodexConfiguratorError: Error, Equatable, Sendable {
    case unknownOption
    case invalidIntent
    case accountLimitReached
    case stalePreview
    case executableChanged
    case accountIDGenerationFailed
    case restoreUnavailable
    case discoveryFailed
}

public actor CodexConfigurator: SourceConfigurator {
    public nonisolated let product = ProductID.codex

    private struct DiscoveredOption: Sendable {
        let candidate: CodexDiscoveryCandidate
        let environment: [String: String]
        let workingDirectoryURL: URL
    }

    private struct PendingPreview: Sendable {
        let preview: ConfigurationPreview
        let option: DiscoveredOption
        let metadata: CodexExecutableMetadata
    }

    private let contexts: any CodexDiscoveryContextProviding
    private let locator: CodexExecutableLocator
    private let validator: CodexExecutableValidator
    private let metadataReader: CodexExecutableMetadataReader
    private let store: ProviderAccountCatalogStore
    private let identifiers: any CodexAccountIDGenerating
    private var discovered: [ConfigurationOptionID: DiscoveredOption] = [:]
    private var pending: [ConfigurationPreviewRevision: PendingPreview] = [:]

    public init(
        contexts: any CodexDiscoveryContextProviding, locator: CodexExecutableLocator,
        validator: CodexExecutableValidator = CodexExecutableValidator(),
        metadataReader: CodexExecutableMetadataReader,
        store: ProviderAccountCatalogStore,
        identifiers: any CodexAccountIDGenerating = RandomCodexAccountIDGenerator()
    ) {
        self.contexts = contexts
        self.locator = locator
        self.validator = validator
        self.metadataReader = metadataReader
        self.store = store
        self.identifiers = identifiers
    }

    public func inspect(accountID: AccountID?) async -> ConfigurationState {
        do {
            let state = try await store.configurationState(accountID: accountID)
            guard state == .configured, let accountID else { return state }
            let configuration = try await store.loadCodexConfiguration(accountID: accountID)
            // An upgrade or reinstall at the confirmed path is not drift: the runtime restarts the
            // child on a metadata change, so only a missing or unsafe executable is incompatible.
            _ = try validator.validate(
                invocationPath: configuration.executable.invocationPath,
                pathEnvironment: configuration.environment["PATH"] ?? "")
            return .configured
        } catch ProviderAccountCatalogStoreError.accountNotFound {
            return .notConfigured
        } catch {
            return .incompatible
        }
    }

    public func discover() async throws -> [ConfigurationOption] {
        discovered.removeAll()
        pending.removeAll()
        let selections: [CodexDiscoveryContext]
        do {
            selections = try await contexts.contexts()
        } catch {
            throw CodexConfiguratorError.discoveryFailed
        }
        var results: [ConfigurationOption] = []
        for selection in selections {
            let candidates: [CodexDiscoveryCandidate]
            do {
                candidates = try await locator.discover(
                    explicitPath: selection.explicitExecutablePath,
                    loginShellURL: selection.loginShellURL,
                    environment: selection.environment,
                    workingDirectoryURL: selection.workingDirectoryURL)
            } catch {
                continue
            }
            for candidate in candidates {
                let option = DiscoveredOption(
                    candidate: candidate, environment: selection.environment,
                    workingDirectoryURL: selection.workingDirectoryURL)
                discovered[candidate.option.id] = option
                results.append(candidate.option)
            }
        }
        return results
    }

    public func preview(
        optionID: ConfigurationOptionID, intent: ConfigurationIntent
    ) async throws -> ConfigurationPreview {
        guard let option = discovered[optionID] else {
            throw CodexConfiguratorError.unknownOption
        }
        try await validate(intent: intent)
        let executable: CodexValidatedExecutable
        do {
            executable = try validator.revalidate(
                option.candidate.executable,
                pathEnvironment: option.environment["PATH"] ?? "")
        } catch {
            throw CodexConfiguratorError.executableChanged
        }
        let metadata: CodexExecutableMetadata
        do {
            metadata = try await metadataReader.read(
                executable: executable, environment: option.environment,
                workingDirectoryURL: option.workingDirectoryURL)
        } catch {
            throw CodexConfiguratorError.executableChanged
        }
        let preview = ConfigurationPreview(
            product: .codex, optionID: optionID,
            revision: ConfigurationPreviewRevision(), intent: intent,
            launch: option.candidate.option.launch)
        pending[preview.revision] = PendingPreview(
            preview: preview, option: option, metadata: metadata)
        return preview
    }

    public func apply(_ preview: ConfigurationPreview) async throws {
        guard preview.product == .codex,
            let prepared = pending[preview.revision], prepared.preview == preview
        else { throw CodexConfiguratorError.stalePreview }
        pending[preview.revision] = nil  // claimed: a concurrent apply sees a stale preview
        do {
            try await applyPrepared(prepared, preview: preview)
        } catch {
            pending[preview.revision] = prepared
            throw error
        }
    }

    private func applyPrepared(
        _ prepared: PendingPreview, preview: ConfigurationPreview
    ) async throws {
        try await validate(intent: preview.intent)
        let executable: CodexValidatedExecutable
        do {
            executable = try validator.revalidate(
                prepared.option.candidate.executable,
                pathEnvironment: prepared.option.environment["PATH"] ?? "")
        } catch {
            throw CodexConfiguratorError.executableChanged
        }
        let metadata: CodexExecutableMetadata
        do {
            metadata = try await metadataReader.read(
                executable: executable, environment: prepared.option.environment,
                workingDirectoryURL: prepared.option.workingDirectoryURL)
        } catch {
            throw CodexConfiguratorError.executableChanged
        }
        guard metadata == prepared.metadata else {
            throw CodexConfiguratorError.executableChanged
        }
        switch preview.intent {
        case .add:
            let accountID = try identifiers.makeAccountID()
            _ = try await store.addCodexAccount(
                id: accountID, revision: preview.revision, executable: executable,
                environment: prepared.option.environment)
        case .replace(let accountID):
            _ = try await store.replaceCodexAccount(
                id: accountID, revision: preview.revision, executable: executable,
                environment: prepared.option.environment)
        }
    }

    public func remove(accountID: AccountID) async throws {
        try await store.removeCodexAccount(accountID: accountID)
    }

    public func restore() async throws {
        throw CodexConfiguratorError.restoreUnavailable
    }

    private func validate(intent: ConfigurationIntent) async throws {
        let catalog = try await store.loadCatalog()
        switch intent {
        case .add:
            guard
                catalog.accounts.count(where: { $0.product == .codex })
                    < AccountCatalog.maximumCodexAccounts
            else { throw CodexConfiguratorError.accountLimitReached }
        case .replace(let accountID):
            guard catalog.account(id: accountID)?.product == .codex else {
                throw CodexConfiguratorError.invalidIntent
            }
        }
    }
}
