import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// The single next blocker a reader's Setup Banner explains. Pairing and delivery come from
/// `LoadPairingStatus` and the transport status, never from an empty Account List alone.
public enum ReaderSetupStep: Equatable, Sendable {
    /// The local reader store cannot be read yet, for example before first unlock.
    case storageUnavailable
    case cleanupPending
    case pairMac
    case confirmingPairing
    case secretsUnavailable
    case authorizationRequired
    case waitingForMacData
    /// An authenticated publication lists no account: nothing is set up on the Collector Mac.
    case sourceNotSetUp
    case sourceSignedOut(ProductID)
    case incompatible
    /// A later delivery failure while committed rows stay visible.
    case syncProblem(TransportStatus)

    /// The next blocker, or `nil` when setup and delivery are complete.
    /// - Parameters:
    ///   - hasVisibleSnapshot: whether an authenticated publication is visible, even an empty one.
    public static func derive(
        pairing: PairingStatusReadModel?, transport: TransportStatus, hasVisibleSnapshot: Bool,
        sources: [AccountSource]
    ) -> Self? {
        guard let pairing else { return .storageUnavailable }
        if let blocker = pairingBlocker(pairing) { return blocker }
        switch transport {
        case .secretsUnavailable: return .secretsUnavailable
        case .authorizationRequired: return .authorizationRequired
        default: break
        }
        guard hasVisibleSnapshot else { return beforeFirstPublication(transport) }
        return publicationBlocker(transport: transport, sources: sources)
    }

    private static func pairingBlocker(_ pairing: PairingStatusReadModel) -> Self? {
        if pairing.cleanupPending { return .cleanupPending }
        return switch pairing.state {
        case .notPaired: .pairMac
        case .awaitingActivation: .confirmingPairing
        case .paired: nil
        }
    }

    private static func beforeFirstPublication(_ transport: TransportStatus) -> Self {
        switch transport {
        case .incompatible: .incompatible
        case .offline, .quotaLimited, .invalidSnapshot: .syncProblem(transport)
        default: .waitingForMacData
        }
    }

    /// Blockers an authenticated publication reveals, then any later delivery failure.
    private static func publicationBlocker(
        transport: TransportStatus, sources: [AccountSource]
    ) -> Self? {
        if sources.isEmpty { return .sourceNotSetUp }
        if let signedOut = sources.first(where: { $0.state == .signedOut }) {
            return .sourceSignedOut(signedOut.product)
        }
        if transport == .incompatible || sources.contains(where: { $0.state == .incompatible }) {
            return .incompatible
        }
        return ReaderVocabulary.isSyncProblem(transport) ? .syncProblem(transport) : nil
    }

    public var title: String {
        switch self {
        case .storageUnavailable: "Local Data Unavailable"
        case .cleanupPending: "Local Cleanup Pending"
        case .pairMac: "Pair Mac"
        case .confirmingPairing: "Confirming Pairing"
        case .secretsUnavailable: "Pairing Secrets Unavailable"
        case .authorizationRequired: "Pair Again"
        case .waitingForMacData: "Waiting for Mac Data"
        case .sourceNotSetUp: "Set Up the Collector Mac"
        case .sourceSignedOut: "Sign In on the Collector Mac"
        case .incompatible: "Update Reset Radar"
        case .syncProblem: "Sync Problem"
        }
    }

    public var message: String {
        switch self {
        case .storageUnavailable:
            "Reset Radar can’t read its local data yet. Unlock this device and reopen the app."
        case .cleanupPending:
            "Forget Mac did not finish removing local data. Old usage stays hidden until cleanup "
                + "completes."
        case .pairMac:
            "Scan or paste a Pairing Package from Reset Radar on your Collector Mac."
        case .confirmingPairing:
            "Your pairing is saved on this device while Reset Radar confirms it with the relay. "
                + "Usage appears after confirmation."
        case .secretsUnavailable:
            "Unlock this device so Reset Radar can read its pairing secrets. Your last readings "
                + "stay as they were."
        case .authorizationRequired:
            "The relay no longer accepts this device. Use Forget Mac, then pair again with a new "
                + "Pairing Package."
        case .waitingForMacData:
            "Pairing is complete. Accounts appear after the Collector Mac publishes its first "
                + "update."
        case .sourceNotSetUp:
            "The Collector Mac has not set up Codex or Claude Code yet. Add an account in its "
                + "Sources settings."
        case .sourceSignedOut(let product):
            "\(ReaderVocabulary.productName(product)) is signed out on the Collector Mac. Sign in "
                + "there to resume its readings."
        case .incompatible:
            "The Collector Mac sent data this version of Reset Radar can’t fully read. Update "
                + "Reset Radar on both devices."
        case .syncProblem(let status):
            "\(ReaderVocabulary.transport(status)) Each reading keeps its own Last Updated time."
        }
    }

    public var symbolName: String {
        switch self {
        case .storageUnavailable, .secretsUnavailable: "lock"
        case .cleanupPending: "trash"
        case .pairMac, .confirmingPairing, .authorizationRequired: "link"
        case .waitingForMacData: "hourglass"
        case .sourceNotSetUp, .sourceSignedOut: "desktopcomputer"
        case .incompatible: "arrow.up.circle"
        case .syncProblem: "exclamationmark.icloud"
        }
    }

    /// Whether the banner's action opens Pairing & Sync.
    public var opensPairing: Bool {
        switch self {
        case .cleanupPending, .pairMac, .confirmingPairing, .authorizationRequired: true
        default: false
        }
    }
}
