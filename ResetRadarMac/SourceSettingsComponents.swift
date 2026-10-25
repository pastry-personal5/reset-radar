import Foundation
import ResetRadarApplication
import ResetRadarDomain
import SwiftUI

struct SettingsCardColumn<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary)
        }
    }
}

struct CodexSourceRow: View {
    let account: AccountMetadata
    let homeFolder: String?
    @ObservedObject var model: SourceSetupViewModel
    let changeHome: () -> Void
    let remove: () -> Void
    @State private var alias: String

    init(
        account: AccountMetadata, homeFolder: String?, model: SourceSetupViewModel,
        changeHome: @escaping () -> Void, remove: @escaping () -> Void
    ) {
        self.account = account
        self.homeFolder = homeFolder
        self.model = model
        self.changeHome = changeHome
        self.remove = remove
        _alias = State(initialValue: account.alias?.value ?? "")
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("Alias", text: $alias)
                .frame(width: 190)
            Text(homeFolder ?? "Unavailable")
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(homeFolder ?? "Home Folder unavailable")
            HStack {
                Button("Change Home", action: changeHome)
                Button("Save Alias") {
                    Task { await model.updateAlias(accountID: account.id, input: alias) }
                }
                Button("Remove", role: .destructive, action: remove)
            }
            .frame(width: 260, alignment: .trailing)
        }
        .onChange(of: account.alias?.value) { _, value in alias = value ?? "" }
    }
}

struct SourceLaunchDetails: View {
    let launch: ConfigurationLaunchPreview

    var body: some View {
        VStack(alignment: .leading) {
            if let codexHome = launch.environment.first(where: { $0.key == .codexHome }) {
                Text("CODEX_HOME: \(codexHome.value)")
                    .font(.headline)
                    .wrapsInMainPane()
            }
            Text(launch.executablePath)
                .font(.body.monospaced())
                .wrapsInMainPane()
            if let interpreter = launch.interpreterPath {
                Text("Interpreter: \(interpreter)")
                    .font(.caption.monospaced())
                    .wrapsInMainPane()
            }
            ForEach(launch.environment.filter { $0.key != .codexHome }, id: \.key) { value in
                Text("\(value.key.rawValue)=\(value.value)")
                    .font(.caption.monospaced())
                    .wrapsInMainPane()
            }
        }
    }
}

struct ConfiguredSourceRow: View {
    let account: AccountMetadata
    @ObservedObject var model: SourceSetupViewModel
    let remove: () -> Void
    @State private var alias: String

    init(account: AccountMetadata, model: SourceSetupViewModel, remove: @escaping () -> Void) {
        self.account = account
        self.model = model
        self.remove = remove
        _alias = State(initialValue: account.alias?.value ?? "")
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(account.effectiveDisplayLabel)
                Spacer()
                Text(account.product == .codex ? "Codex" : "Claude Code")
                    .foregroundStyle(.secondary)
                Button("Remove", role: .destructive, action: remove)
            }
            HStack {
                TextField("Alias", text: $alias)
                Button("Save Alias") {
                    Task { await model.updateAlias(accountID: account.id, input: alias) }
                }
            }
        }
    }
}
