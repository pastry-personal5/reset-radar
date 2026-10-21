# P1-M2 spike results

Status: Draft

Dated evidence for the P1-M2 validation work listed in [the milestone overview](../../phase-1/milestone-02-software-architecture-overview.md). Entries record versions and measurements only, never raw provider responses, credentials, account identifiers, prompts, or project paths.

## Entry template

- Date and owner-present or unattended
- Question
- Method and tool versions
- Measured values
- Result: pass, fail, or deferred with blocker

## Entries

### Cloudflare relay initial remote checkpoint — 2026-10-20

- **Attendance:** Owner-present. The owner ran the Cloudflare login, deployment, remote smoke, and dashboard checks; no agent accessed the Cloudflare account or credentials.
- **Question:** Can the first synthetic-only relay checkpoint deploy to the assigned `workers.dev` hostname with one SQLite-backed Durable Object, keep unplanned routes closed, and remain inside the approved Free-plan and observability boundary?
- **Method and versions:** `npm --prefix relay run deploy:spike` with Wrangler 4.151.2 and compatibility date `2026-10-20`; then the bounded `npm --prefix relay run smoke:remote` health and closed-route checks against the canonical HTTPS `workers.dev` origin. The smoke client rejected redirects, capped each response at 4 KiB, and sent no authorization, credential, ciphertext, or provider data. The owner separately reviewed the Worker in the Cloudflare dashboard.
- **Measured values:** Wrangler reported a 0.97 KiB upload (0.50 KiB gzip), 2 ms Worker startup, creation of the `RelayObject` export, and the expected single Durable Object binding. The remote health request returned the exact synthetic SQLite contract with `Cache-Control: no-store`; `/` returned the expected bounded `404` without a redirect. The repository does not record the deployment origin, account label, account ID, or version ID.
- **Result:** **Pass for the initial checkpoint only.** The first deployment exposed Wrangler's default Preview URL warning and the first combined run stopped because `smoke:remote` had not yet been implemented. The configuration was then changed to set `preview_urls` to `false`, a fail-closed deployment-config validator and the remote smoke command were added, and the owner reported the reviewed deployment, smoke, and dashboard checks as passing. Billing remained US$0, no paid add-on or unexpected binding was reported, and Preview URLs and observability were reported disabled. The owner-present outcome is also recorded in the [Cloudflare evidence note](evidance-cloudflare.md).
- **Still deferred:** This checkpoint did not configure or exercise write or administration secrets, snapshots, reader registration/activation/revocation, manual-refresh requests, authenticated deletion, client-side AES-GCM behavior, the 24-hour Free-quota/capacity measurements, cellular retrieval, release promotion/rollback, or teardown. It is not the Cloudflare synthetic-data gate and does not authorize real provider data.

### Cloudflare relay full-harness local conformance — 2026-10-20

- **Attendance:** Local unattended validation. No Cloudflare login, remote mutation, relay credential, provider tool, or real usage data was used.
- **Question:** Does the completed synthetic harness enforce the documented snapshot, reader, manual-request, authorization, response-bound, and destruction contracts locally, and do its owner-facing scripts fail closed around configuration and secrets?
- **Method and versions:** Node.js 26.8.1, npm 11.19.0, Wrangler 4.151.2, TypeScript 5.9.3, Vitest 4.1.11, and Workers Vitest plugin 1.4.5. `npm --prefix relay test`, `npm --prefix relay run typecheck`, `npm --prefix relay run smoke:local`, `npm --prefix relay run check:deploy-config`, and a Wrangler deployment dry run used only generated synthetic fixtures and isolated local SQLite Durable Object storage.
- **Measured values:** Nine Workers conformance tests and eight Node CLI/configuration tests passed. The dry run bundled 29.74 KiB (6.58 KiB gzip) with exactly one `RELAY` Durable Object binding. The local tests covered size-before-authentication, timing-safe role checks, publisher and sequence binding, strong ETags, authenticated pre-publication `404`, conditional `304`, reader preflight/activation/retry/expiry/revocation/cap, three simultaneous manual requests, duplicate/rate/expiry/poll/acknowledgement behavior, bounded generic responses, and repeated state destruction.
- **Result:** **Pass for local harness conformance.** The provisioning test proves that only a reviewed digest binding is accepted and that its value reaches the repository-local Wrangler through standard input rather than arguments. The remote smoke and destroy clients accept only a canonical HTTPS `workers.dev` origin, refuse redirects, bound responses, use hidden raw-token prompts, and keep identifiers and response bodies out of their output.
- **Still deferred:** Exact dependency pins require owner approval before the next deployment. The updated full protocol has not been deployed or exercised remotely; pending/manual wall-clock expiry, the 24-hour Free-tier measurements, cellular/device behavior, quota and outage behavior, promotion/rollback, dashboard reinspection, and final teardown remain open. The earlier health-only remote pass does not satisfy any of these items.

