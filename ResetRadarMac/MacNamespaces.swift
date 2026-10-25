import Foundation
import ResetRadarStorage
import ResetRadarTransport

enum MacBuildFlavor: Sendable {
    case development
    case release
    case test(root: URL)

    static var current: Self {
        #if DEBUG
            .development
        #else
            .release
        #endif
    }

    var storage: StorageLocations {
        switch self {
        case .development:
            StorageLocations.macApplicationSupport(flavor: .debug)
        case .release:
            StorageLocations.macApplicationSupport(flavor: .release)
        case .test(let root):
            StorageLocations(root: root, flavor: .release)
        }
    }

    var keychainService: String? {
        switch self {
        case .development: KeychainSecretStore.macDevelopmentService
        case .release: KeychainSecretStore.macReleaseService
        case .test: nil
        }
    }

    var logDirectory: URL {
        switch self {
        case .development:
            let logs = FileManager.default.homeDirectoryForCurrentUser.appending(
                path: "Library/Logs", directoryHint: .isDirectory)
            return logs.appending(path: "ResetRadar.dev", directoryHint: .isDirectory)
        case .release:
            let logs = FileManager.default.homeDirectoryForCurrentUser.appending(
                path: "Library/Logs", directoryHint: .isDirectory)
            return logs.appending(path: "ResetRadar", directoryHint: .isDirectory)
        case .test(let root):
            return root.appending(path: "Logs", directoryHint: .isDirectory)
        }
    }

    var logSubsystem: String {
        switch self {
        case .development: "com.unidentifiedstealthstartup.ResetRadar.dev"
        case .release: "com.unidentifiedstealthstartup.ResetRadar"
        case .test: "com.unidentifiedstealthstartup.ResetRadar.test"
        }
    }
}
