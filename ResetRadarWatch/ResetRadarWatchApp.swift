import SwiftUI

@main
struct ResetRadarWatchApp: App {
    @StateObject private var environment = WatchEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .task { await environment.activate() }
        }
        .backgroundTask(.watchConnectivity) {
            await environment.finishBackgroundDelivery()
        }
    }
}
