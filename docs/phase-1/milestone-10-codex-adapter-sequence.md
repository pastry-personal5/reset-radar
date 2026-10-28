# P1-M10: Codex adapter sequencing

Status: Active

Work order and acceptance tests for the
[M10 overview](milestone-10-codex-adapter-overview.md). The binding behavior remains in
[ProviderAdapters](../architecture/provider-adapters.md); this sequence names implementation
seams, test-first order, checkpoints, and the owner-run calibration boundary.

## Constraints

- Codex-specific production code stays in
  `ResetRadarKit/Sources/ResetRadarProviderAdapters/Codex/` and provider tests in
  `ResetRadarKit/Tests/ResetRadarProviderAdaptersTests/Codex/`. Account-aware changes stay in the
  module that owns each contract; relay v2 code stays in the existing Transport and relay roots.
  Shared test fixtures contain only synthetic values and live beside their owning tests unless an
  existing repository fixture is intentionally shared across modules.
- ProviderAdapters imports only Domain, Application, and Foundation. Use Swift 6 strict
  concurrency and Swift Testing. Do not add a package, executable target, build tool, shell
  runtime path, or external service.
- Use injected clocks, sleepers, process sessions, executable metadata, and configuration storage
  for deterministic tests. Keep a small real-`Process` boundary suite for incremental pipes,
  termination, and environment forwarding; do not make every source test spawn a process.
- Never copy production logic from the JavaScript calibration harness. It is reviewed behavioral
  evidence and may supply synthetic fixture shapes; Swift owns its own bounded reader, decoder,
  state machine, and tests.
- Raw app-server stdout/stderr and provider or profile values never reach logs, diagnostics,
  assertion messages, thrown error descriptions, snapshots beyond allowlisted fields, or checked-
  in evidence. Fixture sentinels make leakage assertions deterministic.
- Actual Mac, iPhone/iPad, and Watch SwiftUI screens remain M13, M14, and M16 work. M10 revises
  the binding UX documents, shared account types, read models, and selection contracts only.
- `/v2/refresh-requests` receives offline Swift and TypeScript validation only. M10 never deploys,
  contacts Cloudflare, publishes real usage, or performs or manages M9 work.
