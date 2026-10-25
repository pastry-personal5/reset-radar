import Foundation
import ResetRadarApplication
import ResetRadarDomain

extension ClaudeCodeConfigurator {
    func inspectState() throws -> ConfigurationState {
        try prepareSetupDirectory()
        let record = try restoreStore.load()
        let compose: ComposeRecord?
        do {
            compose = try composeStore.load()
        } catch {
            return .incompatible
        }
        if paths.environment["CLAUDE_CONFIG_DIR"].map({ !$0.isEmpty }) ?? false {
            return .incompatible
        }
        let snapshot = try editor.read()
        if let record {
            return stateWithRecord(record, snapshot: snapshot, compose: compose)
        }
        return stateWithoutRecord(snapshot)
    }

    private func stateWithRecord(
        _ record: StatusLineRestoreRecord, snapshot: ClaudeSettingsSnapshot,
        compose: ComposeRecord?
    ) -> ConfigurationState {
        guard case .command(let current) = snapshot.statusLine,
            current == record.installedCommand
        else {
            // Only a pending transaction still at its exact prior value can safely start over.
            // Any other value may be a post-write owner edit and needs explicit resolution.
            return record.state == .pending && Self.matchesPrior(record.prior, snapshot.statusLine)
                ? .notConfigured : .incompatible
        }
        switch record.prior {
        case .absent:
            if compose != nil { return .incompatible }
        case .command:
            guard let compose, (try? validator.validatePath(compose.executablePath)) != nil
            else { return .incompatible }
        }
        return record.state == .installed ? .configured : .incompatible
    }

    private func stateWithoutRecord(_ snapshot: ClaudeSettingsSnapshot) -> ConfigurationState {
        switch snapshot.statusLine {
        case .absent:
            return .notConfigured
        case .unsupported:
            return .unsafe
        case .command(let command):
            if command == helperCommand { return .incompatible }
            return (try? trustedExecutable(for: command)) == nil ? .unsafe : .notConfigured
        }
    }

    /// The identity of a parseable, trusted existing command; throws for anything unprovable.
    func trustedExecutable(for command: String) throws -> ExecutableIdentity {
        let path = try ExistingStatusLineParser.parse(command, homeDirectory: paths.homeDirectory)
        let identity = try validator.identity(of: path)
        if ExistingStatusLineParser.isBashHomeScript(command) {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            guard try handle.read(upToCount: 12) == Data("#!/bin/bash\n".utf8) else {
                throw ExistingStatusLineParseError.unsupported
            }
            _ = try validator.revalidate(identity)
        }
        return identity
    }

    /// Classifies the current setting for a preview: nil when the setting is absent or already
    /// Reset Radar's own pending command, otherwise the trusted existing executable.
    func classifyExisting(
        _ snapshot: ClaudeSettingsSnapshot, record: StatusLineRestoreRecord?
    ) throws -> Existing? {
        let canRestartPendingTransaction =
            record.map {
                $0.state == .pending && Self.matchesPrior($0.prior, snapshot.statusLine)
            } ?? false
        let hasBlockingRestoreRecord =
            record != nil && snapshot.statusLine != .command(helperCommand)
            && !canRestartPendingTransaction
        if hasBlockingRestoreRecord {
            throw SourceConfigurationError.restoreConflict
        }
        switch snapshot.statusLine {
        case .absent:
            return nil
        case .unsupported:
            throw ConfigureSourcesError.unsafeExistingConfiguration
        case .command(let command):
            if command == helperCommand {
                guard let record else { throw ConfigureSourcesError.unsafeExistingConfiguration }
                if record.state == .installed {
                    throw ClaudeCodeConfiguratorError.alreadyConfigured
                }
                return nil
            }
            guard let identity = try? trustedExecutable(for: command) else {
                throw ConfigureSourcesError.unsafeExistingConfiguration
            }
            return Existing(
                rawCommand: command, identity: identity,
                runsThroughBash: ExistingStatusLineParser.isBashHomeScript(command))
        }
    }

    private static func matchesPrior(
        _ prior: StatusLineRestoreRecord.Prior, _ statusLine: ExistingStatusLine
    ) -> Bool {
        switch (prior, statusLine) {
        case (.absent, .absent): true
        case (.command(let prior), .command(let current)): prior == current
        default: false
        }
    }

    func automaticSetupBlocker() throws {
        if paths.environment["CLAUDE_CONFIG_DIR"].map({ !$0.isEmpty }) ?? false {
            throw ClaudeCodeConfiguratorError.customConfigurationRoot
        }
        guard let managed = paths.managedSettingsURL,
            FileManager.default.fileExists(atPath: managed.path)
        else { return }
        let snapshot: ClaudeSettingsSnapshot
        do {
            snapshot = try ClaudeCodeSettingsEditor.snapshot(of: Self.boundedRead(managed))
        } catch {
            // A managed file that cannot be read or parsed may still override the status line.
            throw ClaudeCodeConfiguratorError.settingsUnsafe
        }
        if snapshot.statusLine != .absent {
            throw ClaudeCodeConfiguratorError.managedSettingsOverride
        }
    }

    private static func boundedRead(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: StatusLineLimits.maximumSettingsBytes + 1) ?? Data()
        guard data.count <= StatusLineLimits.maximumSettingsBytes else {
            throw ClaudeSettingsError.tooLarge
        }
        return data
    }

    func requireCurrentHelper() throws {
        do {
            try installer.ensureCurrent()
        } catch {
            throw ClaudeCodeConfiguratorError.helperNotCurrent
        }
    }

    func prepareSetupDirectory() throws {
        do {
            try SessionRecordFile.ensureOwnerOnlyDirectory(paths.rootDirectory)
            let setup = paths.rootDirectory.appending(path: Self.setupDirectoryName)
            if mkdir(setup.path, 0o700) != 0, errno != EEXIST {
                throw ClaudeCodeConfiguratorError.setupFailed
            }
        } catch {
            throw ClaudeCodeConfiguratorError.setupFailed
        }
    }

    func readSettings() throws -> ClaudeSettingsSnapshot {
        do {
            return try editor.read()
        } catch {
            throw ClaudeCodeConfiguratorError.settingsUnsafe
        }
    }

    func loadRestoreRecord() throws -> StatusLineRestoreRecord? {
        do {
            return try restoreStore.load()
        } catch {
            throw ClaudeCodeConfiguratorError.setupFailed
        }
    }

    func saveRestore(_ record: StatusLineRestoreRecord) throws {
        do {
            try restoreStore.save(record)
        } catch {
            throw ClaudeCodeConfiguratorError.setupFailed
        }
    }

    static func edit(_ body: () throws -> Data) throws -> Data {
        do {
            return try body()
        } catch {
            throw ClaudeCodeConfiguratorError.settingsUnsafe
        }
    }
}
