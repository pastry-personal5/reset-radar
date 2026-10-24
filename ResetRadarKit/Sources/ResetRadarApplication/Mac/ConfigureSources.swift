import ResetRadarDomain

public enum ConfigureSourcesError: Error, Equatable, Sendable {
    case unknownProduct
    /// `apply` needs a preview this instance produced.
    case previewRequired
    case confirmationRequired
    case productMismatch
    /// An existing command is unsafe or unprovable; it is never replaced.
    case unsafeExistingConfiguration
}

/// Drives `SourceConfigurator`: always preview first, apply only after confirmation.
public actor ConfigureSources {
    private let configurators: [ProductID: any SourceConfigurator]
    private var previewed: [ConfigurationPreviewRevision: ConfigurationPreview] = [:]

    public init(configurators: [any SourceConfigurator]) {
        self.configurators = Dictionary(
            configurators.map { ($0.product, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func discover(for product: ProductID) async throws -> [ConfigurationOption] {
        guard let configurator = configurators[product] else {
            throw ConfigureSourcesError.unknownProduct
        }
        return try await configurator.discover()
    }

    public func preview(
        for product: ProductID, optionID: ConfigurationOptionID,
        intent: ConfigurationIntent
    ) async throws -> ConfigurationPreview {
        guard let configurator = configurators[product] else {
            throw ConfigureSourcesError.unknownProduct
        }
        let preview = try await configurator.preview(optionID: optionID, intent: intent)
        guard preview.product == product else { throw ConfigureSourcesError.productMismatch }
        previewed[preview.revision] = preview
        return preview
    }

    public func apply(_ preview: ConfigurationPreview, confirmed: Bool) async throws {
        guard confirmed else { throw ConfigureSourcesError.confirmationRequired }
        guard let configurator = configurators[preview.product] else {
            throw ConfigureSourcesError.unknownProduct
        }
        guard previewed[preview.revision] == preview else {
            throw ConfigureSourcesError.previewRequired
        }
        guard await configurator.inspect(accountID: preview.intent.accountID) != .unsafe else {
            throw ConfigureSourcesError.unsafeExistingConfiguration
        }
        try await configurator.apply(preview)
        previewed[preview.revision] = nil
    }

    public func remove(
        _ accountID: AccountID, product: ProductID, confirmed: Bool
    ) async throws {
        guard confirmed else { throw ConfigureSourcesError.confirmationRequired }
        guard let configurator = configurators[product] else {
            throw ConfigureSourcesError.unknownProduct
        }
        try await configurator.remove(accountID: accountID)
    }

    /// Restores the stored prior setting, after the owner confirms.
    public func restore(_ product: ProductID, confirmed: Bool) async throws {
        guard confirmed else { throw ConfigureSourcesError.confirmationRequired }
        guard let configurator = configurators[product] else {
            throw ConfigureSourcesError.unknownProduct
        }
        try await configurator.restore()
    }
}
