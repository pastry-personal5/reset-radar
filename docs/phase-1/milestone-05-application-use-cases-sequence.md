# P1-M5: Application use cases sequencing

Status: Done

Order of work, interfaces, and tests for [P1-M5](milestone-05-application-use-cases-overview.md). Behavior is defined in [Application](../architecture/application.md); this file adds only the file layout, signatures, outcome types, and test cases that file leaves open. Each task is test-first: write the named tests, watch them fail, implement, run the module's tests. The plan assumes the recommended answer to every overview open question (Q1 to Q10, answered in the changelog).

## Constraints

- Sources in `ResetRadarKit/Sources/ResetRadarApplication/`, fakes in `ResetRadarKit/Sources/ResetRadarTestSupport/`, tests in `ResetRadarKit/Tests/ResetRadarApplicationTests/`; Swift Testing only, Swift 6 strict concurrency.
- Application imports Domain and Foundation only; TestSupport imports Domain, Application, and Foundation only. No CryptoKit, Security, UserNotifications, ActivityKit, WatchConnectivity, WidgetKit, or SwiftUI.
- Ports are `Sendable` protocols named for the product need. Use cases are actors or `Sendable` structs given ports in `init`. Policies are pure value types with named constants and take `now: Date`; no use case reads `Date()` or owns a repeating timer.
- Throw specific errors; no `try?` that hides a failure. Run `swift-format` through `Scripts/lint-swift-format.sh`; do not hand-format.
- Iterate with `swift test --package-path ResetRadarKit --filter ResetRadarApplicationTests`; run the full gate once at the end of each checkpoint and at close-out.
- The owner allows Domain changes, including incompatible ones (Q1). Keep them to what the taxonomy needs and update Domain's tests and golden JSON in the same commit; no persisted data exists yet to migrate.
- Secrets are redacted by construction: `SecretValue` has no `description` or `Codable`, and no outcome, error, or diagnostic carries a token, key, digest, or ciphertext.

## Commits

One conventional commit per checkpoint (A after Task 4, B after Task 11, C after Task 14, close-out after Task 15), each with its tests and docs, made only after the complete gate passes at that point. Tasks are not committed separately.

## Setup

Branch from `main` (the open questions are already answered in the changelog), set P1-M5 to `Active` in [phase-1.md](phase-1.md), and run the baseline gate. Confirm with `git grep -n 'ResetRadarApplicationModule\|ResetRadarTestSupportModule'` that only the three known placeholder files reference the placeholders (Task 15 removes them). Confirm the Mac `xcodebuild test` run executes the package test targets: after Task 2 adds its first real test, its name must appear in that run's output, as the Domain tests did for P1-M4.

## Task 1: Error and outcome taxonomy

Files: `Application/Outcomes/RelayOutcome.swift`, `Application/Outcomes/SecretStoreError.swift`, `Application/Outcomes/UseCaseOutcomes.swift`, `Application/Outcomes/TransportStatusMapping.swift`; Domain `DiagnosticEvent.swift`; tests `TaxonomyTests.swift`, Domain `DiagnosticEventTests.swift`.

Produces:

- `enum RelayOutcome: Sendable, Equatable`, one case per row of the [relay status table](../architecture/relay.md), never an HTTP code:
  `snapshot(Data, etag: String, sequence: UInt64)` (200), `notModified` (304), `awaitingFirstPublish` (authenticated 404 on a snapshot read; any other 404 is `protocolFailure`), `badRequest` (400), `accepted(sequence: UInt64?)` (200 on write or idempotent activation), `refreshAccepted(expiresAt: Date)` (202), `deleted` (204), `unauthorized` (401), `publisherConflict` (409 write), `readerCapReached` (409 register), `requestAlreadyCompleted` (409 manual), `payloadTooLarge` (413), `unsupportedVersion` (422), `requestRateLimited` (429 manual), `quotaLimited` (platform quota or 429 free limit), `protocolFailure` (3xx, unknown route, malformed or oversized response), `offline`.
- `enum SecretStoreError: Error, Equatable { notFound, interactionRequired, unexpected(statusClass: Int) }`.
- `enum PublishOutcome { published(sequence: UInt64), notDue(next: Date?), paused, secretsUnavailable, envelopeTooLarge, stopped(StopReason), backoff(until: Date) }` with `StopReason { snapshotConflict, authorizationRequired, payloadRejected, incompatible }`.
- `enum IngestOutcome { committed, unchanged, inProgress, skipped, failed(TransportStatus) }` and `enum MacRefreshOutcome { completed(ManualRefreshResult.Outcome), macAsleepOrPending, rateLimited, alreadyCompleted, relayUnavailable, timedOut, pairingPending, notRequested }` (the last for a Claude Code-only action).
- `enum TransportStatusMapping { static func status(for: RelayOutcome, context: MappingContext) -> TransportStatus? }`; `nil` means the outcome does not change transport status (for example `deleted`).
- Domain: new `DiagnosticEvent.Category` cases (the owner permits any Domain change this needs) `publicationStopped`, `envelopeTooLarge`, `secretsUnavailable`, `relayFailure`, each with a factory that takes only enums, numbers, and dates (`httpStatusClass`, `firstSequence`, `lastSequence`).

