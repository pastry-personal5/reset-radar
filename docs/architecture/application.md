# Application module

Status: Active

`ResetRadarApplication` is the use-case layer of the [software architecture](../architecture.md). It decides what Reset Radar does and when, through use cases, policies, and read models. It reaches storage, the relay, Keychain, system services, and provider sources only through ports that it defines and outer modules implement.

## Position

| Property | Value |
|---|---|
| Layer | Use cases |
| Platforms | iOS, macOS, watchOS; each composition root wires only the use cases for its platform |
| Depends on | [Domain](domain.md) and Foundation |
| Used by | Every adapter (to implement ports), [UI](ui.md), composition roots, and `ResetRadarTestSupport` |

Rules:

- Imports only Domain and Foundation, never CryptoKit, Security, UserNotifications, ActivityKit, WatchConnectivity, WidgetKit, or SwiftUI.
- Every port is a `Sendable` protocol named for the product need, such as `SnapshotStore`, not for a technology, such as `FileStore`.
- Use cases are actors or `Sendable` structs that receive ports through their initializers; they never construct adapters.
- Time comes from the `AppClock` port and randomness from the `SecretGenerator` port. The port is named `AppClock` because `Clock` would shadow Swift's `Clock` protocol.
- Use cases own no repeating timers. Drivers in the composition roots call them, and policies return the next due instant. The one wait inside a use case is `RequestMacRefresh`'s bounded 45-second poll, which sleeps through `AppClock.sleep(for:)` so it is cancellable and testable. `PairReader` exposes `pollActivation()` and `revokeIfExpired()` for the Mac driver instead of polling itself.
- `ResetRadarTestSupport`, a library linked only into test targets, provides an in-memory fake for every port.

## Internal architecture

```mermaid
flowchart LR
  subgraph Drivers["Composition-root drivers (outside this module)"]
    D1["Timers, scene phase, background tasks, Watch messages, widget reloads"]
  end
  subgraph UseCases["Use cases"]
    subgraph Mac["macOS"]
      CollectUsage
      PublishSnapshot
      ConfigureSources
      RelayAdmin["SetUpRelay, PairReader, ReconcileReaders, RevokeReader, DestroyRelay"]
      HandleManualRefreshRequests
    end
    subgraph Reader["iOS"]
      IngestRelaySnapshot
      RequestMacRefresh
      AcceptPairing
      ForgetMac
      ForwardToWatch
      ConfirmWatchErase
      ReconcileLiveActivities
    end
    subgraph Watch["watchOS"]
      CommitWatchPayload
      RequestPhoneRefresh
      EraseWatchData
    end
    subgraph Shared["Shared"]
      ReconcileResetNotifications
      SetNotificationOptIn
      Queries["LoadHome, LoadUsageDetails, LoadPairingStatus, ExportDiagnostics"]
    end
  end
  subgraph Policies["Policies"]
    PublicationPolicy
    ReaderRefreshPolicy
    ComplicationBudgetPolicy
    BackoffPolicy
  end
  subgraph Ports["Ports"]
    SourcePorts["UsageSource, SourceConfigurator, AccountScoper"]
    StorePorts["SnapshotStore, ReaderStore, PublisherStore, WatchCacheStore, PreferenceStore, NotificationReconcileGate"]
    SecurityPorts["SecretStore, SecretGenerator, EnvelopeCipher, PairingCodec"]
    NetworkPorts["RelayGateway"]
    SystemPorts["NotificationScheduler, LiveActivityController, SurfaceReloader"]
    LinkPorts["WatchLink, PhoneLink"]
    CommonPorts["AppClock, DiagnosticsSink"]
  end
  ReadModels["Read models"]
  Drivers --> UseCases
  UseCases --> Policies
  UseCases --> Ports
  Queries --> ReadModels
```

Adapters implement the ports from outside; the arrows show compile-time dependencies, and none point out of this module except to Domain.

## Ports

