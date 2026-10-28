import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTransport

private func hexadecimal(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

@MainActor
final class RelaySetupViewModel: ObservableObject {
    @Published var origin = ""
    @Published private(set) var writeDigest: String?
    @Published private(set) var adminDigest: String?
    @Published private(set) var isPending = false
    @Published private(set) var message: String?
    @Published private(set) var lifecycle = RelayLifecycle.notConfigured
    @Published private(set) var endpoint: URL?

    private let setup: SetUpRelay
    private let publication: PublicationDriver
    private let refreshManualRequests: @MainActor () async -> Void
    private let pauseManualRequests: @MainActor () async -> Void
    private let resumeManualRequests: @MainActor () async -> Void
    private let runningTeamIdentifier: () -> String?
    private let recordTeamIdentifier: (String) -> Void
    private let publisher: (any PublisherStore)?
    init(
        setup: SetUpRelay, publication: PublicationDriver,
        refreshManualRequests: @escaping @MainActor () async -> Void = {},
        pauseManualRequests: @escaping @MainActor () async -> Void = {},
        resumeManualRequests: @escaping @MainActor () async -> Void = {},
        runningTeamIdentifier: @escaping () -> String? = { nil },
        recordTeamIdentifier: @escaping (String) -> Void = { _ in },
        publisher: (any PublisherStore)? = nil
    ) {
        self.setup = setup
        self.publication = publication
        self.refreshManualRequests = refreshManualRequests
        self.pauseManualRequests = pauseManualRequests
        self.resumeManualRequests = resumeManualRequests
        self.runningTeamIdentifier = runningTeamIdentifier
        self.recordTeamIdentifier = recordTeamIdentifier
        self.publisher = publisher
    }

    func load() async {
        guard let state = try? await publisher?.load() else { return }
        lifecycle = state.lifecycle
        endpoint = state.endpoint
        isPending = state.lifecycle == .setupPending
        origin = state.endpoint?.absoluteString ?? origin
        if state.lifecycle == .setupPending, let digests = await setup.pendingDigests() {
            writeDigest = hexadecimal(digests.writeToken)
            adminDigest = hexadecimal(digests.adminToken)
        } else {
            writeDigest = nil
            adminDigest = nil
        }
    }

    func prepare() async {
        guard let endpoint = URL(string: origin), OriginGuard.accepts(endpoint) else {
            message = "Enter the canonical HTTPS origin for the included workers.dev relay."
            return
        }
        await publication.setSuspended(true)
        await pauseManualRequests()
        do {
            let digests = try await setup.prepare(endpoint: endpoint)
            await refreshManualRequests()
            writeDigest = hexadecimal(digests.writeToken)
            adminDigest = hexadecimal(digests.adminToken)
            if let team = runningTeamIdentifier() { recordTeamIdentifier(team) }
            isPending = true
            await load()
            message = "Install both digests as Worker secrets, then activate."
        } catch {
            message = "Relay preparation paused safely. Try again to resume it."
        }
    }

    @discardableResult
    func activate() async -> Bool {
        switch await setup.activate() {
        case .active:
            isPending = false
            writeDigest = nil
            adminDigest = nil
            message = "Relay setup is active."
            await publication.setSuspended(false)
            await refreshManualRequests()
            await resumeManualRequests()
            await publication.trigger(.wake)
            await load()
            return true
        case .notPrepared:
            message = "Prepare the relay first."
        case .secretsUnavailable:
            message = "Keychain secrets are unavailable. Unlock the login keychain and retry."
        case .wipeFailed(let outcome):
            message = wipeFailureMessage(outcome)
        case .bindFailed(let outcome):
            message = bindingFailureMessage(outcome)
        }
        return false
    }

    private func wipeFailureMessage(_ outcome: RelayOutcome) -> String {
        switch outcome {
        case .unauthorized:
            "Relay activation paused: the admin token was rejected."
        case .offline:
            "Relay activation paused: the relay is unreachable."
        case .quotaLimited:
            "Relay activation paused: the relay quota was reached."
        case .unsupportedVersion:
            "Relay activation paused: the relay protocol is incompatible."
        default:
            "Relay activation paused: the relay wipe was rejected."
        }
    }

    private func bindingFailureMessage(_ outcome: PublishOutcome) -> String {
        if case .backoff = outcome {
            return "Relay activation paused: publication is backing off after a relay failure."
        }
        return PublicationFailureCopy.text(for: outcome)
            ?? "Relay activation paused: the snapshot could not be bound; retry activation."
    }
}

@MainActor
final class PairingViewModel: ObservableObject {
    @Published private(set) var encodedPackage: String?
    @Published private(set) var confirmationCode: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var message: String?

    private let pairing: PairReader
    private let clipboard: PairingClipboardHelper
    private let refreshManualRequests: @MainActor () async -> Void
    private var clipboardLease: PairingClipboardLease?
    private var pollTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var expirationDeadline: Date?
    private var viewVisible = false
    init(
        pairing: PairReader, pasteboard: any PairingPasteboard = SystemPairingPasteboard(),
        refreshManualRequests: @escaping @MainActor () async -> Void = {}
    ) {
        self.pairing = pairing
        clipboard = PairingClipboardHelper(pasteboard: pasteboard)
        self.refreshManualRequests = refreshManualRequests
    }

    func begin() async {
        stopPolling()
        do {
            let offer = try await pairing.begin()
            await refreshManualRequests()
            clearClipboardIfUnchanged()
            cancelExpiry()
            encodedPackage = offer.encoded
            confirmationCode = offer.confirmationCode
            expiresAt = offer.expiresAt
            message = "Scan the QR code in Reset Radar on iPhone or iPad."
            scheduleExpiry(at: offer.expiresAt)
            startPolling()
        } catch {
            await refreshManualRequests()
            // A failed replacement leaves PairReader's prior offer intact. Resume monitoring it
            // instead of leaving a valid package visible with no activation polling.
            startPolling()
            message = "Pairing could not start. Confirm that relay setup is active."
        }
    }

    func copyWithWarningConfirmed() {
        guard let encodedPackage, let expiresAt else { return }
        clipboardLease = clipboard.copy(encodedPackage, expiresAt: expiresAt)
        message = "Pairing data is on the clipboard. Treat it like a password."
    }

    func dismiss() async {
        stopPolling()
        await pairing.revokeIfExpired()
        await refreshManualRequests()
        clearClipboardIfUnchanged()
        clearOffer()
    }

    /// Poll only while visible; a separate deadline task revokes an unclaimed reader.
    func pairingViewAppeared() {
        viewVisible = true
        guard encodedPackage != nil else { return }
        startPolling()
    }

    func pairingViewDisappeared() {
        viewVisible = false
        stopPolling()
        clearClipboardIfUnchanged()
    }

    private func startPolling() {
        guard viewVisible, encodedPackage != nil, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                switch await pairing.pollActivation() {
                case .pending: continue
                case .confirmed:
                    await refreshManualRequests()
                    message = "Reader paired."
                    clearClipboardIfUnchanged()
                    clearOffer(cancelExpiry: true)
                    return
                case .expired:
                    await pairing.revokeIfExpired()
                    await refreshManualRequests()
                    message = "Pairing expired. Start again for a new code."
                    clearClipboardIfUnchanged()
                    clearOffer(cancelExpiry: true)
                    return
                }
            }
        }
    }

    private func scheduleExpiry(at deadline: Date) {
        expirationDeadline = deadline
        expiryTask = Task { [weak self] in
            let interval = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            await self.expire(at: deadline)
        }
    }

    private func expire(at deadline: Date) async {
        guard expirationDeadline == deadline else { return }
        await pairing.revokeIfExpired()
        await refreshManualRequests()
        stopPolling()
        if await pairing.pollActivation() == .confirmed {
            message = "Reader paired."
        } else {
            message = "Pairing expired. Start again for a new code."
        }
        clearClipboardIfUnchanged()
        clearOffer(cancelExpiry: true)
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func clearClipboardIfUnchanged() {
        if let clipboardLease { _ = clipboard.clearIfUnchanged(clipboardLease) }
        clipboardLease = nil
    }

    private func cancelExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        expirationDeadline = nil
    }

    private func clearOffer(cancelExpiry: Bool = false) {
        stopPolling()
        if cancelExpiry { self.cancelExpiry() }
        encodedPackage = nil
        confirmationCode = nil
        expiresAt = nil
    }
}