Tests:

- **Mapping table test:** every `RelayOutcome` case is an input row; assert `TransportStatus` or `nil`. Exhaustive `switch` in the test fails to compile when a case is added without a row. Expected rows include `unauthorized` to `authorizationRequired`, `badRequest` and `protocolFailure` to `invalidSnapshot`, `unsupportedVersion` to `incompatible`, `quotaLimited` to `quotaLimited`, `awaitingFirstPublish` to `awaitingFirstPublish`, `offline` to `offline`, and `snapshot` to `current` only after validation (context).
- **Status coverage:** a table of every status in relay.md (200, 202, 204, 304, 400, 401, 404 both kinds, 409 three kinds, 413, 422, 429 both kinds, and a 3xx) names the `RelayOutcome` it must produce; this is the contract P1-M7's `ResponseMapper` implements, recorded as a fixture list.
- **Redaction:** encode each new `DiagnosticEvent` factory and assert only enum, number, and date values; Domain golden JSON is updated in the same commit if an encoding changed.

## Task 2: Ports and fakes

Files: one file per port in `Application/Ports/`; one fake per port in `TestSupport/`; tests `FakeContractTests.swift`; `ResetRadarKit/Package.swift` (add `ResetRadarDomain` to the dependencies of `ResetRadarApplicationTests`, because the tests import Domain types and `--explicit-target-dependency-import-check=error` rejects an undeclared import; this is a target dependency inside the package, not a new external dependency, and is recorded in the changelog).

Produces (signatures abbreviated; all `async` unless noted, all `Sendable`; types named here but not defined in Domain live in `Application/Ports/PortTypes.swift`):

| Port | Methods |
|---|---|
| `AppClock` | `now: Date` (sync); `sleep(for: Duration) async throws` (Q2) |
| `SecretGenerator` | `randomBytes(count: Int) throws -> SecretValue`; `randomUnit() -> Double` (Q3); `digest(of: SecretValue) -> Data` |
| `SecretStore` | `read(_: SecretName) throws(SecretStoreError) -> SecretValue`; `write(_:value:)`; `delete(_:)`; `invalidateCache()` |
| `EnvelopeCipher` | `seal(_: UsageSnapshot, header: EnvelopeHeader, key: SecretValue) throws -> SealedEnvelope` (has `encoded: Data`); `open(_: Data, key: SecretValue) throws -> (EnvelopeHeader, UsageSnapshot)` |
| `AccountScoper` | `scope(forAccountIdentifier: String) async throws -> AccountScope` |
| `PairingCodec` | `encode(_: PairingPackage) throws -> String`; `decode(_: String, now: Date) throws -> PairingPackage`; `confirmationCode(for: String) -> String` |
| `RelayGateway` | `putSnapshot(_ envelope: Data, endpoint:, writeToken:)`, `getSnapshot(endpoint:, readToken:, etag: String?)`, `activateReader`, `postRefreshRequest(_: RequestID, ...)`, `listRefreshRequests`, `deleteRefreshRequest(_:)`, `registerReader(_: ReaderID, digest: Data, ...)`, `listReaders`, `revokeReader(_:)`, `destroyRelay`; each returns `RelayOutcome` and never throws on an HTTP result |
| `UsageSource` | `start()`, `refresh() -> ReadReceipt`, `stop()`, `updates: AsyncStream<SourceSnapshot>`; `ReadReceipt(startedAt: Date, finishedAt: Date, succeeded: Bool)` lets `HandleManualRefreshRequests` decide whether a read satisfies a request |
| `SourceConfigurator` | `inspect() -> ConfigurationState`, `preview() -> ConfigurationPreview`, `apply(_: ConfigurationPreview, confirmed: Bool)`, `restore()` |
| `SnapshotStore` (Q4) | `load() -> UsageSnapshot?`, `clear()`; roles `LocalSnapshotCommitting.commitLocal(_:)`, `RemoteSnapshotCommitting.commitRemote(_:sequence:ifGreaterThan:) -> Bool`, `WatchSnapshotCommitting.commitWatch(_:deliveryRevision:)` |
| `PublisherStore` | `state`, `setLifecycle(_:)`, `nextSequence() -> UInt64`, `recordHandled(_: RequestID, until: Date)`, `handled(_:)`, pending-registration and device-name accessors |
| `ReaderStore` | `claimFetch(trigger:decide:) -> FetchClaim?` where `decide` is `@Sendable (ReaderState) -> FetchDecision`; `commitResult(_: FetchClaim, ...) -> Bool`; pairing staging, `awaitingActivation`, `forgetCleanupPending`, `watchErasePending`, pending manual-request marker, delivery revision, complication-budget fields (Q6) |
| `PreferenceStore` | `notificationOptIn(_: HomeSlot)`, `setNotificationOptIn`, `complicationEnabled`, typed accessors |
| `NotificationReconcileGate` | `claim() -> GateClaim?` with a bounded lease; `release(_:)` |
| `NotificationScheduler` | `authorization()`, `requestAuthorization()`, `pending() -> [ResetRequest]`, `schedule(_:)`, `cancel(slot:)` |
| `LiveActivityController` | `list()`, `start(slot:content:)`, `update(slot:content:staleDate:)`, `end(slot:)` |
| `WatchLink` / `PhoneLink` | send context and complication transfer, receive refresh requests and `WatchEraseReceipt`s / receive payloads, request refresh, queue receipt |
| `SurfaceReloader` | `reloadWidgets()`, `reloadComplications()` (sync, fire and forget) |
| `DiagnosticsSink` | `record(_: DiagnosticEvent)`; `history() -> [DiagnosticEvent]` |

