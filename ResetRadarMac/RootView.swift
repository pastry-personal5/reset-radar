import SwiftUI

struct RootView: View {
    let environment: MacEnvironment?
    @ObservedObject var messages: GlobalMessageCenter
    var startupFailed = false

    var body: some View {
        if startupFailed {
            VStack(spacing: 0) {
                ContentUnavailableView(
                    "Reset Radar could not start", systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Open Settings to review signing, Keychain, and source setup.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                GlobalMessagesPane(messages: messages)
            }
        } else if let environment {
            MacMainView(model: environment.ownerFlows.home, messages: messages)
        } else {
            VStack(spacing: 0) {
                ProgressView("Starting collector…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                GlobalMessagesPane(messages: messages)
            }
        }
    }
}