## Static architecture review — 2026-10-20

This is a document-level failure and trust-boundary review, not spike evidence or approval to carry real usage through the relay. Each row names a required invariant; the synthetic and physical checks in the [milestone overview](../../phase-1/milestone-02-software-architecture-overview.md) remain open.

| Failure condition in [architecture](../../architecture.md#failure-behavior) | Boundary and design check | Remaining proof |
|---|---|---|
| Provider absent or signed out | Source state changes; cached observation ages, with no credential fallback. | Source fixtures and signed-in calibration. |
| Adapter incompatible or malformed | Per-product failure preserves valid windows and stops tight retries. | Version and malformed-source fixtures. |
| Unsafe existing Claude Code command | Installer leaves settings and restore storage untouched. | Secret-bearing and shell-command fixtures. |
| One invalid window | Per-window validation rejects only that observation. | Domain fixtures. |
| Reset with no new data | Presentation hides percentage; no inferred 0%. | Clock and timeline tests. |
| Removed Home window after reset | Fixed slot becomes unavailable; old observation is diagnostic only. | Report-removal fixture. |
| Mac-assisted request times out | No matching encrypted result means no completed-read claim. | Awake, asleep, offline, and timeout spike. |
| Codex account changes | Account scope drops old windows and dependent schedules. | Account-switch fixture. |
| Claude Code account changes | Identity is unknown; newer same-kind observation wins and old unmatched kinds age out. | Concurrent-session and account-switch fixture. |
| Concurrent Claude Code sessions | Newest proven response per kind wins; idle reruns cannot advance time. | Multi-session and response-signal calibration. |
| Mac sleeps or quits | Readers retain cache and derive stale state from original observation time. | Sleep and wake timing spike. |
| Mac network lost | Local state persists; publication resumes after path recovery. | Outage and recovery fixture. |
| Second Mac instance | One storage lock prevents a second local publisher. | Two-process Mac test. |
| Mac Keychain needs interaction before secrets are cached | Non-interactive read pauses publication; no prompt or silent key replacement. A later lock leaves an already running secret cache active, as now disclosed in Settings. | Signed and locked-Keychain spike for both timings. |
| iPhone secrets before first unlock | Cache survives; decryption reports `secretsUnavailable`. | First-unlock device spike. |
| Widget commits without app | Cross-process commit and reconciliation gate prevent rollback or stale notifications. | Suspension and widget-only spike. |
| `304` after cache loss | Conditional state is invalidated and read retried once. | Ingest fixture. |
| Old Watch message | Delivery revision and installation ID prevent resurrection after clear or re-pair. | Reordered-channel device spike. |
| Relay unauthorized | Revoked token stops reads and manual requests; cache remains. | Three-reader revocation spike. |
| Pairing preflight or local save fails | A preflight read leaves the reader pending; failed Keychain or local commit cannot activate it. Crash recovery removes staged secrets. | Pending-reader protocol and iOS storage-fault fixtures. |
| Pairing activation response is lost | The saved reader retries idempotently, including after the displayed deadline; only a relay `401` proves an expired or revoked pending registration and triggers local cleanup. | Lost-response, expiry, and revoke-during-pairing spike. |
| Relay publication `409` | Publisher stops rather than overwriting another authority. | Publisher and sequence fixture. |
| Relay quota, rate limit, outage | Free plan fails closed; readers keep valid cache. | Free-tier and outage spike. |
| Replay, wrong key, invalid tag, wrong publisher | AES-GCM and sequence checks reject before local commit. | Tamper and rollback fixture. |
| Unknown mandatory schema or protocol | Prior cache survives; reader reports incompatibility. | Cross-version fixtures. |
| Watch unreachable | Interactive request is skipped; queued context and aged cache remain. | Paired-watch reachability spike. |
| Notification or Live Activity denied | Usage continues; controls show denial without repeated prompts. | Runtime permission spike. |

| Trust boundary | Design check | Remaining proof |
|---|---|---|
| First-party tools → Mac | Only allowlisted derived usage fields cross into records; raw JSON stays in memory, credentials and prompts are never persisted. | Owner-present source calibration and logging inspection. |
| Claude Code settings → helper | Only a provably safe existing executable may be composed; no whole-settings backup. | Installer fixture and physical settings test. |
| Mac Keychain → publisher | Stable signed identity and non-interactive reads protect relay secrets. | Eight-day Keychain spike. |
| Mac pairing screen → reader | Owner compares a confirmation code over the entire encoded package, including expiry, before the reader sends a token; a publisher-only fingerprint would miss field substitution. | Tampered-QR and manual-paste pairing tests. |
| Reader local save → relay activation | The official client sends an explicit request only after committed Keychain and local state; pending-reader expiry and idempotent retry prevent its normal flow from closing the Mac early. The relay cannot attest to a remote device's disk commit. | Fault-injected local save, delayed reply, and pending-expiry spike. |
| Mac → Cloudflare | AES-GCM covers the snapshot and header; relay sees ciphertext and bounded protocol metadata. | Synthetic payload and deployment inspection. |
| Reader token → manual request → Mac | Activated token, per-reader limit, expiry, Mac read cap, and encrypted result prevent unauthenticated or false completion. | Replay, abuse, latency, and publication-failure spike. |
| Cloudflare → iPhone/iPad | Authentication, publisher binding, schema and sequence validation precede atomic commit. | Malformed, rollback, and concurrent-process tests. |
| iOS app ↔ widget | Explicit App Group Keychain group, short locks, and reconciliation flag protect shared state. | Physical App Group, Keychain, and suspension spike. |
| iPhone → Watch | Credential-free filtered payload, delivery revision, and installation confirmation protect Watch cache. | Physical delivery and re-pairing spike. |
| Cache → notifications and Live Activity | Absolute reset instants, per-slot opt-in, and stale dates prevent fabricated freshness. | Time-zone, permission, and ActivityKit spike. |

## Follow-up security review — 2026-10-20

This review traces the proposed internal modules and composition roots. The findings below are open design issues, not observed exploits or completed spike results. Resolve or explicitly accept each one before promoting the architecture to Active or sending real usage data through the relay.

| Design | Security responsibility checked | Review result |
|---|---|---|
| [Domain](../../architecture/domain.md) | Stable identities, per-window validation, observation-time and reset-state derivation | No additional static finding; source calibration and malformed-record tests remain open. |
| [Application](../../architecture/application.md) | Single ingest path, atomic sequence commit, manual-result matching, pairing activation, Watch clear | SR-1; the other decisions have specified failure behavior and tests. |
| [Storage](../../architecture/storage.md) | File protection, cross-process claims, sequence durability, migration | No additional static finding; interruption and physical file-protection tests remain open. |
| [Transport](../../architecture/transport.md) | Keychain, AES-GCM, pairing package, authenticated HTTP client | SR-2, SR-3, SR-4, and SR-5. |
| [Relay](../../architecture/relay.md) | Separated read/write/admin authority, ordering, request bounds, revocation, deletion | No additional static finding; deployed conformance and Free-tier measurements remain open. |
| [ProviderAdapters](../../architecture/provider-adapters.md) | Allowlisted provider data, subprocess isolation, safe status-line composition | SR-3; signed-in source and installer tests remain open. |
| [WatchSync](../../architecture/watch-sync.md) | Credential-free transfer and Watch reply channels | SR-1; paired-device delivery remains open. |
| [Scheduling](../../architecture/scheduling.md) | Absolute notification instants, stale activities, no inferred usage | No additional static finding; runtime notification and ActivityKit behavior remains open. |
| [UI](../../architecture/ui.md) | Provenance, stale and unavailable presentation, typed outcomes | No additional static finding; accessibility and state presentation tests remain open. |
| [iOS app](../../architecture/ios-app.md), [Mac app](../../architecture/mac-app.md), [Watch app](../../architecture/watch-app.md) | Process wiring, extension isolation, signed Mac runtime, Watch cache and complication | SR-1 and SR-5; platform lifecycle and signing spikes remain open. |

| ID | Priority | Boundary and finding | Required resolution and verification |
|---|---|---|---|
| SR-1 | High | **iPhone → Watch deletion.** [Forget Mac](../../architecture/application.md#reader-ingestion-ios) sends a cleared application context, but [WatchConnectivity delivery](../../architecture/watch-sync.md#channels) is deferred when the Watch is unreachable. The iPhone has no receipt or pending-erasure state. Forget Mac can therefore appear complete while the Watch and its complication still retain the old snapshot. | Define a Watch clear acknowledgement or an explicit pending-erasure state, keep retrying the clear on reconnection, and tell the owner when erasure cannot be confirmed. Test Forget Mac with the Watch offline, then reconnect it and prove both Watch cache and complication clear. Apple describes application context as a last-value transfer that replaces queued context, not an immediate remote erase ([Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)). |
| SR-2 | Medium | **Pairing package → system clipboard.** The [manual copy/paste fallback](../../architecture.md#pairing-a-reader) carries a long-lived content key and read token. The design specifies no clipboard lifetime or handling. The general Mac pasteboard participates in Universal Clipboard, so copying the package may expose it to other nearby devices on the same Apple Account ([AppKit pasteboard](https://developer.apple.com/documentation/appkit/nspasteboard), [Universal Clipboard](https://support.apple.com/en-au/102430)). The five-minute relay registration deadline does not expire the content key. | Prefer the camera path. Define a manual transfer flow that warns before copying, limits exposure where platform APIs permit, clears only a pasteboard value still owned by Reset Radar, and treats a suspected copied-package leak as a destroy-and-re-pair event. Test that the package does not remain in app-owned clipboard state after pairing or expiry. |
| SR-3 | Medium | **Provider/relay input → process memory.** The [Claude Code helper](../../architecture/provider-adapters.md#helper-composition) bounds stdin, and the relay bounds snapshot uploads, but the [Codex JSON-RPC reader](../../architecture/provider-adapters.md#codex-app-server) and [iOS relay response reader](../../architecture/transport.md#relay-client) specify no byte limit before buffering and decoding. A malformed or oversized source response or relay reply could exhaust the Mac, app, or widget process. | Set byte and structural limits before JSON decoding for Codex messages and every relay response, including errors and pairing preflight. Reject oversized input with typed source/transport failure while preserving the last valid cache. Add oversized and deeply nested response fixtures. |
| SR-4 | Medium | **Relay endpoint → redirected origin.** [HTTPRelayGateway](../../architecture/transport.md#relay-client) sends bearer tokens in `Authorization` using an ephemeral `URLSession`, but specifies no redirect policy. An unexpected redirect can move a credential-bearing operation away from the confirmed pairing origin; the exact header-forwarding behavior should not be a security assumption. Apple provides a redirect delegate that can refuse the redirected request ([URLSession redirect handling](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession%28_%3Atask%3Awillperformhttpredirection%3Anewrequest%3Acompletionhandler%3A%29)). | Bind each request to the confirmed HTTPS origin, reject redirects, and test cross-origin and HTTPS-to-HTTP `3xx` responses for every token role. Keep endpoint validation in the pairing codec and relay client consistent. |
| SR-5 | Medium | **Mac Keychain → in-memory publisher secrets.** [Transport](../../architecture/transport.md#secret-store) explicitly keeps secrets in process memory after the login Keychain locks, while [failure behavior](../../architecture.md#failure-behavior) says a Keychain interaction requirement pauses publication. These describe different behavior after a lock and could mislead the owner about whether locking the Keychain stops relay access. | Decide and document the active-process lock behavior in both places. If continued publication is intended, say so in Settings and recovery guidance; if lock must stop publication, invalidate the cache and prove the pause/resume behavior in the Keychain spike. |

The existing trust boundaries still require their planned synthetic and physical checks. In particular, this static review does not establish the Cloudflare ciphertext boundary, real Keychain behavior, Watch delivery timing, or absence of provider data in logs.

### Proposed architecture response

| Finding | Design response | Evidence still required |
|---|---|---|
| SR-1 | [Application](../../architecture/application.md#reader-ingestion-ios), [Storage](../../architecture/storage.md#stores), and [WatchSync](../../architecture/watch-sync.md#channels) now commit iPhone snapshot and erasure state in one `ReaderBundle`, withhold newer Watch usage, and require a matching `WatchEraseReceipt` after one atomic Watch empty-cache commit. The Watch has a local erase hold. The UI distinguishes iPhone deletion, one responding Watch cache confirmation, and delayed complication rendering. | Fault-injected crash and receipt tests; offline physical Watch, reconnection, and eventual complication reload. An unreachable or other paired Watch has no remote-erasure guarantee. |
| SR-2 | [Transport](../../architecture/transport.md#pairing-package-codec) makes Manual Copy explicit and warned, tracks only a digest and pasteboard change count for conditional cleanup, and requires destroy-and-re-pair after suspected exposure. QR remains the default. | Clipboard and relaunch tests; owner acceptance of the residual Universal Clipboard risk, because a copied key cannot be recalled from another device. |
| SR-3 | [ProviderAdapters](../../architecture/provider-adapters.md#codex-app-server) caps Codex JSON-RPC frames before allocation and validates depth, strings, and window count. [Transport](../../architecture/transport.md#relay-client) streams every relay response under byte caps. | Oversized/deeply nested synthetic fixtures and signed-in Codex calibration against the chosen bound. |
| SR-4 | [Transport](../../architecture/transport.md#relay-client) binds requests to one canonical `workers.dev` HTTPS origin and rejects every redirect. The pairing codec applies the same endpoint rule. | Token-role redirect tests and deployed synthetic endpoint checks. |
| SR-5 | [Transport](../../architecture/transport.md#secret-store) and the [Mac app](../../architecture/mac-app.md#signing-and-keychain) now agree: a prelaunch Keychain lock pauses publication, while a later lock leaves the running process's cached secrets active. Settings discloses this. | Keychain spike for both lock timings and owner review of the disclosed behavior. |

These are proposal changes only. The five findings are not marked closed until their design response and residual risk have been reviewed by the owner and the applicable tests or spikes pass.