`AccountScoper` has no calling use case: ProviderAdapters' Codex source receives it in its initializer and returns scoped `SourceSnapshot`s, which keeps adapters from importing Transport. Application defines the port and the fake only; `CollectUsage` only compares the resulting scopes.

Shared value types in `PortTypes.swift`, defined by Task 2 and used unchanged by later tasks: `SecretName`, `SecretValue` (redacted), `SealedEnvelope`, `ReaderState`, `FetchClaim(id:, expiresAt:)`, `FetchDecision`, `GateClaim`, `ResetRequest`, `ActivityContent`, `ConfigurationState`, `ConfigurationPreview`, `ReadReceipt`, `PendingRefreshRequest`, `CommitEvent(snapshot:, process:)`. Each is `Sendable`; none is `Codable` unless a store persists it.

Fakes: `FakeAppClock` (lock-protected because `now` is synchronous; settable, `advance(by:)`, `sleep` returns when advanced past), `FakeSecretStore` (injectable `SecretStoreError`), `FakeRelayGateway` (scripted `RelayOutcome` queues, request log), `FakeSnapshotStore`, `FakeReaderStore` and `FakePublisherStore` (shared-state instances so two use cases see one store), plus one fake for each remaining port. Every fake records calls and is an `actor` or lock-protected.

Tests: for each fake, a contract test of the behavior use cases rely on: `commitRemote` returns `false` for an equal or lower sequence; `claimFetch` returns `nil` for a second claim while the lease is live and a new claim once `FakeAppClock` passes the lease; `commitResult` returns `false` for a claim that lost its lease; `nextSequence` increments and never repeats after a simulated failure; `FakeSecretStore` throws `interactionRequired` when set; `FakeAppClock.sleep` resumes at the advanced instant.

## Task 3: Backoff, publication, and complication-budget policies

Files: `Application/Policies/BackoffPolicy.swift`, `PublicationPolicy.swift`, `ComplicationBudgetPolicy.swift`; tests `BackoffPolicyTests.swift`, `PublicationPolicyTests.swift`, `ComplicationBudgetPolicyTests.swift`.

Produces:

- `BackoffPolicy.delay(afterFailures: Int, randomUnit: Double) -> TimeInterval` = `randomUnit * min(30 * 2^(failures-1), 900)`; `afterFailures <= 0` gives `0`.
- `enum PublishTrigger { change, heartbeat, wake, networkRestored }`, `struct PublicationState { lastPublishedAt: Date?, backoffUntil: Date? }`, `PublicationPolicy.decide(change: ChangeClass, trigger: PublishTrigger, state:, now:) -> PublicationDecision` where `PublicationDecision` is `.publishNow` or `.wait(until: Date)`. Constants: `coalescing = 30`, `heartbeat = 300`.
- `ComplicationBudgetPolicy.allows(state: ComplicationBudgetState, changedSince: Bool, now: Date) -> Bool` where `ComplicationBudgetState` holds `enabled` and the transfer timestamps of the last 24 hours; constants `minimumInterval = 1800`, `dailyLimit = 48`.

Tests (table-driven, both sides of each edge):

- Backoff: `randomUnit` 0 and 1 for failures 1 to 8; the cap reached at failure 6 (30·2⁵ = 960, capped to 900) and held for 20 failures; success (`afterFailures: 0`) is `0`; `randomUnit` outside `0...1` is clamped.
- Publication: `transition` is `.publishNow` regardless of age; `material` at 29.999 s since last publication waits until +30 s, at exactly 30 s publishes; `observationOnly` waits for the heartbeat; heartbeat at 299.999 s waits, at 300 s publishes; `wake` and `networkRestored` publish immediately; active backoff returns `.wait(backoffUntil)` for every trigger, including `transition`, `wake`, and `networkRestored`. A first publication (`lastPublishedAt == nil`) publishes.
- Complication budget: 29 min 59 s since last transfer denies, 30 min allows; transfer 49 of a day denies; the count covers a rolling 24 hours (Q9), so the 49th is allowed once the oldest transfer is 24 hours old; no change since last transfer denies; disabled denies.