| Port | Purpose | Implemented by |
|---|---|---|
| `UsageSource` | Start, refresh, stop, and stream `SourceSnapshot`s for one configured account (macOS). A performed `ReadReceipt` carries start/finish times and the normalized or state-only report; a backoff-deferred receipt carries only its retry deadline and current source state. | [ProviderAdapters](provider-adapters.md) |
| `SourceConfigurator` | Inspect, preview, apply, and restore a source's local setup, such as Codex discovery or the Claude Code status line. | [ProviderAdapters](provider-adapters.md) |
| `AccountScoper` | Turn a provider account identifier into an `AccountScope` without retaining the identifier. | [Transport](transport.md) |
| `SnapshotStore` | Load and clear the committed snapshot. `LocalSnapshotCommitting` adds the Mac's `commitLocal`, which assigns no relay sequence. On iPhone and iPad the snapshot lives inside `ReaderState`, so `SnapshotStore` is a read facade and ingestion commits through `ReaderStore`; on Watch it is a facade over `WatchCacheStore`. | [Storage](storage.md) |
| `ReaderStore` | iOS `ReaderState`: the committed snapshot, pairing metadata, ingest state, fetch lease, Watch delivery revision, complication-transfer record, and a durable pending Watch-erasure marker. `transact` is the atomic boundary: the adapter takes its lock, reads the bundle, runs a synchronous, I/O-free closure, and replaces the whole bundle in one write. Claims and result commits are built on it in `ReaderClaims` and `IngestRelaySnapshot`. | [Storage](storage.md) |
| `PublisherStore` | Mac `PublisherState`: lifecycle, endpoint, publisher ID, sequence (persisted by `nextSequence()` before each send), the last accepted sequence (the pairing floor), paired-device names, pending registrations, and handled manual-refresh IDs. Same `transact` contract as `ReaderStore`. | [Storage](storage.md) |
| `WatchCacheStore` | Watch `WatchCacheState`: snapshot, installation ID, delivery revision, clear tombstone, `localEraseHold`, and a held payload from a changed installation. Same `transact` contract. | [Storage](storage.md) |
| `PreferenceStore` | Per-device notification opt-in and the complication-enabled flag. | [Storage](storage.md) |
| `NotificationReconcileGate` | Serialize reset-notification reconciliation across the iOS app and widget extension, with a bounded claim and retry after interruption. | [Storage](storage.md) |
| `SecretStore` | Non-interactive read, write, and delete of named secrets. Fails with `interactionRequired` instead of prompting. | [Transport](transport.md) |
| `SecretGenerator` | Random 256-bit keys, tokens, and identifiers, token digests, and `randomUnit()`, the non-secret jitter value that keeps `BackoffPolicy` deterministic. | [Transport](transport.md) |
| `EnvelopeCipher` | Seal a snapshot under an `EnvelopeHeader`; open and authenticate an envelope. | [Transport](transport.md) |
| `PairingCodec` | Encode and decode a `PairingPackage` for QR and manual transfer. | [Transport](transport.md) |
| `RelayGateway` | Snapshot, reader, and manual-refresh relay operations. Every call returns a `RelayOutcome`, or a `RelayResponse` carrying a value on success; none throws for an HTTP result. | [Transport](transport.md) |
| `NotificationScheduler` | Authorization state, pending reset requests, schedule, and cancel. | [Scheduling](scheduling.md) |
| `LiveActivityController` | List, start, update, and end Reset Live Activities (iPhone). | [Scheduling](scheduling.md) |
| `WatchLink` | iPhone side: send the application context and complication transfers, and receive refresh requests and Watch-erasure receipts. | [WatchSync](watch-sync.md) |
| `PhoneLink` | Watch side: receive payloads, request a refresh from the iPhone, and queue a Watch-erasure receipt. | [WatchSync](watch-sync.md) |
| `SurfaceReloader` | Ask the system to reload widget or complication timelines. | Composition roots ([iOS](ios-app.md), [Watch](watch-app.md)) |
| `AppClock` | Current time and a cancellable sleep. | Composition roots; `FakeAppClock` in tests |
| `DiagnosticsSink` | Record a `DiagnosticEvent`. | [Storage](storage.md) |

