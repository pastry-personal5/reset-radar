import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct ConfigureSourcesTests {
    @Test func applyWithoutConfirmationThrowsAndChangesNothing() async throws {
        let configurator = FakeSourceConfigurator(product: .claudeCode)
        let use = ConfigureSources(configurators: [configurator])
        let preview = try await use.preview(
            for: .claudeCode, optionID: configurator.option.id, intent: .add)
        await #expect(throws: ConfigureSourcesError.confirmationRequired) {
            try await use.apply(preview, confirmed: false)
        }
        #expect(configurator.applied.isEmpty)
    }

    @Test func aPreviewAlwaysPrecedesApply() async throws {
        let configurator = FakeSourceConfigurator(product: .codex)
        let use = ConfigureSources(configurators: [configurator])
        let unseen = ConfigurationPreview(
            product: .codex, optionID: configurator.option.id,
            revision: ConfigurationPreviewRevision(), intent: .add,
            launch: configurator.option.launch)
        await #expect(throws: ConfigureSourcesError.previewRequired) {
            try await use.apply(unseen, confirmed: true)
        }
        let preview = try await use.preview(
            for: .codex, optionID: configurator.option.id, intent: .add)
        try await use.apply(preview, confirmed: true)
        #expect(configurator.applied == [preview])
        await #expect(throws: ConfigureSourcesError.previewRequired) {
            try await use.apply(preview, confirmed: true)
        }
    }

    @Test func anUnsafeExistingCommandIsNeverReplaced() async throws {
        let configurator = FakeSourceConfigurator(product: .claudeCode, configuration: .unsafe)
        let use = ConfigureSources(configurators: [configurator])
        let preview = try await use.preview(
            for: .claudeCode, optionID: configurator.option.id, intent: .add)
        await #expect(throws: ConfigureSourcesError.unsafeExistingConfiguration) {
            try await use.apply(preview, confirmed: true)
        }
        #expect(configurator.applied.isEmpty)
    }

    @Test func restoreNeedsConfirmation() async throws {
        let configurator = FakeSourceConfigurator(product: .claudeCode)
        let use = ConfigureSources(configurators: [configurator])
        await #expect(throws: ConfigureSourcesError.confirmationRequired) {
            try await use.restore(.claudeCode, confirmed: false)
        }
        try await use.restore(.claudeCode, confirmed: true)
    }

    @Test func anUnknownProductThrows() async {
        let use = ConfigureSources(configurators: [])
        await #expect(throws: ConfigureSourcesError.unknownProduct) {
            try await use.discover(for: .codex)
        }
    }

    @Test func discoveryReturnsOpaqueOptionsAndAnUnknownOptionFails() async throws {
        let configurator = FakeSourceConfigurator(product: .codex)
        let use = ConfigureSources(configurators: [configurator])
        #expect(try await use.discover(for: .codex) == [configurator.option])
        await #expect(throws: FakeConfigurationError.unknownOption) {
            try await use.preview(
                for: .codex, optionID: ConfigurationOptionID(), intent: .add)
        }
    }

    @Test func alteredPreviewAndUnconfirmedRemovalAreRejected() async throws {
        let configurator = FakeSourceConfigurator(product: .codex)
        let use = ConfigureSources(configurators: [configurator])
        let preview = try await use.preview(
            for: .codex, optionID: configurator.option.id, intent: .add)
        let altered = ConfigurationPreview(
            product: preview.product, optionID: preview.optionID, revision: preview.revision,
            intent: preview.intent,
            launch: ConfigurationLaunchPreview(
                executablePath: "/substituted/provider", environment: []))
        await #expect(throws: ConfigureSourcesError.previewRequired) {
            try await use.apply(altered, confirmed: true)
        }
        let accountID = AccountID(data: Data(repeating: 0x44, count: 16))!
        await #expect(throws: ConfigureSourcesError.confirmationRequired) {
            try await use.remove(accountID, product: .codex, confirmed: false)
        }
        try await use.remove(accountID, product: .codex, confirmed: true)
        #expect(configurator.removed == [accountID])
    }

    @Test func statusLineDetailIsPartOfThePreviewIdentity() async throws {
        let configurator = FakeSourceConfigurator(product: .claudeCode)
        let use = ConfigureSources(configurators: [configurator])
        let preview = try await use.preview(
            for: .claudeCode, optionID: configurator.option.id, intent: .add)
        #expect(preview.statusLine == nil)
        let detail = ConfigurationStatusLinePreview(
            settingsPath: "/Users/owner/.claude/settings.json",
            helperPath: "/Users/owner/Library/Application Support/ResetRadar/bin/helper",
            existingExecutablePath: "/Users/owner/bin/line", changeKind: .replaceCommand)
        let detailed = ConfigurationPreview(
            product: preview.product, optionID: preview.optionID, revision: preview.revision,
            intent: preview.intent, launch: preview.launch, statusLine: detail)
        #expect(detailed != preview)
        await #expect(throws: ConfigureSourcesError.previewRequired) {
            try await use.apply(detailed, confirmed: true)
        }
        try await use.apply(preview, confirmed: true)
    }

    @Test func restoreConflictAndActiveInstallationAreTypedErrors() {
        #expect(SourceConfigurationError.restoreConflict != .installationActive)
    }
}
