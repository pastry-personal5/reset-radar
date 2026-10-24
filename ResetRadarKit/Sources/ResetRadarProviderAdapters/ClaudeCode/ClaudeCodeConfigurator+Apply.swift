import Foundation
import ResetRadarApplication
import ResetRadarDomain

extension ClaudeCodeConfigurator {
    /// Everything `commit` writes, decided before any persistent write.
    struct Plan {
        let prior: StatusLineRestoreRecord.Prior
        let newBytes: Data
        let existingExecutable: String?
    }

    func applyPrepared(_ prepared: Pending) async throws {
        try automaticSetupBlocker()
        try requireCurrentHelper()
        try prepareSetupDirectory()
        let snapshot = try readSettings()
        guard snapshot.revision == prepared.settingsRevision else {
            throw ClaudeCodeConfiguratorError.stalePreview
        }
        if try await completeInterruptedInstall(snapshot: snapshot, prepared: prepared) { return }
        let plan = try makePlan(prepared, snapshot: snapshot)
        try await ensureAccountRow(prepared)
        try await commit(plan, snapshot: snapshot)
    }

    /// Idempotent reapply, or completion of a transaction interrupted after the settings write.
    private func completeInterruptedInstall(
        snapshot: ClaudeSettingsSnapshot, prepared: Pending
    ) async throws -> Bool {
        guard var record = try loadRestoreRecord(),
            case .command(let current) = snapshot.statusLine,
            current == record.installedCommand
        else { return false }
        record.state = .installed
        try saveRestore(record)
        try await ensureAccountRow(prepared)
        return true
    }

    private func makePlan(_ prepared: Pending, snapshot: ClaudeSettingsSnapshot) throws -> Plan {
        guard let existing = prepared.existing else {
            let bytes = try Self.edit {
                try ClaudeCodeSettingsEditor.inserting(
                    statusLineCommand: helperCommand, into: snapshot)
            }
            return Plan(prior: .absent, newBytes: bytes, existingExecutable: nil)
        }
        do {
            _ = try validator.revalidate(existing.identity)
        } catch {
            throw ClaudeCodeConfiguratorError.stalePreview
        }
        do {
            try check.verify(executablePath: existing.identity.canonicalPath)
        } catch SyntheticCompositionError.mismatch {
            throw ClaudeCodeConfiguratorError.compositionMismatch
        } catch {
            throw ClaudeCodeConfiguratorError.compositionFailed
        }
        let bytes = try Self.edit {
            try ClaudeCodeSettingsEditor.replacingCommand(in: snapshot, with: helperCommand)
        }
        return Plan(
            prior: .command(existing.rawCommand), newBytes: bytes,
            existingExecutable: existing.identity.canonicalPath)
    }

    private func ensureAccountRow(_ prepared: Pending) async throws {
        do {
            _ = try await catalog.ensureClaudeCodeAccount(
                id: makeAccountID(), revision: prepared.preview.revision)
        } catch {
            throw ClaudeCodeConfiguratorError.setupFailed
        }
    }

    /// Order: restore record, compose record, settings, then the installed mark.
    private func commit(_ plan: Plan, snapshot: ClaudeSettingsSnapshot) async throws {
        var record = StatusLineRestoreRecord(
            prior: plan.prior, installedCommand: helperCommand, transactionID: UUID(),
            createdAt: clock(), state: .pending)
        try saveRestore(record)
        try writeComposeRecord(for: plan.existingExecutable)
        do {
            try editor.replace(expecting: snapshot, with: plan.newBytes)
        } catch {
            recoverFromFailedReplace()
            if case ClaudeSettingsError.conflict = error {
                throw ClaudeCodeConfiguratorError.stalePreview
            }
            throw ClaudeCodeConfiguratorError.settingsUnsafe
        }
        record.state = .installed
        try saveRestore(record)
    }

    private func writeComposeRecord(for executable: String?) throws {
        do {
            if let executable, let compose = ComposeRecord(executablePath: executable) {
                try composeStore.save(compose)
            } else {
                try composeStore.remove()
            }
        } catch {
            try? restoreStore.remove()
            throw ClaudeCodeConfiguratorError.setupFailed
        }
    }

    /// After a failed replace: if the file already carries Reset Radar's command (a post-write
    /// mismatch), keep the restore record; otherwise nothing changed, so drop the artifacts.
    private func recoverFromFailedReplace() {
        if (try? editor.read())?.statusLine == .command(helperCommand) { return }
        try? composeStore.remove()
        try? restoreStore.remove()
    }

    /// The settings bytes after restoring, or nil when settings already hold the prior state.
    func restoredBytes(
        record: StatusLineRestoreRecord, snapshot: ClaudeSettingsSnapshot
    ) throws -> Data? {
        switch (record.prior, snapshot.statusLine) {
        case (.command(let prior), .command(let current)):
            if current == record.installedCommand {
                return try Self.edit {
                    try ClaudeCodeSettingsEditor.replacingCommand(in: snapshot, with: prior)
                }
            }
            guard current == prior else { throw SourceConfigurationError.restoreConflict }
            return nil
        case (.absent, .absent):
            return nil
        case (.absent, .command(let current)) where current == record.installedCommand:
            guard
                let removed = ClaudeCodeSettingsEditor.removingMinimalStatusLine(
                    in: snapshot, command: record.installedCommand)
            else { throw SourceConfigurationError.restoreConflict }
            return removed
        default:
            throw SourceConfigurationError.restoreConflict
        }
    }
}