## Outcomes and errors

Use cases report typed outcomes, never HTTP codes or strings. `RelayGateway` adapters map the relay status table onto `RelayOutcome`; `RelayStatusContract` in `ResetRadarTestSupport` is that table as fixtures.

| `RelayOutcome` | Relay response | `TransportStatus` it sets |
|---|---|---|
| `snapshot` | `200` snapshot read | `current` after validation, else `invalidSnapshot` |
| `notModified` | `304` | `current` |
| `awaitingFirstPublish` | authenticated `404` | `awaitingFirstPublish` |
| `badRequest`, `protocolFailure` | `400`, other `3xx`, unknown route, malformed or oversized response | `invalidSnapshot` |
| `unauthorized` | `401` | `authorizationRequired` |
| `payloadTooLarge`, `unsupportedVersion` | `413`, `422` | `incompatible` |
| `quotaLimited` | platform quota or free-tier `429` | `quotaLimited` |
| `offline` | `5xx`, network, or TLS failure | `offline` |
| `accepted`, `refreshAccepted`, `deleted` | `200` write, `202`, `204` | none |
| `publisherConflict`, `readerCapReached`, `requestAlreadyCompleted`, `requestRateLimited` | the three `409` causes and the manual-request `429` | none; the use case reports them |

`SecretStoreError` is `notFound`, `interactionRequired`, or `unexpected(statusClass:)`. Per-use-case outcomes are `PublishOutcome` (with `StopReason`), `IngestOutcome`, `MacRefreshOutcome`, `HandleOutcome`, `PairingOutcome` (with `PairingError`), `ForgetOutcome`, `ReceiptOutcome`, `WatchCommitOutcome`, `ReconcileOutcome`, and `OptInOutcome`. No outcome, error, or diagnostic carries a token, key, digest, or ciphertext; `SecretValue` redacts itself from every string form.

## Use cases

### Collection and publication (macOS)

**`CollectUsage`** merges the latest account-scoped `SourceSnapshot` from each `UsageSource` and
the authoritative account catalog into `UsageSnapshot`:

- A window absent from the latest report stays, marked `retained`, with its last observation.
- A newer report of the same `WindowID` replaces a retained window.
- A provider-scope change drops prior-scope windows only for that local `AccountID`; sibling
  accounts are never merged or erased.
- A retained window that does not resolve to an account's standard Home ring is dropped once its
  reset passes, or immediately if it has no reset instant.
- A retained standard Home window with no reset instant, or whose last known reset has passed,
  remains only for diagnostics; Domain resolves its account ring as unavailable until a new report.
- Removing an account removes its source and windows. Alias-only metadata changes are transitions
  and never advance `observedAt`.

It commits locally through `LocalSnapshotCommitting`, without assigning a relay sequence, and classifies the change. A heartbeat restamps `generatedAt` without new content, so liveness stays accurate:

| Change | Meaning |
|---|---|
| `none` | Nothing differs. |
| `observationOnly` | Only `observedAt` advanced. |
| `material` | A percentage or reset instant changed. |
| `transition` | Source state, the window set, report state, or account scope changed. |

**`PublishSnapshot`** asks `PublicationPolicy` whether the change is due. If it is, it:

1. reads the secrets once per process from `SecretStore`;
2. increments the sequence through `PublisherStore`, persisting it before sending;
3. seals the snapshot through `EnvelopeCipher`;
4. rejects an encoded envelope over the relay's 64 KiB request limit without truncating windows or sending plaintext;
5. sends it through `RelayGateway`; and
6. maps the outcome with `BackoffPolicy`.

It never runs before relay setup. An oversized envelope is a typed incompatibility that leaves the last relay snapshot in place and stops automatic retries until the source shape or application changes. It stops automatic retries on `400`, `401`, `409`, `413`, or `422`, and reports `secretsUnavailable` when `SecretStore` fails with `interactionRequired`.

