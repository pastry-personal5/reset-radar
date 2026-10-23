import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// A source whose reads are scripted. `emit` pushes a report to `updates`.
public final class FakeUsageSource: UsageSource, @unchecked Sendable {
    private struct State {
        var receipts: [ReadReceipt] = []
        var starts = 0
        var stops = 0
        var refreshes = 0
        var startFailure = false
    }

    public let product: ProductID
    public let updates: AsyncStream<SourceSnapshot>
    private let continuation: AsyncStream<SourceSnapshot>.Continuation
    private let clock: any AppClock
    private let state = Locked(State())

    public init(product: ProductID, clock: any AppClock) {
        self.product = product
        self.clock = clock
        (updates, continuation) = AsyncStream.makeStream()
    }

    public var refreshCount: Int { state.withLock { $0.refreshes } }
    public var startCount: Int { state.withLock { $0.starts } }
    public var stopCount: Int { state.withLock { $0.stops } }

    public func queueReceipts(_ receipts: ReadReceipt...) {
        state.withLock { $0.receipts += receipts }
    }
    public func emit(_ report: SourceSnapshot) { continuation.yield(report) }

    public func start() async throws {
        state.withLock { $0.starts += 1 }
    }

    public func refresh() async -> ReadReceipt {
        let scripted = state.withLock { state -> ReadReceipt? in
            state.refreshes += 1
            return state.receipts.isEmpty ? nil : state.receipts.removeFirst()
        }
        if let scripted { return scripted }
        let now = clock.now
        return ReadReceipt(startedAt: now, finishedAt: now, succeeded: true)
    }

    public func stop() async { state.withLock { $0.stops += 1 } }
}

public enum FakeConfigurationError: Error, Equatable, Sendable {
    case unsafeExistingConfiguration
}

public final class FakeSourceConfigurator: SourceConfigurator, @unchecked Sendable {
    private struct State {
        var configuration: ConfigurationState = .notConfigured
        var applied: [ConfigurationPreview] = []
        var restores = 0
        var previews = 0
    }

    public let product: ProductID
    private let state = Locked(State())

    public init(product: ProductID, configuration: ConfigurationState = .notConfigured) {
        self.product = product
        state.withLock { $0.configuration = configuration }
    }

    public var applied: [ConfigurationPreview] { state.withLock { $0.applied } }
    public var restoreCount: Int { state.withLock { $0.restores } }
    public var previewCount: Int { state.withLock { $0.previews } }

    public func inspect() async -> ConfigurationState { state.withLock { $0.configuration } }

    public func preview() async throws -> ConfigurationPreview {
        state.withLock { $0.previews += 1 }
        return ConfigurationPreview(product: product, change: .install)
    }

    public func apply(_ preview: ConfigurationPreview) async throws {
        try state.withLock { state in
            guard state.configuration != .unsafe else {
                throw FakeConfigurationError.unsafeExistingConfiguration
            }
            state.applied.append(preview)
            state.configuration = .configured
        }
    }

    public func restore() async throws { state.withLock { $0.restores += 1 } }
}
