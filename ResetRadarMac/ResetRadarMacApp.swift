@preconcurrency import AppKit
import SwiftUI

@MainActor
final class MacBootstrap: ObservableObject {
    @Published var environment: MacEnvironment?
    @Published var startupFailed = false
    private var isRebuilding = false

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

    func rebuildCollector() async {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }
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
        WindowGroup {
            RootView(environment: bootstrap.environment, startupFailed: bootstrap.startupFailed)
                .frame(minWidth: 1400, minHeight: 900)
                .task { await bootstrap.start() }
        }
        Settings {
            SettingsRootView(
                models: bootstrap.environment?.ownerFlows,
                rebuildCollector: { await bootstrap.rebuildCollector() })
        }
        MenuBarExtra("Reset Radar", systemImage: "gauge.with.dots.needle.50percent") {
            Button("Refresh All") {
                Task { await bootstrap.environment?.foreground() }
            }
            Button("Open Reset Radar") {
                NSApplication.shared.activate()
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit") {
                Task {
                    await bootstrap.environment?.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
