#if canImport(WatchConnectivity)
    import Foundation
    import ResetRadarDomain
    @preconcurrency import WatchConnectivity

    private struct WireDictionary: @unchecked Sendable {
        let value: [String: Any]
    }

    private final class ReplyHandlerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (([String: Any]) -> Void)?

        init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }

        func reply(_ value: [String: Any]) {
            let callback = lock.withLock {
                defer { handler = nil }
                return handler
            }
            callback?(value)
        }
    }

    /// Framework-backed session boundary. It is deliberately small: decoding and all product policy
    /// remain in `WatchWireCodec` and Application. Delegate delivery is exposed as typed streams so
    /// composition roots can apply the existing transactional use cases.
    public final class WCSessionBridge: NSObject, WatchSession, @unchecked Sendable {
        private let session: WCSession
        private let codec: WatchWireCodec
        private let payloadDrain = PayloadDrainTracker()
        private let lock = NSLock()
        private var payloadContinuation: AsyncStream<WatchPayload>.Continuation?
        private var receiptContinuation: AsyncStream<WatchEraseReceipt>.Continuation?
        private var activationContinuation: AsyncStream<Void>.Continuation?
        private var refreshHandler: (@Sendable () async -> WatchRefreshReply)?
        private var activationWaiters: [CheckedContinuation<Void, Never>] = []

        public init(session: WCSession = .default, codec: WatchWireCodec = .init()) {
            self.session = session
            self.codec = codec
            super.init()
            session.delegate = self
        }

        public func incomingPayloads() -> AsyncStream<WatchPayload> {
            AsyncStream { continuation in
                lock.withLock { payloadContinuation = continuation }
                continuation.onTermination = { [weak self] _ in
                    self?.lock.withLock { self?.payloadContinuation = nil }
                }
            }
        }

        public func incomingReceipts() -> AsyncStream<WatchEraseReceipt> {
            AsyncStream { continuation in
                lock.withLock { receiptContinuation = continuation }
                continuation.onTermination = { [weak self] _ in
                    self?.lock.withLock { self?.receiptContinuation = nil }
                }
            }
        }

        public func activations() -> AsyncStream<Void> {
            AsyncStream { continuation in
                lock.withLock { activationContinuation = continuation }
                continuation.onTermination = { [weak self] _ in
                    self?.lock.withLock { self?.activationContinuation = nil }
                }
            }
        }

        /// The Watch composition root completes a unit only after durable cache commit and its
        /// complication reload request, so a watchOS background task can hold through both.
        public func payloadHandled() {
            payloadDrain.finish()
        }

        public func waitForPayloads() async {
            await payloadDrain.waitUntilDrained()
        }

        /// Installs the iPhone composition root's bounded refresh handler. A new handler replaces
        /// the old one, preventing duplicate replies when an app scene is reconstructed.
        public func installRefreshHandler(
            _ handler: @escaping @Sendable () async -> WatchRefreshReply
        ) {
            lock.withLock { refreshHandler = handler }
        }

        public func activate() async {
            if session.activationState == .activated { return }
            await withCheckedContinuation { continuation in
                lock.withLock { activationWaiters.append(continuation) }
                session.activate()
            }
        }

        public func state() async -> WatchSessionState {
            #if os(iOS)
                WatchSessionState(
                    activated: session.activationState == .activated, paired: session.isPaired,
                    watchAppInstalled: session.isWatchAppInstalled, reachable: session.isReachable,
                    complicationEnabled: session.isComplicationEnabled,
                    remainingComplicationTransfers: session.remainingComplicationUserInfoTransfers)
            #else
                WatchSessionState(
                    activated: session.activationState == .activated, paired: true,
                    watchAppInstalled: true, reachable: session.isReachable)
            #endif
        }

        public func updateApplicationContext(_ value: [String: Any]) async throws {
            try session.updateApplicationContext(value)
        }

        public func transferComplication(_ value: [String: Any]) async throws {
            #if os(iOS)
                session.transferCurrentComplicationUserInfo(value)
            #else
                throw WatchSessionError.complicationUnavailable
            #endif
        }

        public func sendMessage(_ value: [String: Any]) async throws -> [String: Any] {
            let reply: WireDictionary = try await withCheckedThrowingContinuation { continuation in
                session.sendMessage(
                    value,
                    replyHandler: {
                        continuation.resume(returning: WireDictionary(value: $0))
                    },
                    errorHandler: { continuation.resume(throwing: $0) })
            }
            return reply.value
        }

        public func transferUserInfo(_ value: [String: Any]) async throws {
            session.transferUserInfo(value)
        }

        private func receive(_ dictionary: [String: Any]) {
            guard let message = try? codec.decode(dictionary) else { return }
            lock.withLock {
                switch message {
                case .payload(let payload):
                    if let payloadContinuation {
                        #if os(watchOS)
                            payloadDrain.begin()
                        #endif
                        payloadContinuation.yield(payload)
                    }
                case .eraseReceipt(let receipt): receiptContinuation?.yield(receipt)
                default: break
                }
            }
        }

        private func reply(
            to dictionary: [String: Any], replyHandler: @escaping ([String: Any]) -> Void
        ) {
            guard case .refreshRequest? = try? codec.decode(dictionary) else {
                replyHandler((try? codec.encode(.refreshReply(.empty))) ?? [:])
                return
            }
            let handler = lock.withLock { refreshHandler }
            let replyBox = ReplyHandlerBox(replyHandler)
            Task { [codec, handler, replyBox] in
                let reply = await handler?() ?? .empty
                replyBox.reply((try? codec.encode(.refreshReply(reply))) ?? [:])
            }
        }
    }

    extension WCSessionBridge: WCSessionDelegate {
        public func session(
            _ session: WCSession,
            activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?
        ) {
            let waiters = lock.withLock {
                activationContinuation?.yield()
                let pending = activationWaiters
                activationWaiters.removeAll()
                return pending
            }
            for continuation in waiters {
                continuation.resume()
            }
        }

        #if os(iOS)
            public func sessionDidBecomeInactive(_ session: WCSession) {}
            public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
        #endif

        public func session(
            _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
        ) {
            receive(applicationContext)
        }

        public func session(
            _ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]
        ) {
            receive(userInfo)
        }

        public func session(
            _ session: WCSession, didReceiveMessage message: [String: Any],
            replyHandler: @escaping ([String: Any]) -> Void
        ) {
            reply(to: message, replyHandler: replyHandler)
        }
    }
#endif
