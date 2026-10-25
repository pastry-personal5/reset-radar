import SwiftUI

struct RootView: View {
    var startupFailed = false

    var body: some View {
        if startupFailed {
            ContentUnavailableView(
                "Reset Radar could not start", systemImage: "exclamationmark.triangle",
                description: Text("Open Settings to review signing, Keychain, and source setup."))
        } else {
            Text("Reset Radar")
        }
    }
}
