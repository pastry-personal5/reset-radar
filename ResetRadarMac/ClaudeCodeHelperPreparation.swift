import Foundation
import ResetRadarProviderAdapters

enum ClaudeCodeHelperPreparation {
    @MainActor
    static func onLaunch(rootDirectory: URL, messages: GlobalMessageCenter) {
        let embedded = Bundle.main.bundleURL.appending(
            path: "Contents/Helpers/ResetRadarStatusLine")
        let installer = StatusLineHelperInstaller(
            embeddedHelper: embedded, rootDirectory: rootDirectory)
        do {
            try installer.ensureCurrent()
        } catch {
            messages.post("Claude Code helper could not be verified.", tone: .attention)
        }
    }
}
