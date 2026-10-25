@preconcurrency import AppKit
import ResetRadarProviderAdapters
import ResetRadarStorage
import SwiftUI

@MainActor
final class MacBootstrap: ObservableObject {
    @Published var environment: MacEnvironment?
    @Published var startupFailed = false
    let log: MacRotatingLog
    let messages: GlobalMessageCenter
    private var isStarting = false
    private var isRebuilding = false

    init() {
        let log = MacRotatingLog(
            directoryURL: MacBuildFlavor.current.logDirectory,
            subsystem: MacBuildFlavor.current.logSubsystem)
        self.log = log
        messages = GlobalMessageCenter(log: log)
    }

    func start() async {
        guard environment == nil, !startupFailed, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await log.startMaintenance()
        if !(await log.record(.lifecycle(.starting))) {
            messages.post(
                "Troubleshooting log is unavailable. Check Settings → Diagnostics.",
                tone: .attention)
        }
        messages.post("Starting the Mac collector.")
        do {
            let environment = try await ProductionEnvironmentFactory.make(
                mode: .selected(), messages: messages, log: log)
            messages.observe(environment.ownerFlows)
            self.environment = environment
            await environment.start()
            switch environment.state {
            case .running:
                if environment.collectionAllowed {
                    await log.record(.lifecycle(.ready))
                    messages.post("Mac collector is running.", tone: .success)
                } else {
                    messages.post(
                        "Collection is paused until signing is resolved. Review Signing and "
                            + "Keychain in Settings.", tone: .attention)
                }
            case .secondInstance:
                await log.record(.lifecycle(.secondInstance))
                if !Self.isTestHost {
                    NSApplication.shared.terminate(nil)
                }
            case .stopped:
                await log.record(.lifecycle(.stopped))
                messages.post("Mac collector stopped before startup completed.", tone: .attention)
            }
        } catch {
            startupFailed = true
            await log.record(.startupFailure(startupFailureCode(error)))
            messages.post(
                "Mac collector failed closed: \(startupFailureReason(error))",
                tone: .attention)
        }
    }

    private static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func startupFailureReason(_ error: any Error) -> String {
        if let sourceError = error as? ProviderAccountCatalogStoreError {
            return sourceFailureReason(sourceError)
        }
        if let storageError = error as? StorageError {
            return storageFailureReason(storageError)
        }
        return "a required local component could not be initialized."
    }

    private func startupFailureCode(_ error: any Error) -> MacStartupFailureCode {
        if let sourceError = error as? ProviderAccountCatalogStoreError {
            return sourceFailureCode(sourceError)
        }
        if let storageError = error as? StorageError {
            return storageFailureCode(storageError)
        }
        return .other
    }

    private func sourceFailureCode(
        _ error: ProviderAccountCatalogStoreError
    ) -> MacStartupFailureCode {
        switch error {
        case .unsafeLocation: .unsafeSourceLocation
        case .incompatibleCatalog, .incompatibleConfiguration: .incompatibleSourceConfiguration
        case .unavailable: .sourceConfigurationUnavailable
        case .accountNotFound, .accountAlreadyExists, .labelConflict: .inconsistentSourceCatalog
        }
    }

    private func storageFailureCode(_ error: StorageError) -> MacStartupFailureCode {
        switch error {
        case .corrupt: .corruptPublisherState
        case .incompatible: .incompatiblePublisherState
        case .tooLarge: .oversizedPublisherState
        case .lockTimeout: .busyPublisherState
        case .io: .publisherIO
        }
    }

    private func sourceFailureReason(_ error: ProviderAccountCatalogStoreError) -> String {
        switch error {
        case .unsafeLocation:
            "source configuration is stored in an unsafe location."
        case .incompatibleCatalog, .incompatibleConfiguration:
            "source configuration is incompatible or damaged."
        case .unavailable:
            "source configuration could not be read."
        case .accountNotFound, .accountAlreadyExists, .labelConflict:
            "the source catalog is inconsistent."
        }
    }

    private func storageFailureReason(_ error: StorageError) -> String {
        switch error {
        case .corrupt:
            "local publisher state is damaged."
        case .incompatible:
            "local publisher state uses an unsupported version."
        case .tooLarge:
            "local publisher state exceeds the supported size."
        case .lockTimeout:
            "local publisher state is busy."
        case .io:
            "local publisher state could not be read or written."
        }
    }

    func rebuildCollector() async {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        await log.record(.lifecycle(.restartRequested))
        messages.post("Restarting the collector after source changes.")
        if let environment {
            await environment.stop()
            self.environment = nil
        }
        startupFailed = false
        await start()
    }
}

@main
struct ResetRadarMacApp: App {
    @StateObject private var bootstrap = MacBootstrap()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(
                environment: bootstrap.environment, messages: bootstrap.messages,
                startupFailed: bootstrap.startupFailed
            )
            .frame(minWidth: 1400, minHeight: 900)
            .task { await bootstrap.start() }
        }
        Settings {
            SettingsRootView(
                models: bootstrap.environment?.ownerFlows,
                messages: bootstrap.messages,
                rebuildCollector: { await bootstrap.rebuildCollector() }
            )
            .task { await bootstrap.start() }
        }
        MenuBarExtra("Reset Radar", systemImage: "gauge.with.dots.needle.50percent") {
            MacMenuBarContent(bootstrap: bootstrap, messages: bootstrap.messages)
        }
    }
}
