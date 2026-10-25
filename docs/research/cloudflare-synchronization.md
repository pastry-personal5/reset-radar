# Cloudflare synchronization

Status: Active

Research for using Cloudflare as the primary store-and-forward path between the Mac collector and iPhone. It selects a storage primitive, defines the security and operational boundary, and leaves a concrete synthetic-data validation spike; it does not deploy a Worker or upload real usage data.

Sources were checked on 2026-10-19. Current Cloudflare documentation was fetched through Context7 and cross-checked against the first-party pages linked below.

## 1. Verdict

Cloudflare Workers with one SQLite-backed Durable Object is the recommended primary synchronization candidate. Workers KV should not be the primary store.

The owner has accepted the included `workers.dev` hostname. A custom domain is not part of the relay while the US$0 requirement applies.

- `[documented]` Durable Object storage is private to the object, transactional, and strongly consistent. Cloudflare recommends SQLite-backed storage for new Durable Object namespaces, and it is available on the Workers Free plan.
- `[documented]` KV is eventually consistent, can expose an earlier value for 60 seconds or more across locations, allows only one write per second to the same key, and is not intended for atomic read-modify-write operations.
- `[inferred — confidence: high]` A single Durable Object per owner relay can atomically reject sequence rollback, serialize replacement of the latest snapshot, support conditional reads, and delete the active relay state. Those correctness properties matter more here than KV's globally cached read latency.
- `[documented]` At the expected personal-use volume, Workers and Durable Objects fit comfortably within the current free allocations. A Workers Free account has hard daily limits; excess Worker requests fail instead of becoming metered overages.
- `[inferred — confidence: high]` Cloudflare costs exactly US$0 only under the configuration contract in section 2. The owner must not enroll the account or Worker in Workers Paid, which currently has a US$5 monthly minimum and metered overages.
- `[inferred — confidence: high]` Cloudflare must store usage snapshots only as ciphertext, alongside minimal authorization, ordering, and manual-request metadata. The content-encryption key remains on the paired Apple devices; request-authentication credentials are separate and grant read, write, or deletion authority without decrypting the snapshot.
- `[documented]` A relay does not wake the iOS app. It improves store-and-forward availability over cellular, but foreground refresh and opportunistic background execution remain the first-version delivery model under free Apple signing.

This is an architecture recommendation, not proof from a deployed system. The spike in section 10 must pass before the relay becomes a frozen dependency.

## 2. Zero-cost contract and hidden-fee audit

`[documented]` Cloudflare gives accounts access to Workers Free by default. Under that plan, the selected Worker and SQLite-backed Durable Object have finite daily allowances rather than usage-priced overages. Cloudflare's Worker limit returns error 1027 after the account reaches 100,000 daily requests, and its storage pricing says operations fail when a Free allowance is exhausted. The limits reset at 00:00 UTC. As checked on 2026-10-24, Cloudflare also documents structured error negotiation on Free: an `Accept: application/json` client receives bounded machine-readable fields including stable `cloudflare_error`, `error_category`, `error_code`, and response `status`; Error 1027 belongs to `rate_limit`. Reset Radar matches only that narrow combination.

The following configuration is the cost contract. Every row is required for the relay to qualify as a US$0 service:

| Requirement | Reason |
|---|---|
| Keep the Cloudflare account and this Worker on **Workers Free**. Verify the dashboard shows no Workers Paid subscription before the first deployment and after every billing or plan change. | Workers Paid currently has a US$5 monthly minimum and automatically meters eligible usage above its included amounts. A low-volume Worker on Paid is not US$0. |
| Use only one Worker and one **SQLite-backed** Durable Object namespace for the relay. Do not select the legacy key-value Durable Object backend. | SQLite-backed Durable Objects are available on Free; the key-value backend is a Paid-plan feature. |
| Use the assigned `workers.dev` hostname. Do not require a custom domain. | Cloudflare describes `workers.dev` as a free website intended for personal or hobby use. A custom domain introduces registrar purchase and renewal charges even if the Worker route itself has no separate fee. |
| Use per-Worker encrypted secrets. Do not require Secrets Store, KV, D1, R2, Queues, Workflows, Analytics Engine, Logpush, Access, or another Cloudflare product. | The relay does not need those products. Some are paid, some have independent quotas, and beta or separately priced products make the cost proof harder to maintain. |
| Explicitly disable Workers Logs and traces, and do not configure Logpush or an external telemetry destination. | New Workers can have observability enabled by default. Workers Logs pricing changes on 2026-12-01; Workers Paid can incur log ingestion/storage overages, and third-party telemetry can have its own bill. Free observability would stop ingesting at its allowance, but it is unnecessary for normal operation and exposes metadata. |
| Use local development for routine work and synthetic requests for the minimum remote smoke test. Keep preview or test deployments on the same Free account only if their consumption is included in the measured account budget. | Worker, Durable Object, and observability allowances are account-wide; unrelated Workers and remote testing reduce the relay's headroom. |
| Configure the Worker route to fail closed when its daily request limit is exhausted. | Fail-open routing is inappropriate for an authenticated relay. Failure must produce stale/offline app state, never bypass the Worker or trigger an upgrade. |
| Never respond to quota pressure by clicking an upgrade prompt, purchasing a limit increase, or attaching a paid add-on. | The US$0 guarantee comes from accepting temporary unavailability at the Free limits, not from an assumed spending cap on a paid service. |