@MainActor
final class DevicesViewModel: ObservableObject {
    @Published private(set) var roster = [RosterEntry]()
    @Published private(set) var destroyNeedsRetry = false
    @Published private(set) var message: String?

    private let reconcile: ReconcileReaders
    private let revoke: RevokeReader
    private let destroy: DestroyRelay
    private let publication: PublicationDriver
    private let secrets: SessionSecretCache
    private let refreshManualRequests: @MainActor () async -> Void
    private let pauseManualRequests: @MainActor () async -> Void

    init(
        reconcile: ReconcileReaders, revoke: RevokeReader, destroy: DestroyRelay,
        publication: PublicationDriver, secrets: SessionSecretCache,
        refreshManualRequests: @escaping @MainActor () async -> Void = {},
        pauseManualRequests: @escaping @MainActor () async -> Void = {}
    ) {
        self.reconcile = reconcile
        self.revoke = revoke
        self.destroy = destroy
        self.publication = publication
        self.secrets = secrets
        self.refreshManualRequests = refreshManualRequests
        self.pauseManualRequests = pauseManualRequests
    }

    func refresh() async {
        switch await reconcile.run() {
        case .reconciled(let entries):
            roster = entries
            await refreshManualRequests()
            message = nil
        case .secretsUnavailable:
            message = "Keychain secrets are unavailable."
        case .storageFailed:
            message = "The paired-device list could not be saved locally. Retry."
        case .failed, .notActive:
            message = "The paired-device list is unavailable."
        }
    }

