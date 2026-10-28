import Foundation
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.openURL) private var openURL
    private let repository = URL(string: "https://github.com/pastry-personal5/reset-radar")!
    private let issues = URL(string: "https://github.com/pastry-personal5/reset-radar/issues/new")!

    var body: some View {
        List {
            Section("Reset Radar") {
                Text(
                    "Know your Codex and Claude Code allowance usage at a glance. Reset Radar "
                        + "keeps Percentage Used and reset times clear across your Mac, iPhone, "
                        + "iPad, and Apple Watch.")
            }
            Section("License") {
                Text("Apache License 2.0")
            }
            Section("Feedback") {
                Button {
                    openURL(repository)
                } label: {
                    Label("GitHub", systemImage: "arrow.up.right")
                }
                Button {
                    openURL(issues)
                } label: {
                    Label("Report an Issue", systemImage: "arrow.up.right")
                }
                Button("Support Reset Radar") { openURL(repository) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .navigationTitle("About")
    }
}