## Task 4: Reader refresh policy

Files: `Application/Policies/ReaderRefreshPolicy.swift`; test `ReaderRefreshPolicyTests.swift`.

Produces: `enum FetchTrigger { foregroundActivation, foregroundTick, manual, backgroundTask, watchRequest, widgetReload }`; `ReaderRefreshPolicy.decide(trigger:, state: ReaderState, now:) -> FetchDecision` with `.fetch`, `.skip(reason)`, or `.inProgress`; `nextBackgroundRequest(lastSuccess: Date?, nextReset: Date?, now:) -> Date` per Q8.

Tests:

- Minimum interval: an automatic trigger 14.999 s after the last attempt skips, at 15 s fetches, for each of `foregroundActivation`, `watchRequest`, `backgroundTask`; `foregroundTick` also requires 60 s; `widgetReload` skips at 4 min 59 s since the last success and fetches at 5 min.
- `manual` ignores the minimum interval and backoff, but returns `.inProgress` when a live lease exists.
- During `authorizationRequired`, `incompatible`, active backoff, or `awaitingActivation` (Q7), every automatic trigger skips; `manual` fetches except in `awaitingActivation`, where it returns `.skip(.pairingPending)`.
- Lease expiry exactly at the timeout is free (`lease.expiresAt <= now`); one second earlier is `.inProgress`.
- Next background request: floored at `now + 1 min`; `lastSuccess + 15 min` binds when no reset is near; `nextReset + 1 min` binds when it is sooner; absent inputs follow Q8; a reset in the past still floors at `now + 1 min`.

## Task 5: Snapshot reduction and CollectUsage

Files: `Application/Collect/SnapshotReducer.swift`, `ChangeClass.swift`, `CollectUsage.swift`; tests `SnapshotReducerTests.swift`, `CollectUsageTests.swift`.

Produces:

- `enum ChangeClass: Comparable { none, observationOnly, material, transition }`.
- `enum SnapshotReducer { static func reduce(previous: UsageSnapshot?, reports: [SourceSnapshot], publisherID: PublisherID, heartbeatSeconds: Int, now: Date) -> (snapshot: UsageSnapshot, change: ChangeClass) }`; pure, no ports.
- `actor CollectUsage { init(snapshots: any LocalSnapshotCommitting, diagnostics: any DiagnosticsSink, clock: any AppClock, publisherID: PublisherID, heartbeatSeconds: Int); func ingest(_ report: SourceSnapshot) async throws -> CollectResult }` with `CollectResult(snapshot:, change:)`.

Rules to pin (all from application.md "Collection and publication"): absent window becomes `retained` with its last observation on a complete report; a newer report of the same `WindowID` replaces it; a Codex account-scope change drops prior-scope windows and is a `transition`; a retained non-Home window is dropped once its reset passes, or immediately without a reset; a retained Home window without a future reset stays, resolving to an unavailable cell; a state-only report changes source state and does not advance `observedAt`.

Tests: `none` for an identical report; `observationOnly` when only `observedAt` advances; `material` for a percentage change and for a reset-instant change; `transition` for a source-state change, a window added or removed, `reportState` change, and an account-scope change; retained window keeps its last `observedAt`; non-Home retained window dropped at `resetsAt == now` but kept at one second before; retained Home window past reset remains and `HomeSlotResolver` marks it unavailable; two products merge independently; a state-only report leaves windows and observation times untouched; a commit goes through `commitLocal` only and never calls `nextSequence`; an invalid window in a report is dropped with a diagnostic while its sibling survives.

## Task 6: PublishSnapshot

Files: `Application/Publish/PublishSnapshot.swift`; test `PublishSnapshotTests.swift`.

Produces: `actor PublishSnapshot { init(publisher: any PublisherStore, secrets: any SecretStore, cipher: any EnvelopeCipher, relay: any RelayGateway, diagnostics: any DiagnosticsSink, clock: any AppClock, random: any SecretGenerator); func publish(_ snapshot: UsageSnapshot, change: ChangeClass, trigger: PublishTrigger) async -> PublishOutcome }`. Constant `maximumEnvelopeBytes = 65_536`.

Sequence per call: lifecycle check, `PublicationPolicy`, secrets read once per process (cached in the actor), `nextSequence()` persisted, seal, size check, `putSnapshot`, map outcome, update backoff.

Tests:

