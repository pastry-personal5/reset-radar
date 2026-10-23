import Foundation
import ResetRadarDomain

public struct LoadUsageDetails: Sendable {
    private let visible: VisibleSnapshot
    private let clock: any AppClock

    public init(visible: VisibleSnapshot, clock: any AppClock) {
        self.visible = visible
        self.clock = clock
    }

    public func load() async -> UsageDetailsReadModel {
        let now = clock.now
        let snapshot = await visible.current()
        let products = ProductID.allCases.map { product in
            let source = snapshot?.source(for: product)
            let windows = (snapshot?.windows ?? []).filter { $0.product == product }.map {
                let presentation = PresentationPolicy.derive(window: $0, source: source, now: now)
                return WindowDetails(
                    window: $0, presentation: presentation.state,
                    nextChange: presentation.nextChange)
            }
            return ProductDetails(product: product, source: source, windows: windows)
        }
        return UsageDetailsReadModel(
            products: products,
            macLive: snapshot.map { MacLiveness.isPublishing(snapshot: $0, now: now) },
            transport: await visible.transportStatus())
    }
}