- Run focused ProviderAdapters tests while iterating and the complete
  [gate](../contribution-guide.md#required-validation) at the baseline, each checkpoint, and
  close-out. Delegate command execution and first-pass failure analysis to `test_runner`.

## Commit strategy

Prefer one conventional commit per checkpoint: account/configuration/process boundary,
schema/source/refresh behavior, and calibration close-out. A commit is eligible only after its
complete gate passes. Do not mix unrelated M9 or M11 work into M10 evidence or commits.

## Task 0: Decisions, branch, and baseline

Record the implementation branch, starting commit, and `git status --short`. Record the resolved
owner decisions in the changelog, overview, binding UX documents, and affected architecture before
code uses them. Set M10 to `Active` when that implementation work begins.

Add the approved Domain and Application dependencies to `ResetRadarProviderAdaptersTests`.
Record current Swift, Xcode, Codex, and `codex-profile` public version strings without paths or
profile names. Preserve the already recorded delegated clean baseline gate.

Done when the overview entry criteria contain concrete evidence and no open decision is embedded
as an implementation assumption.

## Task 1: Make Codex calibration independent and runnable

Before any signed-in read, reconcile the maintained runbook and tracked programs:

1. Replace the stale exact-branch claim with the repository's actual tracked-program arrangement.
   Require the approved clean M10 revision and verify that the worktree stays unchanged throughout
   the live run; do not claim that the programs exist only on an absent disposable branch.
2. Add an explicit Codex-only mode through preparation, installed-schema preflight, verifier,
   cleanup, and evidence instructions. It must not inspect Claude settings/history, require the
   `claude` executable, create Claude session IDs/files, wait 65 minutes, or delete Claude data.
   Preserve the combined mode for later M11 only if its behavior remains tested and documented.
3. Extend the sanitized Codex projection and verifier with account-identifier presence/type, never
   its value. Verify the installed `account/read` request and only the response types needed for
   account presence and `requiresOpenaiAuth`; do not retain any account field. Keep profile names,
   `CODEX_HOME`, executable paths, bucket/limit IDs,
   percentages, resets, prompts, responses, and raw frames private and ephemeral.
4. Keep exact profile enumeration, hidden input, per-profile launchers/reports, repository-state
   verification, owner-only permissions, randomized `/private/tmp` storage, and narrow cleanup.
   A failed cleanup never broadens a path or deletes by wildcard.

Offline tests cover argument/mode validation, one and multiple profiles, duplicate selection,
wrong revision or dirty-worktree refusal, absent/malformed installed schemas, bounds, default-
bucket ambiguity, account-ID absent/wrong-type/present classification, the approved structured
sign-in combinations, verifier pass/fail/deferred results, output redaction, and exact cleanup
scope. Align the calibration string measurement with the production 4-KiB decoded-UTF-8 rule and
report bucket-entry as well as candidate-window maxima. Run JavaScript and Zsh syntax checks. Then
the owner runs only installed-schema generation (no account or usage read) for every selected
profile.

If preflight contradicts the selected methods or fields, including the approved sign-in
discriminator, stop. Update the research and return the source choice to the owner; do not patch a
live request from raw output.

## Task 2: Account contracts, configuration, discovery, and storage

Write failing Domain and Application tests before changing contracts. Add a random 128-bit
`AccountID`, account metadata, account-aware source/window identity and standard-window selection,
account-scoped read models, a `ReadReceipt` that distinguishes a performed physical read from an
immediately deferred backoff result, and inner `UsageSnapshot` schema 2. A catalog is valid only
when IDs and global account numbers are unique, effective display labels do not exactly repeat,
every source/window refers to a same-product account, and it contains any number of Codex accounts
and one Claude Code account. The smallest unused positive number is assigned only on successful
apply.

Add generic opaque configuration-option identity, preview revision, owner-visible preview
metadata, selected add/replace intent, confirmed removal, and an `incompatible` state. Add an
account-catalog/alias port and use case. Aliases are optional, at most 32 UTF-8 bytes, use the
Domain safe Unicode profile, require at least one visible letter/number/punctuation/symbol, and
reject exact effective-label duplicates. Accepted values preserve case and leading/trailing ASCII
spaces without normalization; empty input restores the default. Extend tests for every allowed
and rejected Unicode category, combining-mark-only and whitespace-only input, byte boundaries,
metadata-only publication, localized natural ordering inputs, stable identity across replacement,
number reuse after removal, option mismatch, altered/stale preview, rediscovery drift,
confirmation, incompatible inspection, and apply failure.

Implement these ProviderAdapters seams, with exact public names finalized during review:

- `CodexExecutableLocator`: bounded owner-present explicit-path, login-shell `command -v`, and
  standard-Homebrew discovery in that order. Login-shell discovery has a timeout and output cap,
  accepts exactly one absolute executable result, and never evaluates its result as shell text.
  Canonicalize a symlink only for identity checks while retaining the owner-confirmed invocation
  path; require a regular executable with safe ownership/mode, and reject an empty, relative, or
  current-directory `PATH` component. Inspect a bounded shebang; when it uses `/usr/bin/env node`,
  resolve the first `node` from that exact `PATH` without a shell and bind its canonical identity
  into preview, apply revalidation, configuration, and runtime change detection.
- `ProviderAccountCatalogStore` and `CodexConfigurationStore`: a locked owner-only account index
  plus isolated per-account launch files. The index contains only schema version, random
  `AccountID`, stable number, product, optional alias, and configuration revision. Each launch file
  contains the resolved executable and applicable interpreter identity, confirmed `HOME`, `USER`,
  `LANG`, `PATH`, optional confirmed `CODEX_HOME`, and preview revision. File-size caps, strict
  validation, symlink-safe ownership, and `0700`/`0600` modes precede replacement. Corruption in
  one launch file marks only that account incompatible. No provider identifier, separate profile-
  name field, or usage enters either file.
- `CodexConfigurator: SourceConfigurator`: inspect, enumerate/select as approved, preview the
  exact executable and complete allowlisted environment (four required values plus optional
  `CODEX_HOME`), apply only that unchanged preview after confirmation and revalidation, atomically
  add or replace Codex accounts without a fixed count limit, and remove only the confirmed Reset Radar account
  configuration. Replacement keeps the row ID, number, and alias while clearing old scoped
  windows; removal deletes metadata and makes the number reusable.
- `CodexExecutableMetadata`: bounded `--version` read plus Codex and applicable Node file identity
  and modification time, used to restart after an upgrade or replacement without logging a path.
  Normalize only the expected bounded public version grammar; reject multiline, path-like, or
  otherwise unrecognized output instead of relaying arbitrary process text as
  the account source's public version.

Discovery tests cover an explicit choice, sparse login-item environment, missing `node`, missing
or non-executable files, unsafe owner/mode, symlink/replacement behavior, an empty or relative
`PATH` component, native and `/usr/bin/env node` launchers, missing/reordered/replaced `node`,
multiline/oversized discovery and version output, timeout, absent and explicit `CODEX_HOME`, three
or more profiles, preview substitution and rediscovery drift, write interruption,
parent/file permissions, isolated incompatible config versions, confirmed replacement/removal,
alias validation, and account-number reuse. No test reads a real provider home.

## Task 3: Child process and bounded JSON-RPC

Implement `ChildProcessHost`, an injectable process-session protocol, `BoundedRPCFrame`, and
`JSONRPCClient`. The real host launches the configured executable directly with
`app-server --strict-config -c analytics.enabled=false --listen stdio://`, supplies only the
approved environment, gives stdin/stdout/stderr separate pipes, and never invokes a shell.

`BoundedRPCFrame` consumes arbitrary byte chunks and emits newline-delimited frames. The 1-MiB cap
counts payload bytes before and excluding the line delimiter. It rejects an unterminated buffer as
soon as it exceeds the cap and rejects a completed oversized frame before decode. Empty lines are
ignored. LF is the delimiter; one immediately preceding CR forms a CRLF delimiter, and neither
terminator byte counts toward the payload cap. A standalone CR remains payload. The incremental
reader may hold one trailing CR until the next byte resolves it without treating that pending byte
as an over-limit payload. Before semantic `Decodable` work, an iterative JSON lexical/structural
preflight validates UTF-8 and JSON tokens, rejects duplicate object members, measures decoded
object keys and string values at no more than 4 KiB of UTF-8 each (including escape expansion),
and rejects nesting beyond 32. It never includes a raw key or value in an error. The corrected
ProviderAdapters architecture uses this newline-payload definition; the selected stdio transport
has no length header.

`JSONRPCClient` assigns monotonically increasing positive integer request IDs through
`2^53 - 1`, refuses overflow instead of reusing an ID, correlates exactly one response, and
validates JSON-RPC version and result/error exclusivity. It completes every pending request exactly
once on process exit and routes only the allowlisted sparse update notification. Initialization is
`initialize`, successful response, then `initialized`; account-status and rate-limit reads cannot
start earlier. Each request has an injected ten-second deadline. Unknown additive fields and
well-formed unknown notifications are ignored; server-to-client requests, duplicate/late response
IDs, invalid mixed envelopes, and response-type confusion terminate the session. Every callback
carries a session generation so a replaced or stopped child's response, notification, timeout, or
exit is inert.

Drain and discard stderr incrementally under a fixed chunk size. Launch in the fixed app-owned
working directory with exactly the confirmed environment. On stop, cancel timers, close stdin
once, allow five seconds for exit, then terminate the child without hanging. Tests split every
frame at every boundary, combine frames in one chunk, exercise the decided CRLF behavior, and
cover exact/over frame and decoded-string limits; escaped Unicode; exact/over nesting; duplicate
keys; invalid UTF-8/JSON; missing newline; stdout EOF; stderr flood; request-ID exhaustion;
late/duplicate/unknown IDs; server requests; JSON-RPC errors; timeout/cancellation races;
stdin-close exit; forced termination; stale-generation callbacks; minimal exact environment; safe
working directory; and sentinel redaction.

**Checkpoint A:** Tasks 0 to 3 pass focused tests and the complete gate, are reviewed, and are
committed before response normalization begins.

## Task 4: Rate-limit decoding and normalization

Implement `RateLimitDecoder` over allowlisted intermediate types and `CodexNormalizer`. Decode
only the approved account-status discriminator, the account identifier needed by `AccountScoper`,
source/version metadata needed for compatibility, `rateLimits`, `rateLimitsByLimitId`, bucket
identity/label, primary and secondary windows, used percentage, duration, reset,
`rateLimitReachedType`, and `ordinaryUsageAllowed`. Ignore email, display name, auth material,
workspace data, credits, plan, upsell, spend-control, and every unknown field.

Apply these rules:

- Require a valid provider account identifier and pass it directly to `AccountScoper`; release it
  after scoping. It never enters an intermediate description, diagnostic, configuration, or
  fixture evidence. Stamp every output with the configured Reset Radar `AccountID` separately
  from that opaque provider scope.
- Classify `signedOut` only from the approved `account/read` combination. A non-ChatGPT account,
  missing/wrong-type discriminator, account-status error, or generic rate-limit JSON-RPC error is
  never classified by matching its message. Apply the architecture's exhaustive
  [account-status matrix](../architecture/provider-adapters.md#account-status).
- Accept at most 128 multi-bucket entries and 128 total compatibility-plus-map candidate windows.
  Every map key is a provider identity. A present embedded `limitId` must equal its key, and map
  identities must be unique. Reject identity disagreement or duplication before constructing a
  `WindowID`.
- Reconcile the compatibility snapshot to exactly one multi-bucket entry. First use a unique
  validated provider-identity match; use complete allowlisted structural equality only when no
  identity match exists. Never use structural equality to override ambiguous or contradictory
  identity. Emit the selected map bucket once with `isDefaultLimit == true`. With no multi-bucket
  map, emit the compatible snapshot as the default only when it has a valid provider identity.
  Ambiguous or missing identity makes the complete response incompatible; never invent `default`
  as a provider ID.
- Classify windows by provider limit identity plus explicit positive duration, not
  primary/secondary position. Preserve unknown valid bucket IDs and labels. A missing duration or
  reset remains nil. Convert integer Unix seconds to a finite absolute `Date`; reject invalid
  numeric precision or range.
- Preserve integer percentage used with `fractionDigits == 0`. Never invert, clamp, or infer a
  reset percentage. Apply the approved provider-state precedence per bucket without reading
  percentage as state or treating spend-control state as an allowance state.
- Stamp every valid window from one response with the injected receipt time and source version.
  Reject duplicate constructed `WindowID`s within the response. Count all decoded compatibility
  and map candidates before normalization so duplicates and invalid windows cannot evade the
  bound. If no allowance window survives, return the approved state-only failure instead of a
  successful empty complete report.

Fixtures cover a compatibility-only response; a uniquely matching multi-bucket response; two
same-duration buckets; same-bucket duplicate `WindowID`; structurally equal fallback and
ambiguity; identity-match precedence; compatibility/map identity disagreement; repeated embedded
identity; unknown buckets; missing/empty identity; missing duration/reset; absent account ID;
account-scope failure; every approved account-status combination; signed-out and generic JSON-RPC
error codes at every standard/reserved/unknown boundary; reached/allowed/disallowed/unknown
precedence; percentages below zero, at 0/100, fractional, and above 100; invalid epoch values;
nulls and type confusion; unknown additive fields; 128/129 buckets and candidate windows; zero
surviving windows; overlong ignored and allowlisted strings; and two synthetic accounts. Assert
invalid siblings are dropped only when response-level identity and default mapping remain sound.
Cross-account tests prove that identical provider limit IDs do not collide and that a provider
scope change clears only the affected local account.

## Task 5: Source actor, schedule, and Application integration

Implement `CodexSchedule` as pure deadline/coalescing policy and one
`CodexAppServerSource: UsageSource` actor per configured account. Each actor owns only its launch
configuration, process, RPC client, tasks, latest timers, update stream, read gate, and backoff. A
small fleet/coordinator starts both actors concurrently, routes account/all-account refreshes, and
deterministically resolves duplicate provider scopes.

- `start()` is idempotent, loads that account's valid configuration, starts/initializes one child,
  attempts one complete read, then arms the polling or retry timers allowed by its outcome.
  Expected operational failures publish the approved state-only result and leave the runtime
  available for its retry policy; they do not escape `start()` and silently remove collection. A
  terminal `stop()` makes a later `start()` fail deterministically without launching.
- Poll every five minutes while started. A sparse update always schedules a full refetch, but no
  notification-derived read starts within 60 seconds of the prior notification refetch. An update
  received after the active request was sent records one trailing notification refetch at the
  first allowed instant; that newer update is not considered satisfied by the older request.
- From every latest complete report, replace the reset timer set and schedule one read 30 seconds
  after each distinct future reset. A newer report cancels obsolete reset timers.
- `refresh()` starts immediately when that account has neither a read nor restart backoff active.
  Concurrent poll, reset, notification, foreground, wake, and manual callers await the same read
  and receive the same performed receipt describing that actual attempt; no second process or
  parallel request is created for that account. During active backoff it returns an immediate
  deferred receipt carrying the retry deadline and current source state, launches nothing, and
  cannot count as `codexRead`. Its sibling remains independent.
- A configuration, executable version, or executable modification change stops the old child and
  creates a new session generation before reading. A stale generation cannot publish or mutate
  scheduling. Failure emits one typed state-only report and follows the approved retry table;
  eligible failures use one/two/five/fifteen-minute restart delays, and success resets backoff.
- `stop()` is idempotent, cancels pending poll/reset/backoff work, closes the child, finishes the
  update stream once, and prevents a late response from publishing.

Implement the approved
[source-state and retry matrix](../architecture/provider-adapters.md#source-states-and-retry)
exhaustively for not configured/installed, unsafe permissions, proven signed-out,
incompatible/malformed, timeout/process/pipe exit, temporary backend failure, account-scoper
failure, and duplicate provider scope. Record only approved enum-backed diagnostics through the
injected `DiagnosticsSink`; never embed a provider error message. A failed performed read returns
`succeeded == false` and a state-only report when one was produced; a complete performed read
returns `succeeded == true` and the exact normalized report. A deferred receipt has no fake start,
finish, success, or report. Each physical read yields at most one update-stream event, while every
coalesced explicit caller receives the same receipt; the manual-request use case may ingest that
report again to order publication, which is idempotent in Application.
The source does not persist the last valid windows; `CollectUsage` owns that state. When a valid
new provider scope is known, it clears only that row's prior-scope windows even if the new result
must remain state-only. Missing identity cannot trigger that transition. If two profiles resolve
to the same provider scope, the lower-numbered row remains active and the other publishes an
incompatible state without retaining misleading prior-account windows.

Use injected clocks/sleepers and fake process sessions to test exact edges, concurrent startup, a
notification before versus after request send, simultaneous triggers, cancel/re-arm behavior, no
reads or restarts after stop, stale generation callbacks, process replacement, every retry/non-
retry class, independent sibling backoff, both startup race orders for a duplicate provider scope,
one stream event per physical read, identical coalesced receipts, immediate deferred receipts that
never satisfy a manual read, and stream termination. Run real `CollectUsage` integrations over an
in-memory store and fake `AccountScoper` to prove reports replace scopes only within one row,
ordinary state-only failures preserve windows, identity transitions clear old-account windows,
and account/all-account refresh yields the receipts consumed by `HandleManualRefreshRequests`.

Add the account-aware manual-refresh and delivery contracts:

- `ManualRefreshTarget` is one opaque `AccountID` or `allCodex`; a stale or non-Codex target returns a
  typed account-unavailable result without launching another source.
- One result contains a bounded per-account outcome set. Successful reports are ingested and
  published even when another targeted account fails.
- `/v2/refresh-requests` uses strict canonical protocol-version-2 bodies and responses, preserves
  the reader-global 60-second rate limit, and stores only target kind plus optional opaque account
  ID. Snapshot, pairing, encryption, and envelope operations remain v1.
- The Durable Object migrates its internal SQL schema in place, preserves relay state/readers/the
  stored snapshot, and discards only legacy or expired pending refresh rows. The old refresh route
  is not a compatibility path.
- `PendingManualRequest`, reader recovery, replay detection, result retention, Watch stripping,
  and HTTP size/response bounds change together. All relay evidence is offline; no deployment or
  Cloudflare request occurs.

**Checkpoint B:** Tasks 4 and 5, focused ProviderAdapters tests, Application regressions, and the
complete gate pass and are committed.

## Task 6: Owner calibration and close-out

After Checkpoint B is reviewable, the owner follows the repaired Codex-only runbook on the owner's
Mac. The agent may prepare and review commands but never types a profile name, handles the
disposable report, starts a signed-in process, or receives raw output.

For both explicitly selected profiles, the owner runs installed-schema preflight, one initial and
six five-minute reads over 30 minutes, and one ordinary owner-controlled Codex turn per profile to
observe the sparse update/refetch path. The verifier requires the approved method/field
shapes, ten-second response ceiling, legitimate frames/strings/depth/bucket/window measurements
below the approved bounds, unambiguous default bucket, approved account-identifier presence/type,
approved account-status discriminator shape, no scheduled-read gap over 15 minutes, and process
exit within five seconds of stdin close. Exact-bound rejection remains synthetic-test evidence;
the live run never injects malformed input. It reports a missing update notification as deferred,
never passed.

The owner has approved `15 minutes confirmed` when both anonymous ordinals satisfy every defined
criterion. A rejection, legitimate bound violation, missing identity, ambiguous default bucket, or incompatible
installed schema stops close-out and returns the relevant rule to the owner. Do not widen a bound,
drop a profile, read credentials, dump JSON, or substitute another endpoint.

After verified cleanup, append one sanitized Codex calibration entry to
[spike-results.md](../research/spike-results.md). If all profiles pass and the owner
confirms 15 minutes, remove the candidate wording for Codex in `CurrentDataWindow` and affected
docs without changing Claude Code's candidate status.

Remove the ProviderAdapters scaffold source/test, run repository searches for their symbols and
for forbidden fixture sentinels, update the overview checklist, phase plan, docs index, architecture
wording, and changelog. Have the `test_runner` run focused tests and the complete gate. Inspect
`git diff --stat`, then the complete diff, `git diff --check`, and relative Markdown links. Mark
M10 `Done` only when every non-deferred required item has direct evidence; a deferred update
notification is documented for M12 operational observation and does not masquerade as proof.

## Review focus

1. Each owner-confirmed profile/environment reaches only its own process launch;
   no ambient, sibling, or previously selected profile can supply a response after replacement.
2. Byte and structural bounds are enforced before semantic decoding, and every exit path drains or
   closes pipes without hanging or retaining raw data. Duplicate JSON keys, decoded escape growth,
   empty-bucket floods, and stale process generations fail closed.
3. Compatibility/default-bucket reconciliation emits no duplicate and never marks two buckets
   default; account and limit identity are provider-derived or the response fails closed.
4. Coalescing preserves one actual receipt for all callers of the same account while sibling
   accounts remain independent. Notification throttling, reset scheduling, polling, and restart
   backoff remain distinct rules. A notification newer than the active request always leaves a
   trailing refetch.
5. State-only failures preserve Application-owned windows and never advance observations; a
   complete response alone changes provider windows. Sign-out is proven structurally, never from
   provider prose, and every failure class has one approved state and retry behavior.
6. Live calibration evidence is structural, sanitized, owner-run, and cleaned before repository
   edits. It proves the installed versions observed that day, not future compatibility.
7. M10 remains locally validated: refresh v2 is tested offline, and no Cloudflare request, relay
   secret, real publication, Claude settings mutation, platform SwiftUI implementation, or Mac
   composition-root behavior enters its acceptance evidence.