- Lifecycle `setupPending` and `destroyPending` return `paused` and make no secret read, sequence, or relay call; a missing relay setup is also `paused`.
- The fake `PublisherStore` records `nextSequence` before the first `putSnapshot` call (call-order assertion); a failed send leaves the incremented number unused, and the retry uses a higher one.
- Envelope of 65,536 bytes is sent; 65,537 returns `envelopeTooLarge`, makes no relay call, records `envelopeTooLarge`, and later publishes make no attempt while the set of `WindowID`s is unchanged; a changed set (the source shape) permits one new attempt. Stopped states persist for the actor's life; a new instance (relaunch) or `resume()` after `SetUpRelay` clears them. `resume()` and `invalidateSecrets()` also drop the actor's cached secrets, so the next publish after `SetUpRelay` or `DestroyRelay` re-reads `SecretStore`.
- `SecretStore` throwing `interactionRequired` returns `secretsUnavailable` and no sequence is consumed; the first successful read is not repeated for later publishes.
- Each of `badRequest`, `unauthorized`, `publisherConflict`, `payloadTooLarge`, and `unsupportedVersion` returns `stopped(...)`, records `publicationStopped`, and a later heartbeat does not retry; `offline`, `quotaLimited`, and `protocolFailure` back off with `BackoffPolicy` using `randomUnit` from the fake generator, and a success clears the failure count.
- After `invalidateSecrets()` the next publish reads secrets again exactly once; a snapshot sealed with superseded keys is never sent.
- `notDue` carries the policy's next instant; any trigger during backoff, `transition` included, returns `backoff(until:)`.

## Task 7: HandleManualRefreshRequests and ConfigureSources

Files: `Application/Mac/HandleManualRefreshRequests.swift`, `ConfigureSources.swift`; tests `HandleManualRefreshRequestsTests.swift`, `ConfigureSourcesTests.swift`.

Produces: `actor HandleManualRefreshRequests { init(...); func handle(pending: [PendingRefreshRequest]) async -> HandleOutcome }` with `PendingRefreshRequest(id: RequestID, readerID: ReaderID, expiresAt: Date)`; constants `forcedReadInterval = 30`, `resultRetention = 120`. `actor ConfigureSources { func preview(for: ProductID) async throws -> ConfigurationPreview; func apply(_: ConfigurationPreview, confirmed: Bool) async throws }`.

Tests:

- Several pending IDs coalesce into one `UsageSource.refresh()` call; each ID gets its own `ManualRefreshResult` for its `ReaderID`.
- A read whose `ReadReceipt.startedAt` is at or after the observation, or that was in flight at the observation (`startedAt` before, `finishedAt` after), satisfies it; a read that `finishedAt` before the observation does not.
- A second forced read inside 30 s waits (outcome carries the permitted instant); at exactly 30 s it runs.
- A failed read yields `sourceUnavailable` and is still published; a successful read yields `codexRead` even when the percentage is unchanged, and publication happens immediately.
- Acknowledgement (`deleteRefreshRequest`) is sent only after `PublishSnapshot` returns `published`; on publication failure no acknowledgement is sent and the request stays pending; the same ID polled again after a published result makes no new read (handled-ID store); a restart (new instance, same `FakePublisherStore`) also makes no new read.
- Results appear in later snapshots until 120 s after `completedAt`, then drop; a Claude Code source is never refreshed.
- `ConfigureSources`: `apply` with `confirmed: false` throws and changes nothing; a preview always precedes apply; an unsafe or unprovable existing status-line command is never replaced (the fake configurator reports `.unsafe`, and `apply` refuses).

## Task 8: Relay administration

Files: `Application/Relay/SetUpRelay.swift`, `PairReader.swift`, `ReconcileReaders.swift`, `RevokeReader.swift`, `DestroyRelay.swift`; one test file each.

Produces: use cases with the responsibilities in the application.md relay table. `PairReader` exposes `begin() async throws -> PairingOffer`, `pollActivation() async -> ActivationState`, and `revokeIfExpired() async` for the Mac driver (Q2). `PairingOffer` carries the `PairingPackage`, its confirmation code, and the relay-assigned `expiresAt`.

Tests:

- `SetUpRelay`: lifecycle becomes `setupPending` and secrets and publisher ID are persisted before any relay call; digests, not secrets, go to provisioning; wipe then bind; lifecycle returns to `active` only after binding succeeds; a relaunch mid-setup (new instance, same stores) resumes without regenerating secrets and without publishing.
- `PairReader`: registers a pending reader, keeps the relay-assigned deadline rather than a local clock one, builds the package; a fourth reader returns `readerCapReached`; `pollActivation` reports confirmed only on a relay-listed activated reader; `revokeIfExpired` revokes at the deadline (exactly at the deadline, not one second earlier).
- `ReconcileReaders`: merges local names with the relay list, revokes expired pending readers, keeps activated ones past their original deadline.
- `RevokeReader`: relay revoke then local removal; a relay failure keeps the local entry.
- `DestroyRelay`: `destroyPending` persisted and publication paused first; remote delete, then Keychain and in-memory secrets, then local state; a remote failure retains local state and a relaunch stays paused; a repeat after an interrupted run succeeds.