**`ConfigureSources`** drives `SourceConfigurator` for Codex discovery and the Claude Code guided
setup. It enumerates opaque options, previews the exact add or replacement, rejects stale
revisions, applies only after confirmation, and requires separate confirmation for removal.
`UpdateAccountAlias` validates and stores the Mac-authoritative alias; either change reconciles
the account catalog into a metadata-only local snapshot transition.

**`HandleManualRefreshRequests`** runs when the Mac sees one or more pending v2 requests. Each
request targets one opaque Codex `AccountID` or `allCodex`. It refreshes targeted account actors
concurrently, never creates a Claude Code response, ingests every successful report, and records a
bounded per-account result even when a sibling fails or the target was removed. Results remain in
subsequent snapshots for two minutes and are acknowledged only after result-bearing publication
succeeds. The relay retains its reader-global 60-second request limit; Mac-side forced-read
throttling and each source's active backoff are not bypassed. Repeated polls never repeat an
in-flight or completed request. A backoff-deferred source receipt maps promptly to
`sourceUnavailable`; it never fabricates read times or satisfies `codexRead`.

**Relay administration** follows the setup and pairing lifecycle in [Pairing, revocation, and loss](../architecture.md#pairing-revocation-and-loss):

| Use case | Responsibility |
|---|---|
| `SetUpRelay` | `prepare` pauses publication, persists a recoverable pending setup with new secrets and publisher ID, and returns the digests for provisioning; `activate` wipes the relay and binds the new publisher with `PublishSnapshot.bind`. Publication resumes only after binding succeeds. |
| `PairReader` | Register a pending reader, retain its relay-assigned deadline, produce the `PairingPackage` with the last accepted sequence as its floor, confirm activation through `pollActivation()`, and revoke through `revokeIfExpired()` at the deadline. |
| `ReconcileReaders` | Merge local names with the relay list, and revoke expired pending readers at launch. |
| `RevokeReader` | Revoke one reader. |
| `DestroyRelay` | Persist a `destroyPending` state and pause publication, delete remote storage, then delete Keychain and in-memory secrets and local relay state. On remote failure, retain the local state for retry; a relaunch remains paused. |

### Reader ingestion (iOS)

**`IngestRelaySnapshot`** is the single path by which an iPhone or iPad accepts data, whatever the trigger. Each run takes a `trigger` (`foregroundActivation`, `foregroundTick`, `manual`, `backgroundTask`, `watchRequest`, or `widgetReload`):

1. **Claim.** `ReaderStore.claimFetch` asks `ReaderRefreshPolicy` whether this trigger may fetch now and, if so, records a unique claim ID, bounded in-flight lease, and the attempt under the cross-process lock. A concurrent trigger reports `inProgress` rather than starting another network request. A crashed fetch's lease expires after the client's resource timeout.
2. **Fetch.** Outside the lock, call `RelayGateway.getSnapshot`. Send the stored ETag only when a validated snapshot for that publisher and ETag is still committed. If a `304` arrives without that snapshot, clear the ETag and retry once unconditionally.
3. **Open and validate.** On `200`, open the envelope with `EnvelopeCipher`. Then check:
   - the header's publisher matches the pairing;
   - the sequence is at least the pairing floor;
   - the snapshot's own validation passes.
4. **Commit.** Under one lock and atomic transaction, apply the result only if its claim ID still owns the current lease. Commit through `SnapshotStore` only if the sequence is greater than the committed one, and update ETag, contact time, and transport status in `ReaderStore`. A widget-process commit sets `needsAppReconcile` in that same transaction. Release the in-flight lease. A late result from an expired claim cannot overwrite a newer success or its transport status. Never retain an ETag from an envelope that failed authentication or validation.
5. **Outcome.** Return `committed`, `unchanged`, `inProgress`, `skipped`, or `failed(TransportStatus)`. Every failure preserves the committed snapshot. An authenticated `404` before the first publish is `awaitingFirstPublish`, never a successful empty snapshot.

When the run is in the app process, a `committed` outcome triggers the after-commit pipeline:

- `SurfaceReloader` reloads widget timelines;
- `ReconcileResetNotifications` and `ReconcileLiveActivities` run; and
- `ForwardToWatch` updates the Watch.

A commit made in the widget process attempts reset-notification reconciliation using the already
granted, per-window opt-in state. The extension never requests notification authorization. The
atomic `needsAppReconcile` flag makes the app retry notification reconciliation and update Live
Activities and the Watch on its next run even if the extension expires mid-reconciliation. An
app-side stage failure also sets or retains the flag; only completion of all required stages for
the still-current snapshot clears it. A failed marker write or a newer snapshot never counts as
completed reconciliation.

**`RequestMacRefresh`** is called only by a user-started Refresh that includes Codex. It first performs an ordinary conditional relay read, then posts a random request ID using the reader's read token. It writes a pending-request marker before the POST, so a relaunch resumes the wait without posting again. It polls conditional snapshot reads through the shared fetch claim every five seconds for at most 45 seconds and reports Mac completion only after a newer, authenticated snapshot contains a matching `ManualRefreshResult` for its `ReaderID` and request ID. An unchanged `304`, an unrelated publication, or a locally fresh cache does not complete the request. A `sourceUnavailable` result is reported separately from a successful Codex read. If the Mac is asleep, the request is rate-limited, the relay fails, or the wait expires, it returns the latest valid cache and a specific pending/unavailable outcome. It does not retry the POST automatically or ask the Mac to read Claude Code. A manual Refresh scoped only to Claude Code performs the ordinary relay read without posting a request. An optional `MacRefreshProgress` callback reports `relayContacted` after the ordinary read and `waitingForMac(deadline:)` once the relay accepted the request or a matching marker resumed, so presentation can show relay contact and an accepted request without claiming Mac completion.

**`AcceptPairing`** decodes and previews a `PairingPackage`, requires confirmation, then performs one authenticated preflight read. It validates a returned envelope or accepts an authenticated first-publish `404`; the read itself does not activate the token. It writes a recoverable local staging marker, saves the Keychain secrets, then atomically commits the pairing metadata, validated preflight snapshot if present, and `awaitingActivation` state. It sends `POST /v1/readers/activate` only after that local commit. An activation response lost to the network leaves the saved state pending and is retried idempotently on app launch or foreground activation, even after the displayed deadline: the relay may have activated before its response was lost. While awaiting activation, the preflight snapshot is not presented as a completed pairing, and every fetch trigger, a manual refresh included, is suppressed until activation succeeds; a manual tap reports `pairingPending`. A Keychain or local commit failure removes staged secrets without sending activation; only an authenticated `401` after expiry or revocation clears the pending pairing and asks for re-pairing. A crash during staging is reconciled before the next pairing or fetch. A reader with an existing pairing must use `ForgetMac` before accepting another package, so a new publisher cannot inherit the old cache, ETag, or sequence floor.

**`ForgetMac`** atomically removes the committed iPhone snapshot and pairing-specific reader state, invalidates any in-flight fetch claim, and preserves its installation ID while advancing its Watch delivery revision. That transaction sets `forgetCleanupPending` and, if this installation has sent data to a Watch, persists a cleared `WatchPayload` and `watchErasePending` before Keychain deletion or Watch delivery. It then deletes Keychain items and cancels only Reset Radar-owned local notifications and Live Activities. Since pending-notification removal is asynchronous, cleanup checks that no owned request remains before clearing `forgetCleanupPending` and reporting local forgetting complete. A failure retains the marker, hides old usage, blocks a new pairing and relay fetch, and offers retry on launch. A late response from the old claim cannot restore the forgotten snapshot or its ETag. The iPad has no Watch stage. The iPhone UI reports Watch erasure as pending until a matching receipt arrives. The user may pair a new Mac after local cleanup while Watch erasure is pending, but no new usage payload may replace the queued clear or reach the Watch before its receipt. An unreachable or lost Watch cannot be remotely erased by this app; the owner can erase Reset Radar data directly in the Watch app when it is available.

**`ForwardToWatch`** builds a `WatchPayload` and sends it as the application context after every commit or transport-status change. It removes transient `ManualRefreshResult`s from the Watch copy of the snapshot; the Watch needs usage state, not other readers' opaque request IDs. It advances and persists one delivery revision per distinct payload; both Watch channels and any reply for that payload carry the same revision. It also uses a complication transfer when `ComplicationBudgetPolicy` allows. While `watchErasePending` exists, it sends or resends only that saved clear, including in a reply to a Watch refresh request; later usage waits for acknowledgement.

**`ConfirmWatchErase`** accepts only a versioned `WatchEraseReceipt` from `WatchLink` for the same iPhone installation ID and pending clear revision. It clears `watchErasePending` and records the confirmed revision and time atomically, ignores duplicates and older or unrelated receipts, and then permits `ForwardToWatch` to send the latest newly paired snapshot at a higher revision. The receipt proves one responding Watch committed an empty cache and requested a complication reload; it cannot prove that watchOS has already removed every rendered complication frame or that another paired Watch was erased.

### Watch (watchOS)

**`CommitWatchPayload`** validates a payload and commits it through `WatchCacheStore.transact` with these ordering rules:

- a higher delivery revision from the same iPhone installation replaces the cache or updates transport fields; a clear at that revision erases the cache;
- an equal revision is idempotent only when its payload is identical; conflicting content is rejected;
- a lower revision is ignored, even when it carries a different publisher or a clear; and
- a different iPhone installation ID never silently replaces the cache. The Watch presents a reset-pairing action; after owner confirmation it clears the old cache and accepts the new installation's payload.

A cleared payload is committed as a durable tombstone containing its installation ID and revision, with no usage snapshot. After the commit and a complication reload request, `CommitWatchPayload` asks `PhoneLink` to queue a `WatchEraseReceipt`. Repeated identical clears requeue the same receipt; a stale clear never produces one. A Watch-local erase sets a durable hold that rejects future usage payloads until the owner resets Watch pairing; it keeps the tombstone and may still accept a newer clear and send its receipt. If the Watch app has been reinstalled and no longer has its prior cache or revision, it cannot attest that it erased the old installation's data.

The relay sequence still guards iPhone ingestion. The delivery revision guards reordering between WatchConnectivity channels and across Forget Mac and re-pairing.

After a commit it asks `SurfaceReloader` to reload the complication.

**`RequestPhoneRefresh`** asks the iPhone, through `PhoneLink`, to ingest and reply. A reply goes through `CommitWatchPayload`; an unreachable iPhone is not an error.

**`EraseWatchData`** is an owner-confirmed Watch action. It atomically clears the local snapshot, retains the latest delivery-revision tombstone, and sets `localEraseHold`, then requests a complication reload. The hold rejects later usage payloads until the owner invokes Reset Watch Pairing; a later clear can still be committed and acknowledged. Reset Watch Pairing never lowers the revision floor for the same iPhone installation, and a changed installation is accepted only from the specific pending payload the owner previews and confirms. This action needs no iPhone connection.

### Reset notifications (iOS and macOS)

**`ReconcileResetNotifications`** runs after every commit, and when the time zone or clock changes while the app runs. On iOS it takes `NotificationReconcileGate` before reading the latest committed snapshot and applying pending-request changes, so an app and widget cannot schedule different reset instants out of order. A claim interrupted by extension expiry remains retryable. The Mac has only one scheduler process and does not need this gate.

- For each opted-in `WindowSelection` resolving to a valid provider-reported window with a future
  `resetsAt`, it keeps exactly one request, with an identifier derived from that selection. A
  standard selection resolves by `AccountWindow`; an additional selection resolves only by its
  exact `WindowID`.
- A newer reset or changed alias/window label replaces the request, even if the fire instant
  stays the same. A missing, expired, incompatible, or account-replaced window cancels it. A
  temporarily missing additional window
  keeps its saved opt-in but has no pending request; only an exact-ID return resumes it.
- Requests carry an absolute instant, scheduled so a local time-zone change does not move it.
- Copy names the displayed account alias, product, and window and says it has reset. It never
  embeds a formatted local time or a replenished percentage.

**`SetNotificationOptIn`** records the per-device choice for any valid window. Existing standard
`AccountWindow` choices survive migration to `WindowSelection`; additional choices bind to the
concrete `WindowID`. The first enable requests authorization, and a denied state stays visible
with a route to system settings. A provisional grant schedules quiet notifications and remains
visibly provisional. Because the Mac and an iPhone schedule independently, the same reset may
alert on both.

### Reset Live Activity (iPhone)

**`ReconcileLiveActivities`** runs whenever the app executes, in the foreground or a background
task, and keeps at most one activity per five-hour account window. Activities start only from a
foreground Account Details action, through the same use case.

- **Update.** It updates content from the committed snapshot. Each update sets `staleDate` to the earlier of the observation's current-data expiry and `resetsAt`.
- **Stale.** Current-data expiry marks the existing activity stale but does not end it while its
  reset remains in the future. The view uses ActivityKit's `isStale` state and a timer that stops
  at zero; a later app execution ends the activity after reset.
- **End.** It ends an activity with immediate dismissal when any of these holds:
  - its reset has passed;
  - its `AccountWindow` now resolves to a different `WindowID`;
  - its observation is gone;
  - its account is removed;
  - the user stops it;
  - the Mac is forgotten; or
  - Live Activities are disabled.
- **Limits.** An activity cannot end itself. If the app does not run, the system ends it eight hours after start and removes it from the Lock Screen within four more hours. Since `staleDate` is never later than a reset at most five hours away, the stale presentation always appears first.

### Queries

- **`LoadHome`** produces one row per configured account with raw alias metadata, product, source
  state, and five-hour/weekly ring models, plus the earliest `nextChange`. Presentation sorts rows
  with localized natural comparison and account-number ties. On iPhone and iPad, usage is hidden
  while no pairing exists, activation is pending, or Forget Mac cleanup is unfinished.
- **`LoadUsageDetails`** produces the complete window list and source provenance for every visible
  account, plus Mac liveness, transport status, and Last Synced: the reader's last successful
  relay read, present only beside visible usage and absent on the Mac. Presentation selects an
  account by stable ID. Standard windows sort first; additional valid limits follow.
- **`LoadPairingStatus`** produces local pairing state, pending local Forget Mac cleanup, and, on iPhone, `watchErasePending` or the last confirmed responding-Watch cache erasure without claiming immediate complication-frame removal or erasure of another paired Watch. An iPad has no Watch-erasure field.
- **`ExportDiagnostics`** produces a confirmed, redacted export from `DiagnosticsSink` history.

## Policies

Policies are pure value types with their thresholds as named constants.

**`PublicationPolicy`** (macOS):

| Input | Decision |
|---|---|
| `transition` change | Publish immediately. |
| `material` change | Publish once the 30-second coalescing window since the last publication has passed. |
| `observationOnly` change | Publish on the next heartbeat. |
| Heartbeat due (five minutes since the last publication) | Publish. |
| Wake, or network path became satisfied after a failure | Publish immediately. |
| Backoff active | Wait for the backoff instant. |

**`ReaderRefreshPolicy`** (iOS):

| Trigger | Rule |
|---|---|
| `manual` | Bypass the minimum interval and backoff for the initial read, but report `inProgress` when another fetch owns the lease. The HTTP read remains conditional when a matching validated cache exists. A Codex-scoped manual action then uses `RequestMacRefresh`; follow-up reads share the same cross-process claim and stop after 45 seconds. |
| `foregroundActivation`, `watchRequest` | Fetch if the last attempt is more than 15 seconds old. |
| `foregroundTick` | Every 60 seconds while a scene is in the foreground, subject to the 15-second minimum. |
| `widgetReload` | Fetch only if the last successful fetch is more than five minutes old. |
| `backgroundTask` | Fetch if the last attempt is more than 15 seconds old. |
| Next background request | Earliest begin date is `max(now + 1 min, min(lastSuccess + 15 min, nextReset + 1 min))`. An absent `lastSuccess` gives `now + 1 min`; an absent `nextReset` gives `lastSuccess + 15 min`, still floored at `now + 1 min`. |

All automatic triggers share the 15-second minimum through `ReaderStore`, across processes; `foregroundTick` also needs 60 seconds since the last attempt. During `authorizationRequired`, `incompatible`, or an active backoff, only `manual` fetches. While `awaitingActivation`, no trigger fetches, and while `forgetCleanupPending` or unpaired, none can. A lease whose `expiresAt` is at or before `now` is free.

**`ComplicationBudgetPolicy`** (iOS) allows a complication transfer only when all of these hold:

- the complication is enabled and transfers remain;
- a standard account-window percentage, reset instant, or source state changed since the last transfer; and
- at least 30 minutes have passed since the last transfer.

At most 48 transfers a day fit inside the system's daily allowance of 50. A day is a rolling 24 hours over the transfer timestamps persisted in `ReaderState`, so the count never depends on the time zone; the enabled flag lives in `PreferenceStore`.

**`BackoffPolicy`** is exponential with full jitter: the delay is `randomUnit × min(30 s × 2^(failures−1), 15 min)`, where `randomUnit` (clamped to `0...1`) comes from `SecretGenerator.randomUnit()`, so the policy stays deterministic. The cap is reached at the sixth failure. A success resets it.

## Tests

`ResetRadarApplicationTests` exercises every use case against `ResetRadarTestSupport` fakes. Real cross-process locking is out of scope here: "two processes" means two use-case instances sharing one fake store, and the `flock` evidence belongs to Storage.

- **Collection and publication:** change classification; a state-only source failure that does not advance observation time; retained and dropped windows; account-scope replacement; local commits without a relay sequence; publication timing for each policy row, including sequence persistence before send, an over-limit encoded envelope rejected without truncation, and stop codes; and no publication during pending setup or destruction.
- **Manual Mac refresh:** per-reader request coalescing, one remote-forced Codex read per 30 seconds, encrypted results after a successful or failed read, two-minute result retention, publication before relay acknowledgement, retry after publication failure, and no Claude Code read.
- **Pairing and ingestion:** a validated preflight or authenticated first-publish `404` without activation; Keychain or local-save failure and staging recovery; activation only after both saves; lost-response idempotent retry, deadline expiry and revocation; pending-state fetch suppression; every trigger against `ReaderRefreshPolicy`; concurrent claims and lease expiry across two processes; a missing cache with an old ETag and an unexpected `304`; atomic snapshot/reader-state commit; every relay outcome; the pairing floor; re-pair clearing; and widget-process notification reconciliation or deferred app reconciliation.
- **Manual reader refresh:** a matching authenticated result versus `304`, an unrelated publication, wrong reader/request ID, Mac sleep, revoked token, rate limit, source failure, and the 45-second timeout; a Claude Code-only action makes no POST.
- **Watch:** reordering of application context, complication transfers, and replies; replayed clear and old-publisher payloads after re-pairing; iPhone installation change; durable pending clear across an iPhone crash and new pairing; blocked newer Watch payloads until a matching receipt; duplicate, stale, and wrong-installation receipts; duplicate clear receipt requeue; owner-confirmed local erase and its hold; and the complication budget at its limit.
- **Notifications and Live Activities:** reconciliation across opt-in, replacement, cancellation, expiry, time-zone change, and account replacement; activity start, update, `staleDate` selection, and each end condition.
- **Queries:** read models at threshold crossings and distinct local-cleanup, pending Watch-erasure, and confirmed active-Watch states.
