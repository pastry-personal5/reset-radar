import AppKit
import Combine
import ResetRadarApplication
import SwiftUI

enum PublicationFailureCopy {
    static func text(for outcome: PublishOutcome) -> String? {
        switch outcome {
        case .stopped(let reason):
            switch reason {
            case .snapshotConflict:
                "Publication stopped: the relay reported a publisher conflict."
            case .authorizationRequired:
                "Publication stopped: the relay rejected the write token."
            case .payloadRejected:
                "Publication stopped: the snapshot payload was rejected."
            case .incompatible:
                "Publication stopped: the snapshot or relay protocol is incompatible."
            }
        case .envelopeTooLarge:
            "Publication stopped: the encrypted snapshot exceeds the relay size limit."
        case .secretsUnavailable:
            "Publication paused: relay secrets could not be read."
        case .paused:
            "Publication paused: relay setup is inactive or local publisher state is unavailable. "
                + "Local readings remain on this Mac; set up relay in Settings → Relay & Pairing."
        case .published, .notDue, .backoff:
            nil
        }
    }
}

@MainActor
final class GlobalMessageCenter: ObservableObject {
    enum Tone: Sendable, Equatable {
        case information
        case success
        case attention
    }

    struct Entry: Identifiable, Sendable, Equatable {
        let id: Int
        let text: String
        let tone: Tone
    }

    static let maximumEntries = 200

    @Published private(set) var entries = [Entry]()
    private var nextID = 0
    private var subscriptions = Set<AnyCancellable>()
    private let log: MacRotatingLog?

    init(log: MacRotatingLog? = nil) {
        self.log = log
    }

    func post(_ text: String, tone: Tone = .information) {
        guard !text.isEmpty else { return }
        nextID += 1
        entries.append(Entry(id: nextID, text: text, tone: tone))
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
    }

    func reportPublication(_ event: PublicationStatusEvent) {
        if let log { Task { await log.record(.publication(event)) } }
        switch event {
        case .blocked(let outcome):
            guard let text = PublicationFailureCopy.text(for: outcome) else { return }
            post(text, tone: .attention)
        case .recovered:
            post("Publication resumed after a blocked attempt.", tone: .success)
        }
    }

    func observe(_ flows: OwnerFlowModels) {
        subscriptions.removeAll()
        observe(flows.home.$message)
        observe(flows.general.$errorMessage, tone: .attention)
        observe(flows.sources.$message)
        observe(flows.relay.$message)
        observe(flows.pairing.$message)
        observe(flows.devices.$message)
        flows.recovery.$signing
            .removeDuplicates()
            .sink { [weak self] outcome in
                guard case .changedTeam = outcome else { return }
                Task { @MainActor in
                    self?.post(
                        "The signing identity changed. Review Signing and Keychain in Settings.",
                        tone: .attention)
                }
            }
            .store(in: &subscriptions)
        flows.recovery.$secrets
            .removeDuplicates()
            .sink { [weak self] availability in
                guard availability == .secretsUnavailable else { return }
                Task { @MainActor in
                    self?.post(
                        "Keychain secrets are unavailable. Unlock the login keychain and retry.",
                        tone: .attention)
                }
            }
            .store(in: &subscriptions)
    }

    private func observe<P: Publisher>(
        _ publisher: P, tone: Tone = .information
    ) where P.Output == String?, P.Failure == Never {
        publisher
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] text in
                Task { @MainActor in self?.post(text, tone: tone) }
            }
            .store(in: &subscriptions)
    }
}

struct GlobalMessagesPane: View {
    @ObservedObject var messages: GlobalMessageCenter

    private let messageFontSize = NSFont.systemFontSize - 2
    private let messageAreaHeight: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            Text("Global Messages")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
                .padding(.leading, 10)
                .zIndex(1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if messages.entries.isEmpty {
                            Text("No messages yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(messages.entries) { entry in
                            Text(entry.text)
                                .foregroundStyle(color(for: entry.tone))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: messageFontSize))
                .frame(height: messageAreaHeight)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
                .accessibilityIdentifier("globalMessagesArea")
                .onAppear { scrollToLatest(using: proxy) }
                .onChange(of: messages.entries.last?.id) { _, _ in
                    scrollToLatest(using: proxy)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("globalMessagesPane")
    }

    private func color(for tone: GlobalMessageCenter.Tone) -> Color {
        switch tone {
        case .information: .primary
        case .success: .green
        case .attention: .orange
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = messages.entries.last?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
    }
}