## Task 9: IngestRelaySnapshot

Files: `Application/Reader/IngestRelaySnapshot.swift`, `AfterCommitPipeline.swift`; tests `IngestRelaySnapshotTests.swift`, `AfterCommitPipelineTests.swift`.

Produces: `actor IngestRelaySnapshot { init(reader: any ReaderStore, snapshots: any RemoteSnapshotCommitting, secrets: any SecretStore, cipher: any EnvelopeCipher, relay: any RelayGateway, random: any SecretGenerator, clock: any AppClock, diagnostics: any DiagnosticsSink, afterCommit: AfterCommitPipeline); func run(trigger: FetchTrigger, inAppProcess: Bool) async -> IngestOutcome }`; `AfterCommitPipeline.run(_: CommittedSnapshot) async` calling `SurfaceReloader`, `ReconcileResetNotifications`, `ReconcileLiveActivities`, and `ForwardToWatch` in that order (iPad: no Watch step).

Tests:

- Every `FetchTrigger` against `ReaderRefreshPolicy` through the use case (skip becomes `skipped`).
- Two `IngestRelaySnapshot` instances over one `FakeReaderStore`: the second reports `inProgress` while the first's fetch is suspended; after `FakeAppClock` advances to the lease timeout the second claims, and the first's late result is rejected without changing the snapshot, ETag, or transport status.
- Stored ETag is sent only with a matching validated committed snapshot; ETag present with an empty snapshot store clears the ETag and retries once unconditionally; a second unexpected `304` stops with `failed(invalidSnapshot)`.
- A `snapshot` response is opened and validated: wrong publisher, a sequence below the pairing floor (exactly at the floor is accepted), and an invalid snapshot are rejected, preserve the committed snapshot, and retain no ETag.
- Commit only when the sequence is greater than the committed one; an equal sequence is `unchanged`.
- A failed fetch (`offline`, `quotaLimited`, `protocolFailure`) stores a backoff instant from `BackoffPolicy` and `SecretGenerator.randomUnit()` in `ReaderStore`, and consecutive failures lengthen it up to the 900 s cap; `unauthorized` and `unsupportedVersion` set `authorizationRequired` and `incompatible` with no backoff and stop automatic fetches; any `snapshot` or `notModified` success clears the failure count and backoff.
- Every `RelayOutcome` maps through `TransportStatusMapping` and produces the outcome in the Task 1 table; an authenticated first-publish `404` is `awaitingFirstPublish`, an unknown route (`protocolFailure`) is `invalidSnapshot`.
- A widget-process commit sets `needsAppReconcile` and attempts reconciliation without requesting authorization; an app-process commit runs the full pipeline in order; the interrupted widget case is repeated by the next app run.

## Task 10: RequestMacRefresh

Files: `Application/Reader/RequestMacRefresh.swift`; test `RequestMacRefreshTests.swift`.

Produces: `actor RequestMacRefresh { func run(scope: Set<ProductID>) async -> MacRefreshOutcome }`; constants `pollInterval = 5`, `waitLimit = 45`.

Tests:

- A Claude Code-only scope performs the ordinary conditional read and makes no `postRefreshRequest` call, returning `notRequested`.
- Codex scope: ordinary read, then one POST with a random request ID, then polls every 5 s with `FakeAppClock`; completion only on a newer authenticated snapshot containing a `ManualRefreshResult` with this `ReaderID` and request ID.
- Non-completing signals, each ending in the specified outcome: `304`; a newer snapshot without the result; a result for another reader; a result with the right reader and another request ID; a locally fresh cache.
- `sourceUnavailable` is reported separately from `codexRead`; `202` then no result by 45 s returns `timedOut`; at 44.999 s it is still waiting; `429` returns `rateLimited`, `409` returns `alreadyCompleted`, `unauthorized` returns `failed(authorizationRequired)`, offline returns `relayUnavailable`; none re-POST.
- The pending request marker is written before the POST and survives a relaunch without replaying the POST.
- Polling shares the Task 9 claim, so a concurrent ingest reports `inProgress`.

## Task 11: AcceptPairing and ForgetMac

Files: `Application/Reader/AcceptPairing.swift`, `ForgetMac.swift`; tests `AcceptPairingTests.swift`, `ForgetMacTests.swift`.

Produces: `actor AcceptPairing { func preview(_: String) throws -> PairingPreview; func accept(_: PairingPreview, confirmed: Bool) async -> PairingOutcome; func resumeActivation() async -> PairingOutcome; func recoverStaging() async }`; `actor ForgetMac { func forget() async -> ForgetOutcome; func retryCleanup() async -> ForgetOutcome }`.

