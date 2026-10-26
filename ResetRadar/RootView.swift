import ResetRadarUI
import SwiftUI

/// The Main Toolbar: five fixed destinations, each owning its navigation stack. iPad uses the
/// system's adaptive tab bar or sidebar with the same order and icons.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var environment: ReaderEnvironment

    var body: some View {
        TabView {
            Tab("Home", image: "Home") {
                HomeView(environment: environment)
            }
            Tab("Benefits", image: "Benefits") {
                EmptyDestinationView(title: "Benefits", image: "Benefits")
            }
            Tab("Community", image: "Community") {
                EmptyDestinationView(title: "Community", image: "Community")
            }
            Tab("Insight", image: "Insight") {
                EmptyDestinationView(title: "Insight", image: "Insight")
            }
            Tab("All", image: "AllToolbar") {
                AllView(environment: environment)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await environment.sceneBecameActive() }
            } else {
                environment.sceneBecameInactive()
            }
        }
    }
}

/// Benefits, Community, Insight: intentionally empty for now.
private struct EmptyDestinationView: View {
    let title: String
    let image: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, image: image)
            } description: {
                Text("This destination has no content yet.")
            }
            .navigationTitle(title)
        }
    }
}

private enum AllRoute: Hashable {
    case settings
}

/// All is empty apart from its top-right Settings action, which pushes Settings.
private struct AllView: View {
    @ObservedObject var environment: ReaderEnvironment

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("All", image: "AllToolbar")
            } description: {
                Text("This destination has no content yet.")
            }
            .navigationTitle("All")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AllRoute.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: AllRoute.self) { _ in
                SettingsView(environment: environment)
            }
        }
    }
}
