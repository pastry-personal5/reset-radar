import SwiftUI

@main
struct ResetRadarApp: App {
    private let launch = LaunchedReader.make()

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let environment):
                RootView(environment: environment)
            case .unavailable:
                ContentUnavailableView(
                    "Reset Radar Can’t Open Its Data", systemImage: "externaldrive.badge.xmark",
                    description: Text(
                        "This installation is missing its shared storage or Keychain access "
                            + "group. Reinstall the app with its original signing settings."))
            case .testHost:
                Color.clear
            }
        }
    }
}

/// The one environment this process builds, or why it could not be built.
@MainActor
enum LaunchedReader {
    case ready(ReaderEnvironment)
    case unavailable
    case testHost

    static func make() -> Self {
        switch ReaderLaunch.current() {
        case .live:
            do {
                return .ready(ReaderEnvironment(dependencies: try ReaderComposition.live()))
            } catch {
                return .unavailable
            }
        #if DEBUG
            case .unitTestHost:
                return .testHost
            case .synthetic(let scenario):
                let keep = ProcessInfo.processInfo.arguments.contains(
                    SyntheticReaderScenario.keepSelectionArgument)
                do {
                    return .ready(
                        ReaderEnvironment(
                            dependencies: try scenario.dependencies(keepSelection: keep)))
                } catch {
                    return .unavailable
                }
        #endif
        }
    }
}