Tests (AcceptPairing):

- Preview shows the confirmation code and changes nothing; `confirmed: false` throws. A codec failure (expired or implausibly distant deadline, wrong-length key or token, endpoint outside the origin rule) surfaces as a typed `PairingError` from `preview` with no store write.
- Preflight validates a returned envelope or accepts an authenticated first-publish `404`, and sends no activation; the preflight snapshot is not presented as paired while awaiting activation.
- Order: staging marker, Keychain writes, one atomic commit of metadata, preflight snapshot, and `awaitingActivation`, then activation. A Keychain failure or local commit failure removes staged secrets and sends no activation.
- A lost activation response leaves `awaitingActivation`; `resumeActivation` retries idempotently, also after the displayed deadline; only an authenticated `401` after expiry or revocation clears the pending pairing.
- While awaiting activation every fetch trigger is suppressed (Q7); a crash after staging is repaired by `recoverStaging` before the next pairing or fetch; accepting while already paired is rejected with `forgetRequired`.

Tests (ForgetMac):

- One atomic transaction clears snapshot and pairing state, invalidates the in-flight claim (a later `commitResult` returns `false`), keeps the installation ID, advances the Watch delivery revision, and sets `forgetCleanupPending`; when this installation has sent to a Watch, a cleared `WatchPayload` and `watchErasePending` are persisted in the same transaction before Keychain deletion or any Watch send.
- On success `cancel(slot:)` was called for all four slots and every Live Activity ended. Failure during Keychain or surface cleanup keeps `forgetCleanupPending`, hides usage, blocks pairing and fetch, and `retryCleanup` completes; success clears the marker. The iPad path has no Watch stage.
- A new pairing is allowed after local cleanup while `watchErasePending` remains, and the queued clear stays the only Watch payload.

## Task 12: Watch use cases

Files: `Application/Watch/ForwardToWatch.swift`, `ConfirmWatchErase.swift`, `CommitWatchPayload.swift`, `RequestPhoneRefresh.swift`, `EraseWatchData.swift`; one test file each.

Produces: `ForwardToWatch.send(after: CommitEvent) async`, `ConfirmWatchErase.confirm(_: WatchEraseReceipt) async -> ReceiptOutcome`, `CommitWatchPayload.commit(_: WatchPayload) async -> WatchCommitOutcome`, `RequestPhoneRefresh.request() async`, `EraseWatchData.erase() async`, `CommitWatchPayload.resetPairing(confirming: WatchPayload)`.

Tests:

- `ForwardToWatch`: strips `ManualRefreshResult`s from the Watch copy; advances and persists one revision per distinct payload (an identical payload reuses its revision); context and complication transfer carry the same revision; complication transfer only when `ComplicationBudgetPolicy` allows, with the 49th daily transfer denied; with `watchErasePending` only the saved clear is sent or resent, including in a refresh reply.
- `ConfirmWatchErase`: accepts only the same installation ID and pending revision; clears the marker and records confirmation atomically; ignores duplicate, older, and unrelated receipts; then permits newer usage at a higher revision.
- `CommitWatchPayload`: higher revision replaces cache or updates transport fields; clear at that revision erases to a tombstone; equal revision with identical content is idempotent, with different content rejected; lower revision (including a clear and a different publisher) is ignored; a different installation ID is held for owner confirmation and commits only the previewed payload; a committed clear reloads the complication and queues one receipt; a repeated identical clear requeues the same receipt; a stale clear queues none.
- `EraseWatchData`: clears the snapshot, keeps the tombstone revision, sets `localEraseHold`, requests a reload; later usage is rejected until `resetPairing`; a newer clear is still committed and acknowledged; `resetPairing` never lowers the revision floor. `RequestPhoneRefresh` treats an unreachable phone as no error.
- Reordering: context, complication transfer, and reply arriving in every permutation of three deliveries end with the highest revision committed.

## Task 13: Queries and read models

Files: `Application/Queries/LoadHome.swift`, `LoadUsageDetails.swift`, `LoadPairingStatus.swift`, `ExportDiagnostics.swift`, `ReadModels.swift`; test `QueriesTests.swift`.

Produces (Q5): `HomeReadModel(cells: [HomeCell], nextChange: Date?)` with `HomeCell(slot:, resolution:, presentation:, usedPercent: Double?, resetsAt: Date?, observedAt: Date?)`; `UsageDetailsReadModel(products: [ProductDetails], macLive: Bool?, transport: TransportStatus)`; `PairingStatusReadModel(state:, cleanupPending: Bool, watchErase: WatchEraseState?)` where `WatchEraseState` is `pending(revision)` or `confirmed(revision, at)` and is `nil` on iPad; `DiagnosticsExport` (redacted events only, produced after `confirmed: true`).

