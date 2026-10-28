import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters

actor CodexDiscoverySelections: CodexDiscoveryContextProviding {
    struct Selection: Sendable, Equatable {
        let codexHome: URL
        let executablePath: String?
    }

    private let homeDirectory: URL
    private let workingDirectory: URL
    private let loginShellURL: URL?
    private var selections: [Selection] = []

    init(homeDirectory: URL = .homeDirectory, workingDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.workingDirectory = workingDirectory
        if let shell = getpwuid(getuid())?.pointee.pw_shell {
            let path = String(cString: shell)
            loginShellURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
        } else {
            loginShellURL = nil
        }
    }

    func update(_ selections: [Selection]) {
        self.selections = selections
    }

    func contexts() -> [CodexDiscoveryContext] {
        let environment = ProcessInfo.processInfo.environment
        return selections.map { selection in
            CodexDiscoveryContext(
                explicitExecutablePath: selection.executablePath, loginShellURL: loginShellURL,
                environment: [
                    "HOME": homeDirectory.path,
                    "USER": environment["USER"] ?? NSUserName(),
                    "LANG": environment["LANG"] ?? "en_US.UTF-8",
                    "PATH": environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                    "CODEX_HOME": selection.codexHome.path,
                ], workingDirectoryURL: workingDirectory)
        }
    }
}

@MainActor
final class SourceSetupViewModel: ObservableObject {
    @Published var codexHomes = [String]()
    @Published var codexExecutable = ""
    @Published private(set) var options = [ConfigurationOption]()
    @Published private(set) var preview: ConfigurationPreview?
    @Published private(set) var configuredAccounts = [AccountMetadata]()
    @Published private(set) var codexHomeFolders = [AccountID: String]()
    @Published private(set) var message: String?

    private let selections: CodexDiscoverySelections
    private let configure: ConfigureSources
    private let catalog: (any AccountCatalogStore)?
    private let codexConfigurations: ProviderAccountCatalogStore?
    private let aliases: UpdateAccountAlias?
    private let publication: PublicationDriver?
    private let updates: HomeSnapshotUpdates?

    init(
        selections: CodexDiscoverySelections, configure: ConfigureSources,
        catalog: (any AccountCatalogStore)? = nil, aliases: UpdateAccountAlias? = nil,
        publication: PublicationDriver? = nil,
        codexConfigurations: ProviderAccountCatalogStore? = nil,
        updates: HomeSnapshotUpdates? = nil
    ) {
        self.selections = selections
        self.configure = configure
        self.catalog = catalog
        self.codexConfigurations = codexConfigurations
        self.aliases = aliases
        self.publication = publication
        self.updates = updates
    }

    func loadConfiguredAccounts() async {
        guard let catalog else {
            configuredAccounts = []
            codexHomeFolders = [:]
            return
        }
        do {
            configuredAccounts = try await catalog.loadCatalog().accounts
            var homes = [AccountID: String]()
            if let codexConfigurations {
                for account in configuredAccounts where account.product == .codex {
                    do {
                        let configuration = try await codexConfigurations.loadCodexConfiguration(
                            accountID: account.id)
                        homes[account.id] = configuration.environment["CODEX_HOME"]
                    } catch {
                        message = "A configured Codex home folder could not be read."
                    }
                }
            }
            codexHomeFolders = homes
        } catch {
            message = "Configured sources could not be read. Quit and reopen Reset Radar."
        }
    }