Hidden or adjacent costs are:

| Cost path | Current finding | Control |
|---|---|---|
| Workers Paid | `[documented]` US$5/month minimum per account, plus metered Worker and Durable Object overages. | Prohibited by the cost contract. |
| Data transfer | `[documented]` Cloudflare lists no additional egress or throughput charge for Workers. | No special control is needed, but the app still minimizes polling and cellular use. |
| Custom domain | `[inferred — confidence: high]` Registration and renewal are external recurring costs. | Use `workers.dev`. |
| Workers Logs and traces | `[documented]` Free currently includes a capped allowance. A unified Observability model begins 2026-12-01: Free includes 0.5 GB ingestion/day and stops ingestion at the limit, while Paid permits charged overages. | Disable both. Recheck before deployment because the published change has not taken effect as of this review. |
| Workers Logpush | `[documented]` Available only on Workers Paid and separately usage-priced there. | Do not enable it. |
| Rate Limiting binding | `[documented gap]` The current API page documents behavior but does not state a price or a plan requirement, and the Workers pricing page does not list it. | Do not make it part of the US$0 proof. Add it only after a Free-account deployment confirms no upgrade or billable-product enrollment. The platform's hard account quota remains the cost ceiling. |
| Other Cloudflare workloads | `[documented]` Worker request and storage allowances are account-wide. | Prefer an otherwise-unused Free account, or inventory every workload and preserve ample shared headroom. |
| External monitoring, CI, domain registrar, Internet, electricity, and cellular data | `[inferred — confidence: high]` These are not Cloudflare Worker charges but can cost money independently. | Require none for relay operation; treat the owner's existing connectivity as outside the Cloudflare US$0 claim. |
| Pricing or product changes | `[documented]` Cloudflare publishes dated pricing and has already announced an observability-pricing change. | Recheck the linked first-party pricing, limits, logging, and `workers.dev` pages immediately before deployment and after notices; stop using the relay if the contract no longer yields US$0. |

No public Cloudflare documentation found in this review promises these terms forever or proves that account signup never requests a payment method in every country. The defensible claim is narrower: with no paid subscription or add-on enabled, the documented Free products above have no metered overage path; exceeding their allowances causes rejected operations or stopped ingestion. The validation must inspect the account's billing page and abort if deployment requires a paid plan.

## 3. Product and trust boundary

The relay carries only normalized coding-allowance observations produced by the selected Codex app-server and Claude Code status-line adapters. It does not make general ChatGPT or Claude web/mobile usage machine-readable.

The first-version trust boundary is:

- the Mac collector is the only publisher;
- up to three iPhones or iPads are readers, each with its own read token and a shared content key (owner decision 2026-10-19);
- Cloudflare terminates TLS and can observe request metadata, authentication material while a request executes, and opaque ciphertext, but must not receive the content-encryption key or plaintext snapshot;
- the Worker has no vendor token, account email, prompt, response, project path, CLI path, or raw provider output;
- the iPhone retains its last valid local cache when the relay is unavailable or returns invalid data;
- no public account-registration, relay-listing, or password-recovery endpoint exists.

`[inferred — confidence: high]` End-to-end encryption limits a Cloudflare compromise to metadata disclosure, availability attacks, capture of request credentials, and replay of previously valid ciphertext. Client-side authentication, a monotonic sequence, and a pairing sequence floor prevent forgery and most rollback cases; Cloudflare still remains an availability dependency.

## 4. Storage selection

