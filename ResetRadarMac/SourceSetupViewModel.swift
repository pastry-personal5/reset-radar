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
    private var selections: [Selection] = []

    init(homeDirectory: URL = .homeDirectory, workingDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.workingDirectory = workingDirectory
    }

    func update(_ selections: [Selection]) {
        self.selections = Array(selections.prefix(AccountCatalog.maximumCodexAccounts))
    }

    func contexts() -> [CodexDiscoveryContext] {
        let environment = ProcessInfo.processInfo.environment
        return selections.map { selection in
            CodexDiscoveryContext(
                explicitExecutablePath: selection.executablePath, loginShellURL: nil,
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
    @Published private(set) var message: String?

    private let selections: CodexDiscoverySelections
    private let configure: ConfigureSources
    private let catalog: (any AccountCatalogStore)?
    private let aliases: UpdateAccountAlias?
    private let publication: PublicationDriver?

    init(
        selections: CodexDiscoverySelections, configure: ConfigureSources,
        catalog: (any AccountCatalogStore)? = nil, aliases: UpdateAccountAlias? = nil,
        publication: PublicationDriver? = nil
    ) {
        self.selections = selections
        self.configure = configure
        self.catalog = catalog
        self.aliases = aliases
        self.publication = publication
    }

    func loadConfiguredAccounts() async {
        guard let catalog else {
            configuredAccounts = []
            return
        }
        do {
            configuredAccounts = try await catalog.loadCatalog().accounts
        } catch {
            message = "Configured sources could not be read. Quit and reopen Reset Radar."
        }
    }

    func discoverCodex() async {
        let values = codexHomes.compactMap { path -> CodexDiscoverySelections.Selection? in
            guard path.hasPrefix("/") else { return nil }
            return CodexDiscoverySelections.Selection(
                codexHome: URL(fileURLWithPath: path),
                executablePath: codexExecutable.isEmpty ? nil : codexExecutable)
        }
        await selections.update(values)
        await discover(.codex)
    }

    func discoverClaudeCode() async { await discover(.claudeCode) }

    func prepare(_ option: ConfigurationOption, intent: ConfigurationIntent = .add) async {
        do {
            preview = try await configure.preview(
                for: option.product, optionID: option.id, intent: intent)
            message = nil
        } catch {
            message =
                "The source preview could not be prepared. "
                + "Existing unsafe settings were left unchanged."
        }
    }

    func confirmPreview() async -> Bool {
        guard let preview else { return false }
        do {
            try await configure.apply(preview, confirmed: true)
            self.preview = nil
            await loadConfiguredAccounts()
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
            await loadConfiguredAccounts()
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
        do {
            options = try await configure.discover(for: product)
            message = options.isEmpty ? "No safe source was found." : nil
        } catch {
            options = []
            message = "Source discovery failed without changing configuration."
        }
    }
}
