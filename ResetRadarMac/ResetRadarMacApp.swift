import SwiftUI

@MainActor
final class MacBootstrap: ObservableObject {
    @Published var environment: MacEnvironment?
    @Published var startupFailed = false

    func start() async {
        guard environment == nil, !startupFailed else { return }
        do {
            let environment = try await ProductionEnvironmentFactory.make(
                mode: .selected())
            self.environment = environment
            await environment.start()
        } catch {
            startupFailed = true
        }
    }
}

@main
struct ResetRadarMacApp: App {
    @StateObject private var bootstrap = MacBootstrap()

    var body: some Scene {
        WindowGroup {
            RootView(startupFailed: bootstrap.startupFailed)
                .task { await bootstrap.start() }
        }
    }
}
