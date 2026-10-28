@preconcurrency import AppKit
import Combine
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
    @State private var now = Date()

    var body: some View {
        Group {
            if model.loadFailed {
                Text("Account data unavailable")
            } else if model.accounts.isEmpty {
                Text("No sources configured")
            } else {
                ForEach(model.accounts, id: \.id) { account in
                    Text(
                        MacMenuAccountSummary.line(
                            account: account, snapshot: model.snapshot, now: now))
                }
            }
        }
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) {
            now = $0
        }
    }
}

struct MacMenuBarContent: View {
    @ObservedObject var bootstrap: MacBootstrap
    @ObservedObject var messages: GlobalMessageCenter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let environment = bootstrap.environment {
            MacMenuAccountLines(model: environment.ownerFlows.home)
            if !environment.collectionAllowed {
                Text("Collection paused: review Signing and Keychain in Settings")
            }
        } else {
            Text(bootstrap.startupFailed ? "Collector unavailable" : "Starting collector…")
        }
        if messages.publicationProblem != nil {
            Text("Relay publication needs attention")
        } else if let lastPublishedAt = messages.lastPublishedAt {
            Text(
                "Last published \(lastPublishedAt.formatted(date: .abbreviated, time: .shortened))")
        } else {
            Text("No relay publication this session")
        }
        Divider()
        Button("Refresh All") {
            Task {
                if let environment = bootstrap.environment {
                    await bootstrap.log.record(.lifecycle(.refreshRequested))
                    await environment.ownerFlows.home.refreshAll()
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
