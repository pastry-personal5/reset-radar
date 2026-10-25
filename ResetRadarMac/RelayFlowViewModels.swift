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

    private let setup: SetUpRelay
    private let publication: PublicationDriver
    private let runningTeamIdentifier: () -> String?
    private let recordTeamIdentifier: (String) -> Void

    init(
        setup: SetUpRelay, publication: PublicationDriver,
        runningTeamIdentifier: @escaping () -> String? = { nil },
        recordTeamIdentifier: @escaping (String) -> Void = { _ in }
    ) {
        self.setup = setup
        self.publication = publication
        self.runningTeamIdentifier = runningTeamIdentifier
        self.recordTeamIdentifier = recordTeamIdentifier
    }

    func prepare() async {
        guard let endpoint = URL(string: origin), OriginGuard.accepts(endpoint) else {
            message = "Enter the canonical HTTPS origin for the included workers.dev relay."
            return
        }
        await publication.setSuspended(true)
        do {
            let digests = try await setup.prepare(endpoint: endpoint)
            writeDigest = hexadecimal(digests.writeToken)
            adminDigest = hexadecimal(digests.adminToken)
            if let team = runningTeamIdentifier() { recordTeamIdentifier(team) }
            isPending = true
            message = "Install both digests as Worker secrets, then activate."
        } catch {
            message = "Relay preparation paused safely. Try again to resume it."
        }
    }

    func activate() async {
        switch await setup.activate() {
        case .active:
            isPending = false
            writeDigest = nil
            adminDigest = nil
            message = "Relay setup is active."
            await publication.setSuspended(false)
            await publication.trigger(.wake)
        case .notPrepared:
            message = "Prepare the relay first."
        case .secretsUnavailable:
            message = "Keychain secrets are unavailable. Unlock the login keychain and retry."
        case .wipeFailed, .bindFailed:
            message = "Activation was interrupted. Publication remains paused; retry activation."
        }
    }
}

@MainActor
final class PairingViewModel: ObservableObject {
    @Published var deviceName = "iPhone"
    @Published private(set) var encodedPackage: String?
    @Published private(set) var confirmationCode: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var message: String?

    private let pairing: PairReader
    private let clipboard: PairingClipboardHelper
    private var clipboardLease: PairingClipboardLease?
    private var pollTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var expirationDeadline: Date?

    init(pairing: PairReader, pasteboard: any PairingPasteboard = SystemPairingPasteboard()) {
        self.pairing = pairing
        clipboard = PairingClipboardHelper(pasteboard: pasteboard)
    }

    func begin() async {
        stopPolling()
        do {
            let offer = try await pairing.begin(deviceName: deviceName)
            clearClipboardIfUnchanged()
            cancelExpiry()
            encodedPackage = offer.encoded
            confirmationCode = offer.confirmationCode
            expiresAt = offer.expiresAt
            message = "Scan the QR code in Reset Radar on iPhone or iPad."
            scheduleExpiry(at: offer.expiresAt)
            startPolling()
        } catch {
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
        clearClipboardIfUnchanged()
        clearOffer()
    }

    /// Poll only while the pairing UI is visible; its independent deadline task still revokes an
    /// unclaimed reader and clears any pairing material copied to the pasteboard.
    func pairingViewAppeared() {
        guard encodedPackage != nil else { return }
        startPolling()
    }

    func pairingViewDisappeared() {
        stopPolling()
        clearClipboardIfUnchanged()
    }

    private func startPolling() {
        guard encodedPackage != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                switch await pairing.pollActivation() {
                case .pending: continue
                case .confirmed:
                    message = "Reader paired."
                    clearClipboardIfUnchanged()
                    clearOffer(cancelExpiry: true)
                    return
                case .expired:
                    await pairing.revokeIfExpired()
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
        stopPolling()
        message = "Pairing expired. Start again for a new code."
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

    init(
        reconcile: ReconcileReaders, revoke: RevokeReader, destroy: DestroyRelay,
        publication: PublicationDriver, secrets: SessionSecretCache
    ) {
        self.reconcile = reconcile
        self.revoke = revoke
        self.destroy = destroy
        self.publication = publication
        self.secrets = secrets
    }

    func refresh() async {
        switch await reconcile.run() {
        case .reconciled(let entries):
            roster = entries
            message = nil
        case .secretsUnavailable:
            message = "Keychain secrets are unavailable."
        case .failed, .notActive:
            message = "The paired-device list is unavailable."
        }
    }

    func revokeReader(_ id: ReaderID) async {
        switch await revoke.revoke(id) {
        case .revoked: await refresh()
        case .failed, .notActive, .secretsUnavailable:
            message = "The reader was not revoked; retry when the relay is reachable."
        }
    }

    func destroyRelay(confirmed: Bool) async {
        guard confirmed else { return }
        await publication.setSuspended(true)
        switch await destroy.run() {
        case .destroyed:
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

    init(
        signingCheck: SigningCheck, recordedTeamIdentifier: @escaping () -> String?,
        secretCache: SessionSecretCache
    ) {
        self.signingCheck = signingCheck
        self.recordedTeamIdentifier = recordedTeamIdentifier
        self.secretCache = secretCache
        signing = signingCheck.evaluate(recordedTeamIdentifier: recordedTeamIdentifier())
    }

    func refresh() async {
        signing = signingCheck.evaluate(recordedTeamIdentifier: recordedTeamIdentifier())
        secrets = await secretCache.availability
    }

    var recoveryCopy: String {
        switch signing {
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
