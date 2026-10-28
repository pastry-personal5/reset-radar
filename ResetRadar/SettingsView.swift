import ResetRadarApplication
import ResetRadarUI
import SwiftUI
import UIKit

/// iOS Settings: Pairing & Sync, notification and (iPhone) Live Activity authorization status,
/// Privacy & Data, Diagnostics, and About. Per-window controls wait for the scheduling drivers.
struct SettingsView: View {
    @ObservedObject var environment: ReaderEnvironment
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PairingSyncView(environment: environment)
                } label: {
                    LabeledContent(
                        "Pairing & Sync", value: PairingSyncText.status(environment.pairing))
                }
                .accessibilityIdentifier("settings.pairingSync")
            }
            Section {
                LabeledContent(
                    "Notifications",
                    value: Self.authorization(environment.notificationAuthorization))
                if environment.notificationAuthorization == .denied {
                    Button("Open Notification Settings") {
                        guard
                            let url = URL(
                                string: UIApplication.openNotificationSettingsURLString)
                        else { return }
                        openURL(url)
                    }
                }
                if let enabled = environment.liveActivitiesEnabled {
                    LabeledContent("Live Activities", value: enabled ? "Allowed" : "Not allowed")
                }
                LabeledContent(
                    "Background Refresh",
                    value: environment.backgroundRefreshAvailable ? "Registered" : "Unavailable")
            } header: {
                Text("System Permissions")
            } footer: {
                Text(
                    "Reset reminders are device-local. Live Activity availability depends on this"
                        + " device."
                )
            }
            Section {
                NavigationLink("Privacy & Data") { PrivacyView() }
                NavigationLink("Diagnostics") { DiagnosticsView(environment: environment) }
                NavigationLink("About") { AboutView() }
            }
        }
        .navigationTitle("Settings")
    }

    static func authorization(_ value: NotificationAuthorization) -> String {
        switch value {
        case .authorized: "Allowed"
        case .provisional: "Quietly allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested"
        case .failed: "Unavailable"
        case .unknown: "Unknown"
        }
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text(
                    "Reset Radar on this device contacts only the encrypted Reset Radar relay. "
                        + "It never contacts Codex or Claude Code and holds no provider "
                        + "credentials.")
                Text(
                    "Pairing secrets stay in this device’s Keychain and are not synchronized. "
                        + "Usage readings stay in Reset Radar’s local storage until Forget Mac.")
                Text(
                    "The relay stores encrypted snapshots and device profiles plus opaque "
                        + "delivery metadata. Reset Radar shows percentage used as each provider "
                        + "reports it and keeps no usage history.")
            }
        }
        .navigationTitle("Privacy & Data")
    }
}

private struct DiagnosticsView: View {
    @ObservedObject var environment: ReaderEnvironment
    @State private var confirmExport = false
    @State private var exportURL: URL?
    @State private var exportFailed = false

    var body: some View {
        List {
            Section("Delivery") {
                LabeledContent(
                    "Relay", value: ReaderVocabulary.transport(environment.details.transport))
                LabeledContent(
                    "Collector Mac",
                    value: ReaderVocabulary.macPublication(environment.details.macLive))
                LabeledContent("Last Synced") {
                    if let synced = environment.details.lastSyncedAt {
                        Text(synced.formatted(date: .abbreviated, time: .standard))
                    } else {
                        Text("Not yet")
                    }
                }
            }
            Section {
                Button("Prepare Redacted Export") { confirmExport = true }
                if let exportURL {
                    ShareLink("Share Export", item: exportURL)
                }
                if exportFailed {
                    Text("The export could not be prepared.").foregroundStyle(.secondary)
                }
            } footer: {
                Text(
                    "The export contains only event categories, status classes, and times. It "
                        + "never contains pairing secrets, usage readings, or account names.")
            }
        }
        .navigationTitle("Diagnostics")
        .confirmationDialog(
            "Prepare a redacted diagnostics export?", isPresented: $confirmExport,
            titleVisibility: .visible
        ) {
            Button("Prepare Export") {
                Task {
                    do {
                        exportURL = try await environment.exportDiagnosticsFile()
                        exportFailed = false
                    } catch {
                        exportURL = nil
                        exportFailed = true
                    }
                }
            }
        }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            LabeledContent("Version", value: Self.version)
            LabeledContent("License", value: "Apache-2.0")
            Text(
                "A personal Reset Radar reader for the Codex and Claude Code allowance windows "
                    + "your Collector Mac publishes.")
        }
        .navigationTitle("About")
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
