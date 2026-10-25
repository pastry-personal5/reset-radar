import Foundation
import ResetRadarStorage
import ResetRadarTransport

enum MacBuildFlavor: Sendable {
    case development
    case release
    case test(root: URL)

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
}
