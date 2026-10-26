import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarStorage
import ResetRadarTransport
import UIKit

/// Every port one reader process uses, so tests and synthetic scenarios replace system
/// boundaries without a second object graph.
struct ReaderDependencies {
    var reader: any ReaderStore
    var snapshots: any SnapshotStore
    var secrets: any SecretStore
    var relay: any RelayGateway
    var cipher: any EnvelopeCipher
    var codec: any PairingCodec
    var random: any SecretGenerator
    var clock: any AppClock
    var diagnostics: any DiagnosticsSink
    var system: any ReaderSystemStatus
    var selection: any AccountSelectionStore
    var preferences: any PreferenceStore
    var notificationGate: any NotificationReconcileGate
    /// False on iPad, which has no Watch stage.
    var hasWatchStage: Bool
}

/// Resolves the live object graph's storage root and Keychain access group.
enum ReaderComposition {
    static let appGroup = "group.com.unidentifiedstealthstartup.ResetRadar"
    static let keychainGroupInfoKey = "ResetRadarKeychainAccessGroup"

    enum Build: Equatable {
        case development
        case release

        static var current: Self {
            #if DEBUG
                .development
            #else
                .release
            #endif
        }
    }

    enum CompositionError: Error, Equatable {
        case appGroupUnavailable
        case keychainGroupUnavailable
        case preferencesUnavailable
    }

    /// Release requires the shared App Group container. Development builds are unsigned, so on a
    /// simulator they have no App Group entitlement and fall back to their own Application
    /// Support; either way Development uses the `Debug` flavor and never reads installed data.
    static func storageLocations(
        appGroupContainer: URL?, applicationSupport: URL, build: Build
    ) throws(CompositionError) -> StorageLocations {
        switch build {
        case .release:
            guard let appGroupContainer else { throw .appGroupUnavailable }
            return StorageLocations(root: appGroupContainer, flavor: .release)
        case .development:
            let root =
                appGroupContainer
                ?? applicationSupport.appending(path: "ResetRadar", directoryHint: .isDirectory)
            return StorageLocations(root: root, flavor: .debug)
        }
    }

    /// The entitlement-expanded access group shared with the widget. An unexpanded build
    /// variable or a missing value fails closed instead of using the default group.
    static func keychainAccessGroup(infoValue: Any?) throws(CompositionError) -> String {
        guard let value = infoValue as? String, value.hasSuffix(appGroup), !value.contains("$(")
        else { throw .keychainGroupUnavailable }
        return value
    }

    static func preferenceStore(
        appGroupSuite: UserDefaults?, build: Build
    ) throws(CompositionError) -> DefaultsPreferenceStore {
        switch build {
        case .release:
            guard let appGroupSuite else { throw .preferencesUnavailable }
            return DefaultsPreferenceStore(defaults: appGroupSuite)
        case .development:
            if let appGroupSuite { return DefaultsPreferenceStore(defaults: appGroupSuite) }
            guard
                let isolated = UserDefaults(
                    suiteName: "com.unidentifiedstealthstartup.ResetRadar.debug")
            else { throw .preferencesUnavailable }
            return DefaultsPreferenceStore(defaults: isolated)
        }
    }

    @MainActor
    static func live() throws -> ReaderDependencies {
        let fileManager = FileManager.default
        let locations = try storageLocations(
            appGroupContainer: fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup),
            applicationSupport: URL.applicationSupportDirectory, build: .current)
        let accessGroup = try keychainAccessGroup(
            infoValue: Bundle.main.object(forInfoDictionaryKey: keychainGroupInfoKey))
        let preferences = try preferenceStore(
            appGroupSuite: UserDefaults(suiteName: appGroup), build: .current)
        let store = BackgroundTaskReaderStore(
            store: FileReaderStore(locations: locations), assertion: ApplicationBackgroundTask())
        let clock = SystemReaderClock()
        return ReaderDependencies(
            reader: store, snapshots: ReaderSnapshotStore(store: store),
            secrets: KeychainSecretStore(
                build: Build.current == .release ? .release : .debug, accessGroup: accessGroup),
            relay: HTTPRelayGateway(), cipher: AESGCMEnvelopeCipher(), codec: JSONPairingCodec(),
            random: CryptoSecretGenerator(), clock: clock,
            diagnostics: LogDiagnosticsSink(locations: locations),
            system: LiveReaderSystemStatus(), selection: UserDefaultsSelectionStore(),
            preferences: preferences,
            notificationGate: FileNotificationReconcileGate(locations: locations, clock: clock),
            hasWatchStage: UIDevice.current.userInterfaceIdiom == .phone)
    }
}

/// How this process was launched. Only Development builds recognize test launches.
enum ReaderLaunch {
    case live
    #if DEBUG
        /// A hosted unit-test run: the tests build their own environments.
        case unitTestHost
        case synthetic(SyntheticReaderScenario)
    #endif

    static let scenarioArgument = "-ResetRadarSyntheticScenario"

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        #if DEBUG
            let value = arguments.firstIndex(of: scenarioArgument).flatMap { index in
                arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
            }
            if let scenario = value.flatMap(SyntheticReaderScenario.init(rawValue:)) {
                return .synthetic(scenario)
            }
            if environment["XCTestConfigurationFilePath"] != nil { return .unitTestHost }
        #endif
        return .live
    }
}