| Candidate | Relevant behavior | Result |
|---|---|---|
| SQLite-backed Durable Object | `[documented]` Strongly consistent, transactional, one globally addressable coordination point, available on Free, 2 MB row/value ceiling, atomic `deleteAll()`, and up to 30 days of point-in-time recovery history. | Selected for the validation spike. Store one current ciphertext record and minimal protocol state. |
| Workers KV | `[documented]` Eventually consistent; old values can remain visible for 60 seconds or more; one write/second/key; 1,000 writes/day on Free. | Reject as the primary source of truth. It adds rollback and conflict complexity without a useful benefit at this scale. |
| D1 | `[documented]` Serverless SQL with a much broader database surface. | Reject for version 1. A single relay record does not need a shared relational database. |
| R2 | `[documented]` Object storage suited to larger objects and files. | Reject for version 1. Snapshots are tiny and require serialized state transitions, not object distribution. |

The selected Durable Object contains:

- the latest accepted opaque publisher ID and unsigned sequence number;
- the latest versioned encrypted envelope and a strong entity tag;
- the time the Worker accepted it;
- a protocol-state version needed to reject incompatible requests;
- up to three registered reader-token digests, activation flags, and pending deadlines; and
- up to three short-lived opaque, account-targeted manual-refresh requests, with per-reader
  rate-limit metadata.

No history is retained by Reset Radar in Cloudflare. Replacing a snapshot overwrites the active record. Cloudflare's SQLite-backed Durable Object point-in-time recovery can restore database state from the preceding 30 days, so product copy must not promise immediate physical erasure from every provider recovery system.

## 5. Relay protocol

