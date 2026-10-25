@preconcurrency import AppKit
import ResetRadarDomain
import SwiftUI

struct MacMenuAccountSummary {
    static func line(
        account: AccountMetadata, snapshot: UsageSnapshot?, now: Date
    ) -> String {
        let fiveHour = MacAllowanceDisplay.resolve(
            account: account, window: .fiveHour, snapshot: snapshot, now: now)
        let weekly = MacAllowanceDisplay.resolve(
            account: account, window: .weekly, snapshot: snapshot, now: now)
        return "\(account.effectiveDisplayLabel) · 5h: \(reading(fiveHour))"
            + " · Weekly: \(reading(weekly))"
    }

    private static func reading(_ display: MacAllowanceDisplay) -> String {
        guard let percentage = display.percentageText else { return display.statusText }
        return display.state == .current ? percentage : "\(percentage) (\(display.statusText))"
    }
}

private struct MacMenuAccountLines: View {
    @ObservedObject var model: HomeViewModel

    var body: some View {
        if model.message != nil {
            Text("Account data unavailable")
        } else if model.accounts.isEmpty {
            Text("No sources configured")
        } else {
            ForEach(model.accounts, id: \.id) { account in
                Text(
                    MacMenuAccountSummary.line(
                        account: account, snapshot: model.snapshot, now: .now))
            }
        }
    }
}

struct MacMenuBarContent: View {
    @ObservedObject var bootstrap: MacBootstrap
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let environment = bootstrap.environment {
            MacMenuAccountLines(model: environment.ownerFlows.home)
        } else {
            Text(bootstrap.startupFailed ? "Collector unavailable" : "Starting collector…")
        }
        Divider()
        Button("Refresh All") {
            Task {
                if let environment = bootstrap.environment {
                    await bootstrap.log.record(.lifecycle(.refreshRequested))
                    bootstrap.messages.post("Refreshing configured sources.")
                    await environment.foreground()
                } else {
                    bootstrap.messages.post(
                        "Refresh is unavailable while the collector is stopped.",
                        tone: .attention)
                }
            }
        }
        Button("Open Reset Radar") {
            openWindow(id: "main")
            NSApplication.shared.activate()
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit") {
            Task {
                await bootstrap.log.record(.lifecycle(.stopping))
                await bootstrap.environment?.stop()
                await bootstrap.log.record(.lifecycle(.stopped))
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
