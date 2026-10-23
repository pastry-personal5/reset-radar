import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct ConfigureSourcesTests {
    @Test func applyWithoutConfirmationThrowsAndChangesNothing() async throws {
        let configurator = FakeSourceConfigurator(product: .claudeCode)
        let use = ConfigureSources(configurators: [configurator])
        let preview = try await use.preview(for: .claudeCode)
        await #expect(throws: ConfigureSourcesError.confirmationRequired) {
            try await use.apply(preview, confirmed: false)
        }
        #expect(configurator.applied.isEmpty)
    }

    @Test func aPreviewAlwaysPrecedesApply() async throws {
        let configurator = FakeSourceConfigurator(product: .codex)
        let use = ConfigureSources(configurators: [configurator])
        let unseen = ConfigurationPreview(product: .codex, change: .install)
        await #expect(throws: ConfigureSourcesError.previewRequired) {
            try await use.apply(unseen, confirmed: true)
        }
        let preview = try await use.preview(for: .codex)
        try await use.apply(preview, confirmed: true)
        #expect(configurator.applied == [preview])
        await #expect(throws: ConfigureSourcesError.previewRequired) {
            try await use.apply(preview, confirmed: true)
        }
    }

    @Test func anUnsafeExistingCommandIsNeverReplaced() async throws {
        let configurator = FakeSourceConfigurator(product: .claudeCode, configuration: .unsafe)
        let use = ConfigureSources(configurators: [configurator])
        let preview = try await use.preview(for: .claudeCode)
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
            try await use.preview(for: .codex)
        }
    }
}