The validation spike should prove the canonical [relay protocol](../architecture/relay.md#protocol), summarized here:

| Operation | Authority | Behavior |
|---|---|---|
| `PUT /v1/snapshot` | Write token | Accept one versioned encrypted envelope no larger than 64 KiB. Atomically reject an unexpected publisher, an equal or lower sequence, malformed metadata, or an unsupported mandatory version. Return the accepted sequence and entity tag. |
| `GET /v1/snapshot` | Read token | Return the current envelope with `Cache-Control: no-store` and an entity tag. Support `If-None-Match`; return not-found when no snapshot has been published. |
| `POST /v1/readers/activate` | Registered read token | Idempotently activate the token after local save, before its pending expiry. |
| `POST /v2/refresh-requests` | Activated read token | Accept a bounded, rate-limited, opaque request ID targeting one Reset Radar `AccountID` or `allCodex` for an awake Mac to poll. The clean-break v2 body carries no alias, provider identifier, usage value, or credential. |
| `GET` and `DELETE /v2/refresh-requests` | Write token | List unexpired requests with their opaque target and acknowledge one only after publishing its encrypted per-account result. There is no `/v1/refresh-requests` compatibility path. |
| Reader registration, listing, and revocation | Administration token | Register, list, and revoke up to three independent reader tokens through the paths in the canonical protocol. |
| `DELETE /v1/relay` | Destructive administration token | Atomically call `deleteAll()` after explicit owner confirmation in a trusted local UI. The client then discards its credentials and cache. |

All other methods and paths return a generic error. Secrets never appear in a URL, query string, response body, or log message.

The outer envelope exposes only fields the Durable Object needs to enforce ordering:

- protocol/envelope version;
- opaque random publisher ID;
- monotonically increasing sequence number;
- encryption-key version;
- AES-GCM nonce, ciphertext, and authentication tag.

Provider windows, observation times, source versions, availability, and reset data stay inside the ciphertext. Bind the outer version, publisher ID, sequence, and key version into AES-GCM authenticated data so they cannot be changed without authentication failure.

`[documented]` Apple CryptoKit supports randomly generated 256-bit symmetric keys, AES-GCM sealed boxes, random nonces when the caller omits one, and authenticated additional data. `[inferred — confidence: high]` Using those platform primitives avoids inventing an encryption construction.

## 6. Authentication, pairing, and recovery

Generate three independent random 256-bit values on the Mac at setup, plus a separate random 256-bit read token for each paired reader:

1. a content-encryption key shared only with the iPhone;
2. a write bearer token retained by the Mac;
3. a destructive administration token retained by the Mac.

Store SHA-256 digests of the write and administration tokens as Worker secrets, and reader-token digests in the Durable Object. Compare presented-token digests in constant time. Cloudflare documents encrypted Worker secret bindings and `crypto.subtle.timingSafeEqual`; secrets must not be placed in `vars`, source, Wrangler configuration, terminal arguments, or committed development files.

The first version should use an owner-deployed, single-tenant Worker rather than a public provisioning service. Setup is:

1. The owner creates or selects an otherwise-unused Cloudflare account, confirms that Workers Free is active with no paid subscription or add-on, and deploys the version-pinned Worker to its assigned `workers.dev` endpoint. Endpoint obscurity is not an authentication control.
2. A local setup command prompts for the token digests and writes them as Worker secrets without echoing values or placing them in shell history.
3. The Mac binds its publisher, registers a reader, and displays a short-lived, owner-confirmed QR payload containing the endpoint, `ReaderID`, that reader's token, content key, opaque publisher ID, key version, minimum acceptable sequence, and relay-assigned five-minute registration expiry.
4. The iPhone or iPad preflight-reads and validates the snapshot, then stores its read token and content key in Keychain as non-synchronizing `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` items so approved background and widget refresh can decrypt after first unlock. Only after local pairing state is committed does it send an idempotent authenticated activation request. A preflight read alone never closes the Mac pairing screen; expired pending registrations cannot activate.

There is no server-side recovery for the content key. Ordinary reader retirement revokes only its read token; a lost or compromised reader, publisher replacement, or suspected key compromise destroys and recreates the relay identity, tokens, publisher ID, and content key, then re-pairs readers. This is simpler and safer than a recovery service for one owner.

Multiple publisher Macs are deferred. Supporting them requires a separate publisher identity, token, and sequence space per Mac plus a defined merge rule for observations. It must not be implemented by letting several Macs share one write token and overwrite one sequence.

## 7. Abuse and replay controls

- Reject oversized and malformed requests cheaply. The Worker rejects invalid write and administration credentials before storage access; the Durable Object checks read-token digests and an invalid read token causes no write. The Durable Object enforces the per-reader manual-request limit. A separate Workers rate-limiting binding would need a new cost and dependency decision.
- Enforce small request headers and a 64 KiB application body limit even though the platform allows much larger requests.
- Authenticate before parsing or storing the ciphertext body beyond the minimum needed to enforce the size limit.
- Reject write sequences that are not strictly greater than the stored sequence. A repeated captured `PUT` is therefore idempotently rejected.
- The iPhone separately rejects a response below its highest accepted sequence or the minimum sequence carried during pairing. This prevents Cloudflare or a network intermediary from rolling an established client back to an older valid envelope.
- Return generic unauthorized and malformed responses. Do not reveal whether a token, publisher ID, or relay state exists.
- Use HTTPS only, set `Cache-Control: no-store`, and never place authorization or relay secrets in cache keys or URLs.

Cloudflare's platform DDoS protection and rate limiting reduce abuse but cannot guarantee availability. On the Free plan, an attacker who exhausts the account's daily request allocation can cause legitimate requests to fail until the quota resets. The app must show a stale/offline state and retain its last valid cache.

## 8. Privacy, deletion, and operations

Cloudflare can observe the request IP, time, route, size, response status, and other invocation metadata even though it cannot decrypt the envelope. By default, KV data is globally replicated; that is another reason not to use KV. A Durable Object persists in a selected location, and Cloudflare offers EU, US, or FedRAMP jurisdiction constraints, but those do not control every request-processing or logging location. No appropriate Korea-only control is documented.

Operational requirements:

- explicitly disable Workers Logs and traces in Wrangler and do not call `console.log` with requests, headers, bodies, tokens, relay identifiers, ciphertext, or device metadata;
- rely only on the included aggregate request/error metrics for normal operation; temporary diagnostics must remain disabled unless their current price and privacy impact are re-approved;
- use local development by default; if a remote test Worker or storage namespace is necessary, count it in the same account-wide Free budget and delete it after validation;
- pin a Workers compatibility date and a tested Wrangler version;
- deploy immutable versions; for the isolated synthetic M9 Worker, promote a candidate to 100%, privately verify the active version, immediately smoke-test it with synthetic ciphertext, and roll back on failure because Durable Object Workers do not receive Version URLs;
- keep a rollback runbook, while recognizing that Worker rollback does not roll storage back and may be blocked by incompatible storage migrations;
- keep the account on Workers Free permanently while the US$0 requirement applies, and configure quota exhaustion to fail closed without usage charges;
- keep Cloudflare API tokens scoped to only the required Worker, Durable Object, and deployment permissions and store them outside the repository;
- provide an owner-visible delete action and a documented Cloudflare-account teardown path.

`[documented]` Cloudflare says new Workers can have observability enabled by default and invocation logs contain request/response metadata. Current Free-plan log retention is three days when logging is enabled; on 2026-12-01 it moves to the unified Observability allowance described in section 2. `[documented]` SQLite Durable Objects use `deleteAll()` for atomic deletion of active storage, but point-in-time recovery can address states from the preceding 30 days.

## 9. Capacity and failure model

The original baseline of one 4 KiB publish and one reader fetch every five minutes is 576 Worker and Durable Object requests per day, but it no longer represents the selected foreground, three-reader, and Mac-assisted manual-refresh behavior. The current intended-client estimate is in [Relay capacity](../architecture.md#relay-capacity); its conservative all-day maximum is about 69,500 Worker requests including request acknowledgements. The physical row-write count can be higher than the logical operation count if the schema adds indexes or auxiliary rows, so it must be measured. Current free allocations include:

- 100,000 Worker requests/day;
- 100,000 Durable Object requests/day and 13,000 GB-s/day;
- 100,000 SQLite rows written/day, 5 million rows read/day, and 5 GB total stored data;
- a 10 ms Worker CPU allowance and 128 MB memory per request.

The intended-client request estimate remains below the documented Free request limit. The spike must still measure actual CPU use for token hashing, validation, and routing because the Free-plan Worker CPU ceiling is small.

The all-day estimate consumes about 70% of each 100,000-request daily allowance before pairing, rejected abuse traffic, or unrelated account work. These figures are availability headroom, not a spending forecast. They are account-wide and must be recomputed if any other workload shares the account. Durable Object duration and actual SQL rows read and written also need measurement; the request-count margin alone does not prove every quota margin. The implementation should avoid WebSockets and alarms and let the object become idle so it does not waste the 13,000 GB-s daily duration allowance.

Map failures to stable client states:

| Condition | Client behavior |
|---|---|
| Unauthorized or revoked | Stop automatic retries, retain cache, and require re-pairing. |
| Rate limited or free quota exhausted | Honor bounded exponential backoff with jitter; show relay unavailable/stale. |
| No snapshot | Show source unavailable, not zero usage. |
| Network, TLS, Worker, or Durable Object failure | Retain the last valid cache and distinguish transport failure from source staleness. |
| Older/equal sequence | Ignore without replacing cache; surface a diagnostic only after repeated occurrences. |
| Unknown mandatory version or failed AES-GCM authentication | Retain cache, mark the relay incompatible/invalid, and do not retry tightly. |
| Valid newer envelope | Commit to local cache only after full decryption, schema, timestamp, publisher, and sequence validation. |

## 10. Required validation spike

Use synthetic fixtures only. Do not connect a real provider adapter or upload real usage data until these checks pass:

- confirm the billing page shows Workers Free, no Workers Paid subscription, and no paid add-on before and after deploying a Free-plan Worker plus SQLite-backed Durable Object;
- deploy only to `workers.dev`, using per-Worker secrets, with logs, traces, Logpush, and unused Cloudflare bindings disabled;
- prove write, conditional read, strict sequence rejection, publisher rejection, body/version validation, and atomic deletion;
- prove separate read, write, and destructive credentials cannot cross authorities;
- prove that a preflight read does not activate a pending reader; local-save failure cannot activate it; a lost confirmation response is idempotently recoverable even after the displayed deadline; and relay expiry rejects an unactivated reader;
- prove with a synthetic Mac source that an activated reader can submit only a bounded, short-lived manual Codex refresh request, the Mac can poll it without consuming it, and the reader recognizes completion only from a matching authenticated encrypted result; test revocation, duplicate/replayed IDs, source failure, publication failure, expiry, and a sleeping Mac;
- verify Worker logs and traces are disabled and error responses never contain secrets or ciphertext;
- drive each Free quota to a safe synthetic boundary where practical, confirm that excess work fails without an upgrade or charge, and verify the Worker route fails closed;
- inspect account-wide usage to prove no unrelated Worker or storage workload invalidates the capacity calculation;
- exercise token replacement and full destroy/re-pair recovery;
- publish from Mac Wi-Fi, then read on an iPhone using cellular only after the Mac disconnects;
- measure p50/p95 round-trip latency, CPU time, requests, rows read/written, and storage for one uninterrupted 30-minute sample at the intended refresh schedule, including manual requests at the accepted per-reader rate limit and the reader's bounded follow-up reads; retain a checked-in 24-hour workload calculation for comparison with daily Free limits, while recognizing that the shortened run does not prove 24-hour stability;
- simulate malformed ciphertext, wrong keys, replay, clock skew, rate limiting, quota exhaustion, Worker failure, and incompatible protocol versions;
- deploy a compatible new version, smoke-test it, promote it, and roll back without corrupting stored state;
- separately in P1-M14 and later owning milestones, re-sign the installable iPhone app and embedded watch app through Sideloadly and confirm Keychain credentials, cached sequence, widgets, local notifications, watch installation, and watch state survive as intended. This installation criterion remains required for Phase 1, but it is not part of the P1-M9 relay-adoption gate because the installable clients do not exist yet.

The P1-M9 relay-adoption gate passes only if every relay criterion above passes: Cloudflare never receives plaintext or a provider credential, stale state remains honest through every relay failure, the owner can repeat deployment and teardown from documentation, and the Cloudflare billing view remains US$0 with no paid subscription or add-on. The separate installation criterion is closed by its owning milestones before Phase 1 closes.

## 11. Owner decisions and remaining validation

Decided: use `workers.dev`; do not require or purchase a custom domain for Reset Radar. This can be revisited only if the owner changes the US$0 requirement or explicitly treats an already-owned domain as an external cost.

The owner also decided:

- conditionally accept Cloudflare's account, metadata, and operational trust boundary, with final adoption dependent on this document's synthetic-data spike;
- limit the first version to one authoritative publishing Mac;
- accept foreground/manual plus opportunistic background refresh without reserving a paid Apple Developer/APNs path; and
- select separate source-specific refresh and stale thresholds from P1-M2 tests instead of fixing arbitrary values now.

No real usage data or provider adapter may connect to the relay before the spike passes. The complete decision is recorded in [Phase 1 owner decisions](../phase-1/owner-decisions.md).

## Sources

Checked 2026-10-19:

- [Cloudflare: Durable Object storage](https://developers.cloudflare.com/durable-objects/best-practices/access-durable-objects-storage/): transactional and strongly consistent storage, SQLite recommendation, `deleteAll()`, and point-in-time recovery.
- [Cloudflare: Durable Object limits](https://developers.cloudflare.com/durable-objects/platform/limits/): Free-plan availability, storage, object, and request constraints.
- [Cloudflare: Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/): Workers, Durable Objects, KV, storage, and Free-plan allocations.
- [Cloudflare: Workers limits](https://developers.cloudflare.com/workers/platform/limits/): requests, CPU, memory, failure behavior, and fail-closed routing.
- [Cloudflare: `workers.dev`](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/): included hostname and intended personal/hobby use.
- [Cloudflare: How KV works](https://developers.cloudflare.com/kv/concepts/how-kv-works/): eventual consistency and the recommendation to use Durable Objects for atomic coordination.
- [Cloudflare: KV writes](https://developers.cloudflare.com/kv/api/write-key-value-pairs/): one-write-per-second/key limit and expiration behavior.
- [Cloudflare: Worker secrets](https://developers.cloudflare.com/workers/configuration/secrets/): encrypted secret bindings, required secrets, and local-development handling.
- [Cloudflare: Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/): SHA-256, HMAC, AES-GCM, and timing-safe comparison support.
- [Cloudflare: rate-limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/): fixed windows and stable-identity key guidance.
- [Cloudflare: Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/): invocation metadata, disabling logs, sampling, retention, and plan limits.
- [Cloudflare: error responses](https://developers.cloudflare.com/fundamentals/reference/error-responses/): structured JSON content negotiation, stable platform error fields, and the Error 1027 rate-limit category.
- [Cloudflare: Observability pricing](https://developers.cloudflare.com/observability/pricing/): the 2026-12-01 pricing change, Free ingestion allowance, and stop-ingestion behavior.
- [Cloudflare: versions and deployments](https://developers.cloudflare.com/workers/versions-and-deployments/): immutable versions, promotion, version URLs, and rollback limits.
- [Cloudflare: Durable Object data location](https://developers.cloudflare.com/durable-objects/reference/data-location/): jurisdiction scope and metadata caveats.
- [Apple: CryptoKit `SymmetricKey`](https://developer.apple.com/documentation/cryptokit/symmetrickey): random symmetric keys and AES-GCM use.
- [Apple: AES-GCM sealing](https://developer.apple.com/documentation/cryptokit/aes/gcm/seal%28_%3Ausing%3Anonce%3A%29): authenticated encryption and generated nonces.
- [Apple: restricting Keychain accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility): device-only and background-access tradeoffs.