Tests: four cells in fixed slot order; a missing snapshot gives four unavailable cells; the next change equals the earliest cell `nextChange`, and loading again at that instant changes at least one cell; threshold crossings for reset, current-data expiry, and the five-minute skew edge; Mac liveness not publishing at 3 heartbeats plus one second and the observation staying stale; pairing status distinguishes local cleanup pending, Watch erasure pending, and confirmed erasure, and carries no field claiming complication-frame removal; `ExportDiagnostics` without confirmation throws.

## Task 14: Reset notifications, opt-in, and Live Activities

Files: `Application/Reminders/ReconcileResetNotifications.swift`, `SetNotificationOptIn.swift`, `ReconcileLiveActivities.swift`; one test file each.

Produces: `ReconcileResetNotifications.run(onIOS: Bool) async -> ReconcileOutcome`; `SetNotificationOptIn.set(_: HomeSlot, enabled: Bool) async -> OptInOutcome`; `ReconcileLiveActivities.run() async`; `ResetRequest(slot:, fireAt: Date, product:)` with an identifier derived from the slot only; `ActivityContent` and `staleDate` computed here.

Tests:

- One request per opted-in slot with a future `resetsAt`, identifier `reset.<slot>`; a newer reset replaces it; a missing, expired, incompatible, or account-replaced window cancels; `resetsAt == now` schedules nothing; the request holds an absolute instant that does not change when the time zone changes mid-run.
- On iOS the gate is claimed before the snapshot is read and released after; an interrupted claim is retried; a claim held by another instance returns `retryable` and does nothing; on Mac no gate is used. Copy fields contain a product and window enum and no formatted time or percentage.
- `SetNotificationOptIn`: first enable requests authorization once; denied stays recorded with a settings route; a widget-process reconcile never requests authorization.
- Live Activities: at most one per five-hour slot; `staleDate` is the earlier of the observation's current-data expiry and `resetsAt` (tied equal, and each side earlier); ends with immediate dismissal when reset has passed, the slot resolves to a different `WindowID`, the observation is gone, the user stops it, the Mac is forgotten, or activities are disabled; never starts from a background run.

## Task 15: Close-out

Remove `ResetRadarApplicationModule`, `ResetRadarTestSupportModule`, and the smoke test; confirm no reference remains (`git grep`). Run `Scripts/check-imports.sh` and `git grep -n '^import' ResetRadarKit/Sources/ResetRadarApplication ResetRadarKit/Sources/ResetRadarTestSupport` to confirm the import rules. Write the Spec corrections and each answered question into [application.md](../architecture/application.md), the port-shape notes into [storage.md](../architecture/storage.md) and [transport.md](../architecture/transport.md), update the README index, changelog, and phase-1.md, run the complete gate once, record concise evidence in the overview, and set P1-M5 to `Done`.

## Coverage of the application.md test list

| application.md bullet | Tasks |
|---|---|
| Collection and publication | 3, 5, 6 |
| Manual Mac refresh | 7 |
| Pairing and ingestion (fakes only; real locks in P1-M6) | 4, 8, 9, 11 |
| Manual reader refresh | 10 |
| Watch | 3, 12 |
| Notifications and Live Activities | 14 |
| Queries | 13 |

## Review focus

Inputs the spec implies but its test list does not name; each has a test in the owning task.

1. The 64 KiB boundary: 65,536 sent, 65,537 rejected (Task 6).
2. Exactly 30 s of coalescing and exactly 5 min of heartbeat, both sides (Task 3).
3. Lease expiry at exactly the timeout, and a late result from an expired claim (Tasks 2, 4, 9).
4. An ETag present with no committed snapshot, and a `304` that follows the unconditional retry (Task 9).
5. An account-scope change while windows are retained, and a retained Home window past its reset (Task 5).
6. A Mac or reader process that restarts mid-flow: setup, publication, manual request, pairing, and Forget Mac each resume from persisted state without reuse of a sequence or request (Tasks 6, 7, 8, 10, 11).

## Risks

- **Port shapes harden early.** Four adapter milestones implement them. Mitigation: checkpoint A is committed with a passing gate before adapter work starts (the owner declined a review gate); later port changes go through the changelog with the adapter plan updated in the same change.
- **Scope.** The milestone is the whole module. Mitigation: three checkpoints, each with a passing gate; an overrun splits at a checkpoint boundary without renumbering the pre-checkpoint work.
- **Fakes drifting from real adapters.** A fake that is more permissive than Storage or Transport hides bugs until P1-M12. Mitigation: each fake's contract test (Task 2) mirrors the storage.md and transport.md behavior it stands in for, and P1-M6 and P1-M7 re-run them against the real implementations.
- **Spec-silent decisions.** Ten open questions affect port and policy shapes; settle them before Task 1 rather than after.
- **Domain edit.** The owner permits changing Domain freely. Reopening a finished module can still break M4's tests; run the Domain tests with the Application tests after any Domain change.