    func revokeReader(_ id: ReaderID) async {
        switch await revoke.revoke(id) {
        case .revoked:
            await refreshManualRequests()
            await refresh()
        case .failed, .notActive, .secretsUnavailable:
            message = "The reader was not revoked; retry when the relay is reachable."
        }
    }

    func destroyRelay(confirmed: Bool) async {
        guard confirmed else { return }
        await publication.setSuspended(true)
        await pauseManualRequests()
        switch await destroy.run() {
        case .destroyed:
            await refreshManualRequests()
            await secrets.invalidateCache()
            roster = []
            destroyNeedsRetry = false
            message = "Relay data and local relay secrets were destroyed."
        case .remoteFailed, .secretsUnavailable, .storageFailed:
            destroyNeedsRetry = true
            message = "Destroy Relay is paused. Publication remains stopped; retry destruction."
        }
    }
}

@MainActor
final class RecoveryViewModel: ObservableObject {
    @Published private(set) var signing: SigningOutcome
    @Published private(set) var secrets: SecretAvailability = .available
    private let signingCheck: SigningCheck
    private let recordedTeamIdentifier: () -> String?
    private let secretCache: SessionSecretCache
    private let development: Bool

    init(
        signingCheck: SigningCheck, recordedTeamIdentifier: @escaping () -> String?,
        secretCache: SessionSecretCache, development: Bool = false
    ) {
        self.signingCheck = signingCheck
        self.recordedTeamIdentifier = recordedTeamIdentifier
        self.secretCache = secretCache
        self.development = development
        signing = signingCheck.evaluate(recordedTeamIdentifier: recordedTeamIdentifier())
    }

    func refresh() async {
        signing = signingCheck.evaluate(recordedTeamIdentifier: recordedTeamIdentifier())
        secrets = await secretCache.availability
    }

    var recoveryCopy: String {
        if development {
            return secrets == .available
                ? "Development uses separate local data and relay secrets. "
                    + "A Personal Team Release build is required for the installed collector."
                : "Development relay secrets cannot be read without interaction. "
                    + "Unlock the login keychain and retry; Reset Radar will never prompt."
        }
        return switch signing {
        case .valid where secrets == .available:
            "Signing and non-interactive Keychain access are available."
        case .changedTeam:
            "The signing identity changed. Rebuild with the recorded identity, "
                + "or set up the relay again and re-pair every reader."
        case .adHoc, .missingTeam, .unreadable:
            "This build cannot prove the required signing identity. "
                + "Install a Personal Team Release build before using relay secrets."
        case .valid:
            "The login keychain is locked or denied non-interactive access. "
                + "Unlock it and retry; Reset Radar will never prompt."
        }
    }
}