    func discoverCodex() async {
        var values = [CodexDiscoverySelections.Selection]()
        for path in codexHomes {
            guard path == path.trimmingCharacters(in: .whitespacesAndNewlines) else {
                cancelPendingSetup()
                message = "Remove leading or trailing whitespace from the Home Folder."
                return
            }
            guard path.hasPrefix("/") else {
                cancelPendingSetup()
                message = "Enter an absolute Home Folder."
                return
            }
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                cancelPendingSetup()
                message = "The Home Folder does not exist or is not a directory."
                return
            }
            values.append(
                CodexDiscoverySelections.Selection(
                    codexHome: URL(fileURLWithPath: path),
                    executablePath: codexExecutable.isEmpty ? nil : codexExecutable))
        }
        await selections.update(values)
        await discover(.codex)
    }

    func discoverClaudeCode() async { await discover(.claudeCode) }

    func cancelPendingSetup() {
        options = []
        preview = nil
        message = nil
    }

    func prepare(_ option: ConfigurationOption, intent: ConfigurationIntent = .add) async {
        preview = nil
        do {
            preview = try await configure.preview(
                for: option.product, optionID: option.id, intent: intent)
            message = nil
        } catch {
            message = Self.previewFailureMessage(error, product: option.product)
        }
    }

    private static func previewFailureMessage(_ error: any Error, product: ProductID) -> String {
        if product == .claudeCode {
            if let reason = error as? ClaudeCodeConfiguratorError {
                switch reason {
                case .helperNotCurrent:
                    return "The Claude Code helper could not be installed or verified. "
                        + "Claude Code settings were not changed."
                case .settingsUnsafe:
                    return "Claude Code settings could not be read safely. "
                        + "Check the file and its permissions before retrying."
                default:
                    break
                }
            }
            if error as? ConfigureSourcesError == .unsafeExistingConfiguration {
                return "The existing Claude Code status line cannot be composed safely. "
                    + "Reset Radar accepts a trusted executable path or a simple "
                    + "bash $HOME/<script> command inside your home folder. "
                    + "Claude Code settings were not changed."
            }
        }
        return "The source preview could not be prepared. Configuration was not changed."
    }

    func confirmPreview(alias: String = "") async -> Bool {
        guard let preview else { return false }
        if preview.product == .codex, !alias.isEmpty {
            do {
                let validated = try AccountAlias(validating: alias)
                guard
                    !configuredAccounts.contains(where: {
                        $0.effectiveDisplayLabel == validated.value
                    })
                else {
                    message = "The alias is already used by another source."
                    return false
                }
            } catch {
                message = "The alias must be unique, visible text no longer than 32 bytes."
                return false
            }
        }
        let previousIDs = Set(configuredAccounts.map(\.id))
        do {
            try await configure.apply(preview, confirmed: true)
            self.preview = nil
            options = []
            await loadConfiguredAccounts()
            let addedAccount = configuredAccounts.first {
                $0.product == .codex && !previousIDs.contains($0.id)
            }
            if preview.product == .codex, !alias.isEmpty, let added = addedAccount {
                guard let catalog else {
                    message = "Source saved, but its alias could not be saved."
                    return true
                }
                do {
                    _ = try await catalog.setAlias(
                        accountID: added.id, alias: AccountAlias(validating: alias))
                    await loadConfiguredAccounts()
                } catch {
                    message = "Source saved, but its alias could not be saved."
                    return true
                }
            }
            message = "Source configuration saved."
            return true
        } catch {
            message = "Source configuration was not changed. Review the preview and try again."
            return false
        }
    }

    func remove(_ accountID: AccountID, product: ProductID, confirmed: Bool) async -> Bool {
        do {
            try await configure.remove(accountID, product: product, confirmed: confirmed)
            await loadConfiguredAccounts()
            message = "Source removed."
            return true
        } catch {
            message = "The source was not removed."
            return false
        }
    }

    func restoreClaudeCode(confirmed: Bool) async -> Bool {
        do {
            try await configure.restore(.claudeCode, confirmed: confirmed)
            message = "The prior Claude Code status-line setting was restored."
            return true
        } catch {
            message = "The prior status-line setting could not be restored safely."
            return false
        }
    }

    func updateAlias(accountID: AccountID, input: String) async {
        guard let aliases else { return }
        do {
            let update = try await aliases.update(accountID: accountID, input: input)
            if let updates {
                await updates.aliasDidChange()
            } else {
                await loadConfiguredAccounts()
            }
            if let snapshot = update.snapshot {
                await publication?.collected(
                    CollectResult(snapshot: snapshot, change: update.change))
            }
            message = nil
        } catch {
            message = "The alias must be unique, visible text no longer than 32 bytes."
        }
    }

    private func discover(_ product: ProductID) async {
        preview = nil
        do {
            options = try await configure.discover(for: product)
            message = options.isEmpty ? "No safe source was found." : nil
        } catch {
            options = []
            message = "Source discovery failed without changing configuration."
        }
    }
}
