import Foundation
import ResetRadarApplication
import ResetRadarDomain

public struct CodexRuntimeMetadata: Equatable, Sendable {
    public let configurationRevision: ConfigurationPreviewRevision
    public let executable: CodexValidatedExecutable
    public let sourceVersion: String

    public init(
        configurationRevision: ConfigurationPreviewRevision,
        executable: CodexValidatedExecutable, sourceVersion: String
    ) {
        self.configurationRevision = configurationRevision
        self.executable = executable
        self.sourceVersion = sourceVersion
    }
}

public protocol CodexRuntimeInspecting: Sendable {
    func inspect() async throws -> CodexRuntimeMetadata
}

/// Revalidates only persisted, owner-approved launch material. It never discovers or falls back
/// to an ambient profile at runtime.
public struct StoredCodexRuntimeInspector: CodexRuntimeInspecting, Sendable {
    private let accountID: AccountID
    private let store: ProviderAccountCatalogStore
    private let validator: CodexExecutableValidator
    private let metadataReader: CodexExecutableMetadataReader
    private let workingDirectoryURL: URL

    public init(
        accountID: AccountID, store: ProviderAccountCatalogStore,
        validator: CodexExecutableValidator = CodexExecutableValidator(),
        metadataReader: CodexExecutableMetadataReader, workingDirectoryURL: URL
    ) {
        self.accountID = accountID
        self.store = store
        self.validator = validator
        self.metadataReader = metadataReader
        self.workingDirectoryURL = workingDirectoryURL
    }

    public func inspect() async throws -> CodexRuntimeMetadata {
        let configuration: CodexStoredConfiguration
        do {
            configuration = try await store.loadCodexConfiguration(accountID: accountID)
        } catch ProviderAccountCatalogStoreError.accountNotFound {
            throw CodexSourceFailure.notConfigured
        } catch {
            throw CodexSourceFailure.incompatible
        }
        let executable: CodexValidatedExecutable
        do {
            executable = try validator.validate(
                invocationPath: configuration.executable.invocationPath,
                pathEnvironment: configuration.environment["PATH"] ?? "")
        } catch CodexExecutableValidationError.unavailable {
            throw CodexSourceFailure.notInstalled
        } catch CodexExecutableValidationError.unsafePermissions {
            throw CodexSourceFailure.permissionDenied
        } catch {
            throw CodexSourceFailure.incompatible
        }
        let metadata: CodexExecutableMetadata
        do {
            metadata = try await metadataReader.read(
                executable: executable, environment: configuration.environment,
                workingDirectoryURL: workingDirectoryURL)
        } catch CodexCommandError.timedOut, CodexCommandError.launchFailed {
            throw CodexSourceFailure.temporarilyUnavailable
        } catch {
            throw CodexSourceFailure.incompatible
        }
        return CodexRuntimeMetadata(
            configurationRevision: configuration.revision, executable: metadata.executable,
            sourceVersion: metadata.publicVersion)
    }
}

/// Loads the current isolated launch record for every new child. Existing children are replaced
/// by `CodexAppServerSource` when its runtime inspector observes a metadata change.
public struct StoredCodexProcessRPCSessionFactory: CodexRPCSessionFactory, Sendable {
    private let accountID: AccountID
    private let store: ProviderAccountCatalogStore
    private let validator: CodexExecutableValidator
    private let host: ChildProcessHost
    private let workingDirectoryURL: URL
    private let clock: any AppClock

    public init(
        accountID: AccountID, store: ProviderAccountCatalogStore,
        validator: CodexExecutableValidator = CodexExecutableValidator(), host: ChildProcessHost,
        workingDirectoryURL: URL, clock: any AppClock
    ) {
        self.accountID = accountID
        self.store = store
        self.validator = validator
        self.host = host
        self.workingDirectoryURL = workingDirectoryURL
        self.clock = clock
    }

    public func makeSession(generation: UInt64) async throws -> any CodexRPCSession {
        let configuration: CodexStoredConfiguration
        do {
            configuration = try await store.loadCodexConfiguration(accountID: accountID)
        } catch ProviderAccountCatalogStoreError.accountNotFound {
            throw CodexSourceFailure.notConfigured
        } catch {
            throw CodexSourceFailure.incompatible
        }
        let executable: CodexValidatedExecutable
        do {
            executable = try validator.validate(
                invocationPath: configuration.executable.invocationPath,
                pathEnvironment: configuration.environment["PATH"] ?? "")
        } catch CodexExecutableValidationError.unavailable {
            throw CodexSourceFailure.notInstalled
        } catch CodexExecutableValidationError.unsafePermissions {
            throw CodexSourceFailure.permissionDenied
        } catch {
            throw CodexSourceFailure.incompatible
        }
        let launch: CodexProcessLaunchConfiguration
        do {
            launch = try CodexProcessLaunchConfiguration(
                executableURL: URL(fileURLWithPath: executable.invocationPath),
                environment: configuration.environment,
                workingDirectoryURL: workingDirectoryURL)
        } catch {
            throw CodexSourceFailure.permissionDenied
        }
        return try await CodexProcessRPCSessionFactory(
            configuration: launch, host: host, clock: clock
        ).makeSession(generation: generation)
    }
}
