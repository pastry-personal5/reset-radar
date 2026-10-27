import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarUI
import SwiftUI

struct MacDetailWindow: Identifiable {
    enum Identity: Hashable {
        case standard(AccountWindow.StandardWindow)
        case additional(WindowID)
    }

    let id: Identity
    let label: String
    let window: AllowanceWindow?
    let ambiguous: Bool

    static func ordered(account: AccountMetadata, snapshot: UsageSnapshot?, now: Date) -> [Self] {
        let standards = AccountWindow.StandardWindow.allCases.map { standard -> Self in
            guard let snapshot else {
                return Self(
                    id: .standard(standard), label: standard.label,
                    window: nil, ambiguous: false)
            }
            let (resolution, _) = AccountWindowResolver.resolve(
                AccountWindow(accountID: account.id, window: standard),
                in: snapshot, now: now)
            switch resolution {
            case .window(let window):
                return Self(
                    id: .standard(standard), label: standard.label,
                    window: window, ambiguous: false)
            case .ambiguous:
                return Self(
                    id: .standard(standard), label: standard.label,
                    window: nil, ambiguous: true)
            case .unavailable:
                return Self(
                    id: .standard(standard), label: standard.label,
                    window: nil, ambiguous: false)
            }
        }
        let extras = (snapshot?.windows ?? []).filter { window in
            guard window.accountID == account.id else { return false }
            return !window.isDefaultLimit
                || !AccountWindow.StandardWindow.allCases.contains {
                    $0.durationMinutes == window.durationMinutes
                }
        }.sorted { left, right in
            let leftLabel = left.label ?? left.limitID
            let rightLabel = right.label ?? right.limitID
            return leftLabel.localizedStandardCompare(rightLabel) == .orderedAscending
        }.map { window in
            Self(
                id: .additional(window.id), label: window.displayLabel,
                window: window, ambiguous: false)
        }
        return standards + extras
    }
}

extension AccountWindow.StandardWindow {
    fileprivate var label: String {
        switch self {
        case .fiveHour: "Five-hour"
        case .weekly: "Weekly"
        }
    }
}

extension AllowanceWindow {
    fileprivate var displayLabel: String {
        if let label, !label.isEmpty { return label }
        if let durationMinutes { return "\(durationMinutes)-minute window" }
        return "Additional window"
    }
}

struct MacAccountDetailsView: View {
    let account: AccountMetadata
    @ObservedObject var model: HomeViewModel
    @ObservedObject var messages: GlobalMessageCenter
    let focusedWindow: AccountWindow.StandardWindow?
    @State private var editingAlias = false
    @State private var alias = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    let details = MacDetailWindow.ordered(
                        account: account, snapshot: model.snapshot, now: timeline.date)
                    if let nextReset = nextReset(in: details, now: timeline.date) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Executive Summary").font(.headline)
                            Text(
                                nextReset.date.formatted(
                                    date: .abbreviated, time: .shortened)
                            )
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .minimumScaleFactor(0.65)
                            Text(nextReset.label).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("executiveSummary")
                    }
                    ForEach(details) { item in
                        MacWindowDetailsCard(
                            account: account, source: model.snapshot?.source(for: account.id),
                            detail: item, model: model, now: timeline.date,
                            emphasized: item.id == focusedWindow.map { .standard($0) })
                    }
                    provenance
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { alias = account.alias?.value ?? "" }
        .onChange(of: account.alias?.value) { _, value in alias = value ?? "" }
    }

    private func nextReset(in details: [MacDetailWindow], now: Date) -> NextReset? {
        details.compactMap { detail -> NextReset? in
            guard case .standard(let standard) = detail.id, !detail.ambiguous,
                let date = detail.window?.resetsAt, date > now
            else { return nil }
            return NextReset(date: date, window: standard)
        }.min { left, right in
            if left.date == right.date { return left.window == .fiveHour }
            return left.date < right.date
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    if editingAlias {
                        HStack {
                            TextField("Account Alias", text: $alias)
                                .onSubmit { saveAlias() }
                            Button("Save") { saveAlias() }
                            Button("Cancel") { editingAlias = false }
                        }
                    } else {
                        Button(account.effectiveDisplayLabel) {
                            alias = account.alias?.value ?? ""
                            editingAlias = true
                        }
                        .buttonStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .accessibilityHint("Edit Account Alias")
                    }
                    Text(account.product == .codex ? "Codex" : "Claude Code")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await model.refreshAccount(account.id) }
                }
                .disabled(model.isRefreshing)
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if let delivery = model.aliasDelivery {
                Text(delivery.rawValue)
                    .font(.callout)
                    .foregroundStyle(delivery == .failed ? .orange : .secondary)
            }
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Provenance and synchronization")
                .font(.headline)
            if let source = model.snapshot?.source(for: account.id) {
                LabeledContent("Acquisition source", value: source.kind.displayName)
                LabeledContent("Source compatibility") {
                    Text(
                        source.state == .incompatible
                            ? "Incompatible" : "No incompatibility reported")
                }
                DisclosureGroup("Technical details") {
                    LabeledContent("Source version", value: source.version)
                }
            } else {
                Text("No source report is available for this account.")
                    .foregroundStyle(.secondary)
            }
            if let lastPublishedAt = messages.lastPublishedAt {
                LabeledContent("Collector Mac publication") {
                    let localTime = lastPublishedAt.formatted(
                        date: .abbreviated, time: .shortened)
                    Text("Last published \(localTime)")
                }
            } else {
                LabeledContent("Collector Mac publication", value: "No successful publication yet")
            }
            Text("Last Synced is shown on receiving devices after they accept a snapshot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func saveAlias() {
        Task {
            await model.updateAlias(accountID: account.id, input: alias)
            let saveFinished =
                model.aliasDelivery == .available || model.aliasDelivery == .localOnly
            if model.message == nil && saveFinished {
                editingAlias = false
            }
        }
    }
}

