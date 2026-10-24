import Foundation
import ResetRadarApplication
import ResetRadarDomain

public enum ClaudeCodeConfiguratorError: Error, Equatable, Sendable {
    case unknownOption
    /// Replace is not offered: Claude Code has one status line.
    case invalidIntent
    /// A relocated user root or a provable higher-precedence `statusLine` was found.
    case customConfigurationRoot
    case managedSettingsOverride
    case helperNotCurrent
    case settingsUnsafe
    case stalePreview
    case alreadyConfigured
    case compositionMismatch
    case compositionFailed
    case nothingToRestore
    case setupFailed
}

public struct ClaudeCodeConfiguratorPaths: Sendable {
    public let homeDirectory: URL
    /// `~/Library/Application Support/ResetRadar`.
    public let rootDirectory: URL
    /// The default `~/.claude/settings.json`; never inferred from a relocated root.
    public let settingsURL: URL
    /// The system managed-settings file, consulted only to prove a higher-precedence override.
    public let managedSettingsURL: URL?
    public let environment: [String: String]

    public init(
        homeDirectory: URL, rootDirectory: URL, settingsURL: URL, managedSettingsURL: URL?,
        environment: [String: String]
    ) {
        self.homeDirectory = homeDirectory
        self.rootDirectory = rootDirectory
        self.settingsURL = settingsURL
        self.managedSettingsURL = managedSettingsURL
        self.environment = environment
    }
}

/// Owner-confirmed setup of the Claude Code status line for the default user settings file.
public actor ClaudeCodeConfigurator: SourceConfigurator {
    public nonisolated let product = ProductID.claudeCode

    struct Pending {
        let preview: ConfigurationPreview
        let settingsRevision: String
        let existing: Existing?
    }

    struct Existing {
        let rawCommand: String
        let identity: ExecutableIdentity
    }

    let paths: ClaudeCodeConfiguratorPaths
    let installer: StatusLineHelperInstaller
    let catalog: ProviderAccountCatalogStore
    let editor: ClaudeCodeSettingsEditor
    let restoreStore: StatusLineRestoreStore
    let composeStore: ComposeRecordStore
    let validator: ExecutableIdentityValidator
    let check: SyntheticCompositionCheck
    let makeAccountID: @Sendable () -> AccountID
    let clock: @Sendable () -> Date
    let optionID = ConfigurationOptionID()
    var pending: [ConfigurationPreviewRevision: Pending] = [:]

    public static let setupDirectoryName = "claude-setup"

    public init(
        paths: ClaudeCodeConfiguratorPaths, installer: StatusLineHelperInstaller,
        catalog: ProviderAccountCatalogStore,
        makeAccountID: @escaping @Sendable () -> AccountID = {
            var bytes = UUID().uuid
            return AccountID(data: withUnsafeBytes(of: &bytes) { Data($0) })!
        },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.installer = installer
        self.catalog = catalog
        let setup = paths.rootDirectory.appending(path: Self.setupDirectoryName)
        editor = ClaudeCodeSettingsEditor(
            settingsURL: paths.settingsURL, transactionDirectory: setup)
        restoreStore = StatusLineRestoreStore(directory: setup)
        composeStore = ComposeRecordStore(rootDirectory: paths.rootDirectory)
        validator = ExecutableIdentityValidator(homeDirectory: paths.homeDirectory)
        check = SyntheticCompositionCheck(
            validator: validator, homeDirectory: paths.homeDirectory,
            environment: Self.boundedEnvironment(paths.environment))
        self.makeAccountID = makeAccountID
        self.clock = clock
    }

    /// The helper command Reset Radar installs: the quoted stable absolute path.
    public nonisolated var helperCommand: String { "\"\(installer.installedURL.path)\"" }

    static func boundedEnvironment(_ source: [String: String]) -> [String: String] {
        let keys = ["HOME", "USER", "LANG", "PATH"]
        return source.filter { keys.contains($0.key) }
    }

    // MARK: SourceConfigurator

    public func inspect(accountID: AccountID?) async -> ConfigurationState {
        do {
            return try inspectState()
        } catch is StatusLineRestoreError {
            return .incompatible
        } catch {
            return .unsafe
        }
    }

    public func discover() async throws -> [ConfigurationOption] {
        pending.removeAll()
        do {
            try automaticSetupBlocker()
        } catch {
            return []
        }
        return [
            ConfigurationOption(
                id: optionID, product: .claudeCode,
                launch: ConfigurationLaunchPreview(
                    executablePath: installer.installedURL.path, environment: []))
        ]
    }

    public func preview(
        optionID requested: ConfigurationOptionID, intent: ConfigurationIntent
    ) async throws -> ConfigurationPreview {
        guard requested == optionID else { throw ClaudeCodeConfiguratorError.unknownOption }
        guard intent == .add else { throw ClaudeCodeConfiguratorError.invalidIntent }
        try automaticSetupBlocker()
        try requireCurrentHelper()
        try prepareSetupDirectory()
        let snapshot = try readSettings()
        let existing = try classifyExisting(snapshot, record: try loadRestoreRecord())
        let preview = ConfigurationPreview(
            product: .claudeCode, optionID: optionID, revision: ConfigurationPreviewRevision(),
            intent: .add,
            launch: ConfigurationLaunchPreview(
                executablePath: installer.installedURL.path, environment: []),
            statusLine: ConfigurationStatusLinePreview(
                settingsPath: paths.settingsURL.path, helperPath: installer.installedURL.path,
                existingExecutablePath: existing?.identity.canonicalPath,
                changeKind: existing == nil && snapshot.statusLine == .absent
                    ? .add : .replaceCommand))
        pending[preview.revision] = Pending(
            preview: preview, settingsRevision: snapshot.revision, existing: existing)
        return preview
    }

    public func apply(_ preview: ConfigurationPreview) async throws {
        guard preview.product == .claudeCode, let prepared = pending[preview.revision],
            prepared.preview == preview
        else { throw ClaudeCodeConfiguratorError.stalePreview }
        pending[preview.revision] = nil
        do {
            try await applyPrepared(prepared)
        } catch {
            // A changed input needs a fresh preview, not a retry of this one.
            if (error as? ClaudeCodeConfiguratorError) != .stalePreview {
                pending[preview.revision] = prepared
            }
            throw error
        }
    }

    public func remove(accountID: AccountID) async throws {
        try prepareSetupDirectory()
        guard try loadRestoreRecord() == nil else {
            throw SourceConfigurationError.installationActive
        }
        do {
            try await catalog.removeClaudeCodeAccount(accountID: accountID)
        } catch {
            throw ClaudeCodeConfiguratorError.setupFailed
        }
    }

    public func restore() async throws {
        try prepareSetupDirectory()
        guard let record = try loadRestoreRecord() else {
            throw ClaudeCodeConfiguratorError.nothingToRestore
        }
        let snapshot = try readSettings()
        if let newBytes = try restoredBytes(record: record, snapshot: snapshot) {
            do {
                try editor.replace(expecting: snapshot, with: newBytes)
            } catch ClaudeSettingsError.conflict {
                throw SourceConfigurationError.restoreConflict
            } catch {
                throw ClaudeCodeConfiguratorError.settingsUnsafe
            }
        }
        // The prior setting is durable in settings.json; only now drop Reset Radar's artifacts.
        do {
            try composeStore.remove()
            try restoreStore.remove()
        } catch {
            throw ClaudeCodeConfiguratorError.setupFailed
        }
    }
}
