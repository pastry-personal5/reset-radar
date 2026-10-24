import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarProviderAdapters

struct SetupRig {
    let home: URL
    let root: URL
    let settings: URL
    let catalog: ProviderAccountCatalogStore
    let installer: StatusLineHelperInstaller
    let configurator: ClaudeCodeConfigurator

    init(
        _ home: URL, environment: [String: String] = ["PATH": "/usr/bin:/bin"],
        managed: URL? = nil, installHelper: Bool = true
    ) throws {
        self.home = home
        root = home.appending(path: "ResetRadar")
        precondition(mkdir(root.path, 0o700) == 0)
        precondition(mkdir(home.appending(path: ".claude").path, 0o700) == 0)
        settings = home.appending(path: ".claude/settings.json")
        let embedded = try writeExecutable(
            "#!/bin/sh\nprintf '\(StatusLineHelperVersion.current)\\n'\n",
            at: home.appending(path: "embedded"))
        installer = StatusLineHelperInstaller(embeddedHelper: embedded, rootDirectory: root)
        if installHelper { try installer.install() }
        catalog = ProviderAccountCatalogStore(directoryURL: root)
        let paths = ClaudeCodeConfiguratorPaths(
            homeDirectory: home, rootDirectory: root, settingsURL: settings,
            managedSettingsURL: managed, environment: environment)
        configurator = ClaudeCodeConfigurator(paths: paths, installer: installer, catalog: catalog)
    }

    func write(_ text: String) throws {
        try Data(text.utf8).write(to: settings)
        precondition(chmod(settings.path, 0o600) == 0)
    }

    func text() throws -> String { try String(contentsOf: settings, encoding: .utf8) }

    func install() async throws -> ConfigurationPreview {
        let option = try #require(try await configurator.discover().first)
        let preview = try await configurator.preview(optionID: option.id, intent: .add)
        try await configurator.apply(preview)
        return preview
    }

    var restoreFileExists: Bool {
        FileManager.default.fileExists(
            atPath: root.appending(path: "claude-setup/\(StatusLineRestoreRecord.fileName)").path)
    }
    var composeFileExists: Bool {
        FileManager.default.fileExists(atPath: root.appending(path: ComposeRecord.fileName).path)
    }
}
