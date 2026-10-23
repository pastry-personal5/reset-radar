import Foundation
import ResetRadarDomain

/// A user-started Refresh that includes Codex: an ordinary conditional read, one request to the
/// Mac, and a bounded wait for the Mac's authenticated result. It never re-posts.
public actor RequestMacRefresh {
    public static let pollInterval: TimeInterval = 5
    public static let waitLimit: TimeInterval = 45

    private let reader: any ReaderStore
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let random: any SecretGenerator
    private let clock: any AppClock
    private let ingest: IngestRelaySnapshot

    public init(
        reader: any ReaderStore, secrets: any SecretStore, relay: any RelayGateway,
        random: any SecretGenerator, clock: any AppClock, ingest: IngestRelaySnapshot
    ) {
        self.reader = reader
        self.secrets = secrets
        self.relay = relay
        self.random = random
        self.clock = clock
        self.ingest = ingest
    }

    public func run(scope: Set<ProductID>) async -> MacRefreshOutcome {
        let first = await ingest.run(trigger: .manual, inAppProcess: true)
        guard scope.contains(.codex) else { return .notRequested }
        if let early = await earlyOutcome(after: first) { return early }
        guard let state = try? await reader.load(), let pairing = state.pairing else {
            return .failed(.notPaired)
        }
        let marker: PendingManualRequest
        if let resumed = await resumableMarker(state) {
            marker = resumed
        } else {
            switch await post(pairing: pairing) {
            case .success(let posted): marker = posted
            case .failure(let outcome): return outcome
            }
        }
        return await wait(marker, pairing.readerID)
    }

    private func earlyOutcome(after outcome: IngestOutcome) async -> MacRefreshOutcome? {
        switch outcome {
        case .failed(.offline): return .relayUnavailable
        case .failed(let status) where status != .awaitingFirstPublish: return .failed(status)
        case .skipped:
            let state = try? await reader.load()
            return state?.awaitingActivation == true ? .pairingPending : .failed(.notPaired)
        default: return nil
        }
    }

    /// A marker from an interrupted wait that has not reached its deadline: resume it instead
    /// of posting again.
    private func resumableMarker(_ state: ReaderState) async -> PendingManualRequest? {
        guard let marker = state.pendingManualRequest else { return nil }
        if marker.deadline > clock.now { return marker }
        await clearMarker(marker)
        return nil
    }

    private enum PostResult {
        case success(PendingManualRequest)
        case failure(MacRefreshOutcome)
    }

    private func post(pairing: ReaderPairing) async -> PostResult {
        guard let token = try? await secrets.read(.readToken) else {
            return .failure(.failed(.secretsUnavailable))
        }
        guard let requestID = try? random.randomIdentifier(RequestID.self) else {
            return .failure(.failed(.secretsUnavailable))
        }
        let marker = PendingManualRequest(
            requestID: requestID, deadline: clock.now.addingTimeInterval(Self.waitLimit))
        do {
            // Written before the POST, so a crash never replays it.
            try await reader.transact { $0.pendingManualRequest = marker }
        } catch {
            return .failure(.failed(.invalidSnapshot))
        }
        let outcome = await relay.postRefreshRequest(
            requestID, endpoint: pairing.endpoint, readToken: token)
        if case .refreshAccepted = outcome { return .success(marker) }
        await clearMarker(marker)
        return .failure(Self.refusal(outcome))
    }

    private static func refusal(_ outcome: RelayOutcome) -> MacRefreshOutcome {
        switch outcome {
        case .requestRateLimited: .rateLimited
        case .requestAlreadyCompleted: .alreadyCompleted
        case .unauthorized: .failed(.authorizationRequired)
        case .quotaLimited: .failed(.quotaLimited)
        case .unsupportedVersion, .payloadTooLarge: .failed(.incompatible)
        case .offline: .relayUnavailable
        default: .failed(.invalidSnapshot)
        }
    }

    private typealias Marker = PendingManualRequest

    private func wait(_ marker: Marker, _ readerID: ReaderID) async -> MacRefreshOutcome {
        while true {
            let remaining = marker.deadline.timeIntervalSince(clock.now)
            guard remaining > 0 else { return await finishTimedOut(marker) }
            do {
                try await clock.sleep(for: .seconds(min(Self.pollInterval, remaining)))
            } catch {
                return .timedOut  // cancelled: the marker stays so a relaunch resumes the wait
            }
            let outcome = await ingest.run(trigger: .manual, inAppProcess: true)
            if outcome == .committed, let result = await matchingResult(marker, readerID) {
                await clearMarker(marker)
                return .completed(result.outcome)
            }
            if outcome == .failed(.authorizationRequired) {
                await clearMarker(marker)
                return .failed(.authorizationRequired)
            }
        }
    }

    private func matchingResult(
        _ marker: PendingManualRequest, _ readerID: ReaderID
    ) async -> ManualRefreshResult? {
        guard let snapshot = try? await reader.load().snapshot else { return nil }
        return ManualRefreshResults.result(
            for: readerID, requestID: marker.requestID, in: snapshot.manualRefreshResults,
            now: clock.now)
    }

    private func finishTimedOut(_ marker: PendingManualRequest) async -> MacRefreshOutcome {
        await clearMarker(marker)
        guard let snapshot = try? await reader.load().snapshot,
            !MacLiveness.isPublishing(snapshot: snapshot, now: clock.now)
        else { return .timedOut }
        return .macAsleepOrPending
    }

    private func clearMarker(_ marker: PendingManualRequest) async {
        try? await reader.transact { state in
            if state.pendingManualRequest == marker { state.pendingManualRequest = nil }
        }
    }
}