extension SourceKind {
    fileprivate var displayName: String {
        switch self {
        case .codexAppServer: "Codex app-server"
        case .claudeCodeStatusLine: "Claude Code status line"
        }
    }
}

private struct MacWindowDetailsCard: View {
    let account: AccountMetadata
    let source: AccountSource?
    let detail: MacDetailWindow
    @ObservedObject var model: HomeViewModel
    let now: Date
    let emphasized: Bool
    @State private var remindersEnabled: Bool?

    private var display: MacAllowanceDisplay {
        guard let window = detail.window else { return .unavailable }
        return .resolve(window: window, source: source, product: account.product, now: now)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            MacAllowanceFace(
                display: display, label: detail.label,
                accessibilityLabel: ringAccessibilityLabel
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.label).font(.headline)
                LabeledContent("Percentage Used", value: display.percentageText ?? "—")
                LabeledContent("Data state", value: display.statusText)
                if let observation = detail.window?.observation {
                    LabeledContent("Last Updated") {
                        Text(observation.observedAt, style: .relative)
                    }
                } else {
                    LabeledContent("Last Updated", value: "No reading")
                }
                if let resetsAt = detail.window?.resetsAt {
                    LabeledContent("Reset Time") {
                        VStack(alignment: .trailing) {
                            Text(resetsAt, style: .relative)
                            Text(resetsAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    LabeledContent("Reset Time", value: "Not reported")
                }
                reminderToggle
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    emphasized ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: emphasized ? 2 : 1)
        }
        .task(id: selection.versionedID) {
            remindersEnabled = await model.notificationOptIn(selection)
        }
    }

    private var selection: WindowSelection {
        switch detail.id {
        case .standard(let standard):
            .standard(AccountWindow(accountID: account.id, window: standard))
        case .additional(let windowID): .additional(windowID)
        }
    }

    @ViewBuilder private var reminderToggle: some View {
        if detail.window != nil, let source, source.state != .incompatible {
            Toggle(
                "Reset Reminder",
                isOn: Binding(
                    get: { remindersEnabled ?? false },
                    set: { enabled in
                        remindersEnabled = enabled
                        Task { _ = await model.setNotificationOptIn(selection, enabled: enabled) }
                    })
            )
            .font(.callout)
        }
    }

    private var explanation: String {
        if detail.ambiguous {
            return "Multiple default windows were reported for this duration; no reading is shown."
        }
        switch display.state {
        case .current:
            return "The provider reading is current."
        case .resetAwaitingRefresh:
            return "The reported reset passed. Waiting for a new provider reading."
        case .unavailable:
            switch source?.state {
            case .signedOut: return "The source is signed out. Sign in, then refresh."
            case .sourceOffline:
                return "The source is offline. The last valid reading remains on this Mac."
            case .incompatible: return "The installed source is incompatible with this version."
            case .reporting, .unavailable, .none:
                return "No provider reading is available for this window."
            }
        case .stale(let reason):
            switch reason {
            case .sourceNotReporting:
                switch source?.state {
                case .signedOut: return "The source is signed out; this reading may be old."
                case .sourceOffline: return "The source is offline; this reading may be old."
                case .incompatible: return "The source is incompatible; this reading may be old."
                case .reporting, .unavailable, .none:
                    return "The source is not reporting; this reading may be old."
                }
            case .retained: return "This reading was retained while waiting for a new report."
            case .observationOld: return "The last reading is older than the current-data window."
            case .observationInFuture: return "The source clock is ahead of this Mac."
            }
        }
    }

    private var ringAccessibilityLabel: String {
        let value = display.percentageText ?? "No percentage available"
        return "\(account.effectiveDisplayLabel), \(detail.label), \(value), \(display.statusText)"
    }
}
