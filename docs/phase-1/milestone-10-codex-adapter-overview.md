# P1-M10: Codex adapter overview

Status: Planned

Implement the macOS-only Codex app-server half of
`ResetRadarProviderAdapters` against the existing Domain and Application ports. The
[sequence](milestone-10-codex-adapter-sequence.md) orders configuration, bounded JSON-RPC,
normalization, scheduling, synthetic tests, and the owner-present signed-in calibration.

## Goal

One explicitly selected Codex profile can be read through its first-party
`codex app-server --listen stdio://` process without Reset Radar reading or copying a provider
credential. Successful responses become complete `SourceSnapshot`s with every valid limit
bucket, an opaque account scope, the compatibility bucket marked as default, provider-reported
percentage used, and absolute reset instants. Source failures produce typed state-only reports,
retain the last valid windows, and retry on the approved bounded schedule.

The adapter and its synthetic tests pass the complete
[contribution-guide gate](../contribution-guide.md#required-validation). The owner-present
calibration separately proves the installed Codex schema, bounds, profile isolation, response
latency, clean shutdown, update notification behavior, and the proposed 15-minute current-data
window without retaining raw usage or identity data.

## Why this milestone can proceed

[Phase 1](phase-1.md#order-and-dependencies) allows M10 and M11 to run in parallel with M6 to
M9 after M5. M5 is done and supplies `UsageSource`, `SourceConfigurator`, `AccountScoper`,
`ReadReceipt`, and the source-preserving reducer behavior. The ProviderAdapters target and test
target exist but contain only scaffold symbols.

M9 is not an M10 dependency. This milestone is entirely local: it does not publish a snapshot,
connect to Cloudflare, handle a relay secret, or authorize real usage to cross the relay gate.
M12 owns composition into the Mac collector.

## Planning basis

- [ProviderAdapters](../architecture/provider-adapters.md) defines process isolation, allowed
  fields, the Codex schedule, error classes, input bounds, and adapter dependencies.
- [Upstream automatic usage sources](../research/phase-1/upstream-automatic-usage-sources.md)
  pins the selected app-server methods, field meanings, and normalization rules.
- The [source-calibration runbook](../research/phase-1/source-calibration-spike-runbook.md)
  defines the privacy boundary and owner-run evidence. Task 1 must repair the workflow issues
  identified in [Plan review](#plan-review) before it is run.
- [Domain](../architecture/domain.md) defines `SourceSnapshot`, account scope, window identity,
  percentage validation, and retained-window behavior. [Application](../architecture/application.md)
  owns ingestion and manual-refresh use cases; ProviderAdapters does not reproduce them.
- The current implementation contracts are
  `UsageSource.refresh() -> ReadReceipt`, `SourceConfigurator`, and `AccountScoper`. Any port
  change requires the owner decision below, focused Application regression tests, and a
  changelog entry before adapter code depends on it.

## Entry criteria

- [x] The M10 overview and sequence are linked from the phase plan and documentation index and
  reviewed against the binding architecture, current package, source-calibration workflow, and
  M5 ports. Evidence: the plan review below and the 2026-10-24 changelog entry.
- [x] The enhanced plan resolves the follow-up contract, lifecycle, scheduling, privacy, and
  verification findings recorded in [Plan review](#plan-review), with delegated validation
  evidence and no signed-in provider access. Evidence: the follow-up result under
  [Plan validation](#plan-validation) and the 2026-10-24 changelog entry.
- [ ] The owner answers all [implementation decisions](#implementation-decisions), and the
  answers are recorded in [changelog.md](changelog.md) and the binding docs they affect.
- [ ] Record the implementation branch, starting commit, and complete worktree state. Preserve
  unrelated concurrent M9 and M11 work as separate pre-existing work.
- [ ] The `test_runner` passes the complete gate on the recorded baseline before production
  implementation begins.
- [ ] Task 1 makes the Codex calibration independently runnable, passes every offline test and
  installed-schema preflight, and retains the runbook's privacy and cleanup boundaries.

## In scope

- An owner-confirmed Codex launch configuration for one approved profile selection, persisted
  locally with owner-only permissions and never included in diagnostics.
- Bounded executable discovery and validation, an owner-confirmed minimal child environment,
  version/change detection, direct `Process` launch without a shell, stale-session fencing,
  bounded pipe handling, and clean stop.
- A newline-delimited JSON-RPC client with initialization, request correlation, timeouts,
  notification dispatch, and a one-MiB pre-decode frame limit.
- Additive decoding of `account/rateLimits/read` and the approved optional account-status read,
  strict validation of the allowlisted fields, account scoping, default-bucket reconciliation,
  and normalization of all valid buckets.
- The `CodexAppServerSource` actor and `CodexSchedule`: five-minute polling, notification refetch
  no more than once per 60 seconds, reset reads after 30 seconds, immediate coalesced refresh,
  ten-second request timeouts, and one/two/five/fifteen-minute restart backoff.
- Typed source outcomes and retry policies for not installed, signed out, incompatible, timeout,
  process exit, malformed input, permission denial, account-scope failure, and temporary
  unavailability, with redacted diagnostics.
- Synthetic unit and integration fixtures plus the owner-present Codex half of source
  calibration. Only sanitized structural and timing evidence enters the repository.
- Necessary focused Domain/Application contract changes approved below, their tests, removal of
  the ProviderAdapters scaffold, and affected active documentation.

## Out of scope

- Claude Code parsing, session records, helper installation, settings edits, or its 60-minute
  calibration (P1-M11).
- Mac collector wiring, launch at login, UI, Keychain, publication, or timer-drift observation
  (P1-M12 and M13).
- Relay deployment or any local or remote publication of real usage (M9 and M12). The live
  calibration talks only to the already signed-in first-party Codex process.
- Concurrent collection from multiple Codex profiles unless the owner rejects the recommended
  single-selection rule below. Calibration may still test every owner-designated profile.
- Reading a Codex authentication file, browser state, consumer token, prompt, response, project
  path, or private endpoint; API-key mode; dependencies; or a new build tool.
- Treating missing duration, reset, account identity, or limit identity as a guessed value.

## Security and privacy invariants

- Launch only the reviewed absolute executable and explicit profile environment. Never invoke a
  shell for app-server, search a changed ambient `PATH` after configuration, or fall back to an
  unselected profile.
- Pass only the confirmed `HOME`, `USER`, `LANG`, `PATH`, and optional `CODEX_HOME`. `PATH` has
  only absolute non-empty entries, and the child starts in a fixed app-owned directory so a
  relative working directory cannot select `node` or other code.
- The owner-only launch-configuration file may contain the confirmed executable and environment
  paths needed to reproduce the selection. Normalized `SourceSnapshot`s may contain the approved
  percentage, reset, limit identity, opaque account scope, and public source version. Those are
  the only persistence exceptions. Provider account identifiers, raw JSON-RPC bytes, stderr,
  profile names, prompts, responses, and every rejected or ignored field are never persisted or
  logged; launch paths and normalized usage values never enter diagnostics or calibration
  evidence.
- Drain stderr in bounded chunks and discard it. Bound stdout before decoding: one frame at most
  1 MiB, each decoded key or string at most 4 KiB of UTF-8, nesting at most 32 levels, at most 128
  multi-bucket entries, and at most 128 decoded candidate windows. A violation terminates the
  child, emits a redacted state-only failure, and preserves the last valid observation.
- Unknown additive response fields are ignored. Missing or invalid required identity, percentage,
  or structural fields fail closed; valid sibling windows survive only when the enclosing
  response identity and default-bucket mapping remain unambiguous.
- `observedAt` is the injected Mac time when a complete read response arrives. The adapter never
  advances it from a sparse notification, failed read, reset timer, or retry.
- All tests and checked-in fixtures are synthetic. The owner alone runs signed-in commands and
  completes cleanup before sanitized evidence is written.

## Implementation decisions

These are newly exposed M10 choices, not permission to invent behavior. Implementation remains
blocked until the owner answers all seven.

1. **First-version profile cardinality.** Recommend exactly one active Codex profile selection.
   Setup may calibrate and offer multiple profiles, but applying a new selection atomically
   replaces the prior launch configuration and restarts the child; it does not run concurrent
   sources. Supporting several accounts at once would require product-facing account selection,
   duplicate Home-slot rules, and publication semantics outside the approved first version.
2. **Profile-aware configuration contract.** The current `SourceConfigurator` can return only
   `configured`, `unsafe`, or `notConfigured` and a generic `discover` preview; it cannot carry a
   selected option or show the exact executable/environment that the owner must confirm.
   Recommend a minimal generic option/preview addition in Application plus an `incompatible`
   configuration state for corrupt, unsupported-version, or unsafe-permission app-owned state.
   Display-only fields may carry the exact local path and environment for confirmation, but
   Application neither interprets nor persists them, while ProviderAdapters retains the typed
   launch configuration. A provider-generated opaque option ID and preview revision bind apply
   to the exact selected executable, any `/usr/bin/env node` interpreter resolved from `PATH`, and
   all five environment values; apply revalidates them and rejects a stale preview. M12 can then
   list choices, request a preview, and apply only the exact preview the owner confirmed. Do not
   require `codex-profile` at collector runtime; owner-present discovery may use an installed copy
   during setup to resolve a selection into an official Codex executable plus the complete fixed
   launch environment.
3. **Missing account identifier.** Codex documents the account identifier as optional, while
   `SnapshotReducer` can remove prior-account windows only after it receives a different non-nil
   scope. Recommend treating a complete response without a valid account identifier as
   `incompatible`, preserving the last valid windows, rather than hashing a profile path or
   allowing windows from two accounts to mix. Task 1 must record identifier *presence and type*
   for every selected profile without retaining its value. An alternative needs an explicit
   local profile-scope and account-switch clearing design across Domain/Application.
4. **Provider limit state.** The approved Domain enum cannot distinguish
   `ordinaryUsageAllowed: false` from an independently reported reached state. Recommend adding
   the tolerant wire case `ordinaryUsageDisallowed`. Per-bucket recognized
   `rateLimitReachedType` takes precedence and maps to `reached`; otherwise account-wide true maps
   to `ordinaryUsageAllowed`, false to `ordinaryUsageDisallowed`, and absence or an unrecognized
   reached value to `unknown`. Ignore spend-control state and never infer state from percentage
   or reset.
5. **Provider test imports.** Recommend adding the existing local `ResetRadarDomain` and
   `ResetRadarApplication` targets to `ResetRadarProviderAdaptersTests`. This is not an external
   dependency, but it is a `Package.swift` dependency-graph change and therefore needs owner
   approval. It permits direct contract, fake `AccountScoper`, and normalized-record tests under
   the explicit-import gate.
6. **Machine-readable sign-in state.** The selected rate-limit call reports signed-out as a
   generic JSON-RPC invalid-request error; matching its human `message` would be brittle and could
   leak provider text. The first-party app-server also exposes `account/read` with a structured
   nullable account and `requiresOpenaiAuth` flag. Recommend allowing that one additional
   read-only method, with `refreshToken: false`, solely once after initialization before the first
   rate-limit read and again after a generic rate-limit error that could represent authentication.
   Decode only account presence/type and the boolean, never email, display name, tokens, workspace
   data, or error prose. A missing method, ambiguous combination, non-ChatGPT account, or failed
   status read is `incompatible` or `sourceOffline` under decision 7, never guessed as
   `signedOut`.
7. **Source failure, retry, and diagnostics contract.** `SourceState` has five product-visible
   cases, while M10 has more failure classes, and the closed `DiagnosticEvent` cannot currently
   express a provider failure category. Recommend an explicit table in ProviderAdapters before
   code: not configured/not installed/unsafe permissions to `unavailable`; a proven structured
   sign-out to `signedOut`; schema, identity, framing, or normalization violations to
   `incompatible`; and timeout, process/pipe exit, temporary backend failure, or account-scoper
   failure to `sourceOffline`. Only retryable running-source failures use the one/two/five/fifteen
   minute restart ladder; setup failures wait for a configuration change, and manual/wake/
   foreground requests respect an active adapter backoff. Add only enum-backed provider
   diagnostic factories carrying product, source state, error class, duration, and time. Keep the
   public source version on `ProductSource` rather than adding arbitrary strings to diagnostics.

## Completion checklist

- [ ] Entry criteria hold with recorded owner decisions, baseline evidence, and no unrelated
  work attributed to M10.
- [ ] Owner-confirmed discovery selects exactly the approved executable/profile environment,
  persists only required launch material with symlink-safe owner-only permissions, rejects stale
  or altered previews, unsafe `PATH` entries, and executable/interpreter substitution, and never
  falls back to an ambient profile.
- [ ] App-server initialization, request matching, sparse-notification dispatch, timeout,
  cancellation, stdout EOF, bounded stderr draining, clean stdin-close shutdown, and
  executable-version/modification restart pass deterministic tests. A session generation fences
  every late response, exit callback, and notification from a replaced or stopped child.
- [ ] The frame reader rejects an unterminated or delivered frame over 1 MiB before JSON decode;
  malformed UTF-8/JSON, duplicate object keys, decoded keys or strings over 4 KiB of UTF-8,
  nesting over 32, more than 128 bucket entries, and more than 128 candidate windows terminate
  that child without leaking input or erasing the last valid observation.
- [ ] Single-bucket, multi-bucket, and compatibility-only fixtures normalize without duplicate
  windows. Exactly the uniquely reconciled compatibility bucket is default; two same-duration
  limits do not collide; map keys and embedded IDs cannot disagree or repeat; unknown limit IDs
  survive; missing identity never gains a fabricated ID or scope; and a response with no valid
  allowance window fails state-only rather than reporting a false successful refresh.
- [ ] Percentages remain provider-reported integer percentage used with `fractionDigits == 0`;
  reset instants remain absolute; missing duration/reset stays nil; invalid windows are rejected
  individually with redacted diagnostics; explicit provider state is never inferred from usage.
- [ ] A valid account identifier crosses only the injected `AccountScoper` call and the output
  contains only its opaque scope. Account change replaces prior scoped windows in a real
  `CollectUsage` integration test; a missing identifier follows the approved fail-closed rule.
- [ ] `start`, five-minute polls, sparse updates, reset-plus-30-second reads, concurrent immediate
  refreshes, `stop`, and one/two/five/fifteen-minute restart backoff are proven with injected
  time. Reads never overlap, notifications refetch no more than once per 60 seconds, and reset
  timers are replaced when a newer complete report changes the distinct reset-deadline set. A
  notification received after an in-flight request started leaves one trailing refetch instead
  of being incorrectly satisfied by the older request.
- [ ] Every failure class maps to the approved source state and a state-only `SourceSnapshot`;
  retry and non-retry behavior follows the approved table. `start()` keeps operational failures
  observable instead of tearing down the runtime, one physical read produces at most one stream
  event, and every coalesced caller receives the same `ReadReceipt`. Receipt times bound the
  actual read and report success only for a complete normalized response. M5 ingestion and
  manual-refresh tests pass with the real adapter seam.
- [ ] Privacy tests prove that configuration contains only approved launch fields and that
  diagnostics, thrown errors, and the app/test process's own output contain no fixture sentinel
  representing an account ID, profile/path, prompt, response, limit ID, percentage, reset, child
  stderr, or raw frame.
- [ ] Owner-present calibration passes for every selected profile: installed schema, initial plus
  six scheduled reads, ten-second latency, legitimate-response measurements below all approved
  input bounds, unambiguous default bucket, account-identifier presence/type, approved sign-in
  discriminator shape, process exit within five seconds, profile isolation, and the 15-minute
  decision. Synthetic tests, not live input, prove rejection at each exact bound. A notification/
  refetch may be explicitly deferred, but is not reported as passed.
- [ ] The calibration cleanup succeeds before one redacted Codex evidence entry is added to
  [spike-results.md](../research/phase-1/spike-results.md). No raw or identifying value enters
  version control.
- [ ] The ProviderAdapters placeholder and smoke test are removed, affected active docs match
  the implementation, and P1-M10 moves to `Done` only after every required item has evidence.
- [ ] The `test_runner` passes the complete contribution-guide gate from the final reviewable
  worktree; focused ProviderAdapters tests, `git diff --check`, and relative Markdown links also
  pass.

## Checkpoints

- **A: Configuration and process boundary** (Tasks 0 to 3): decisions, baseline, calibration
  workflow repair, configuration contract, launch persistence, child host, and bounded framing.
- **B: Schema and source behavior** (Tasks 4 and 5): decoder, normalizer, account scope, source
  actor, schedule, error mapping, and synthetic Application integration.
- **C: Owner calibration and close-out** (Task 6): owner-run signed-in evidence, cleanup, final
  gate, documentation, and M12 handoff.

## Plan review

The 2026-10-24 review traced the proposed milestone against the phase dependency table, M4/M5
contracts, current package and test targets, ProviderAdapters architecture, upstream-source
research, source-calibration programs, and the privacy rules. It found and addressed these plan
gaps:

- The tracked calibration programs are already on the main history, but the runbook says they
  exist only on a disposable `spike/provider-source-calibration` branch and refuses every other
  branch. No such branch currently exists. The workflow must be reconciled before a live run.
- Preparation, verification, cleanup, and evidence currently couple Codex and Claude Code. M10
  and M11 have separate owner-run work and may proceed independently, so Task 1 requires a
  Codex-only path that does not run, mutate, or wait for Claude Code.
- The generic configuration port cannot represent profile choice or the exact launch preview;
  silently hiding that state inside the adapter would bypass M5's owner-confirmation use case.
- The upstream account identifier is optional, while the existing reducer cannot safely evict
  unscoped windows on an account/profile change. The plan makes this an owner decision and
  rejects path-derived identity as an implicit workaround.
- The architecture's wording about a declared frame length did not match the selected stdio
  JSON-lines protocol. It now specifies the one-MiB newline payload bound before decoding instead
  of introducing a second framing dialect.
- The provider test target needs direct access to its inward contracts under the repository's
  explicit-import check. The local dependency change is called out for approval instead of
  appearing incidentally during implementation.

The review found no reason to make M9 a dependency or to broaden M10 into Claude setup, Mac
composition, relay publication, or multi-account product behavior. Plan validation results are
recorded here after the delegated gate completes.

A follow-up review on 2026-10-24 found and corrected additional execution gaps:

- The original privacy sentence forbade persisting the executable, home, percentages, resets,
  and limit IDs even though the plan requires an owner-only launch file and normalized snapshots.
  The invariant now names those narrow exceptions and still excludes every raw, identity, profile,
  rejected-field, diagnostic, and calibration-evidence path.
- The launch configuration pinned only `PATH` and `CODEX_HOME` while the child also inherited
  `HOME`, `USER`, and `LANG`. Preview, storage, validation, and launch now bind the same complete
  five-variable environment, a safe absolute-only `PATH`, a fixed working directory, and the
  executable identity. npm-script discovery also binds the actual `node` selected by that `PATH`.
- The plan promised `signedOut` without a stable discriminator. Official app-server source uses a
  generic invalid-request error for an unauthenticated rate-limit read, while `account/read`
  exposes structured account presence and `requiresOpenaiAuth`. Decision 6 makes the narrow
  read-only status method explicit and forbids matching provider error prose.
- Product-visible source state, retry eligibility, and provider diagnostics were under-specified;
  account-scoper failure was omitted entirely. Decision 7 now requires one exhaustive table and
  keeps diagnostics enum-backed and string-free.
- A replaced child could deliver a late response or notification, and a sparse notification that
  arrived after a request began could be incorrectly coalesced into that older request. The plan
  now requires session-generation fencing and one rate-limited trailing refetch.
- Structural inspection was ambiguous about decoded string units and duplicate keys, while an
  oversized map of empty buckets could evade the window count. It now caps decoded UTF-8, rejects
  duplicate members before semantic decoding, and bounds both bucket entries and candidate
  windows.
- Default-bucket reconciliation did not fully order identity matching, structural fallback,
  duplicate identities, and the zero-valid-window result. The sequence now makes those outcomes
  deterministic and fail-closed.
- Earlier Markdown validation considered tracked files, but both new M10 plan files are still
  untracked in the shared worktree. Follow-up validation must inspect these two paths explicitly;
  the earlier result is not reused as link evidence for their enhanced contents.

## Plan validation

On 2026-10-24, the `test_runner` ran the complete
[contribution-guide gate](../contribution-guide.md#required-validation) on the reviewed planning
worktree. Project generation, Swift format lint, strict SwiftLint with zero violations across 198
files, import checks, the Mac scheme (85 tests in 16 suites plus the Mac smoke test), relay
dependency installation, 23 Workers Vitest tests, TypeScript checking, and the non-deploying
Wrangler dry run passed. `git diff --check` and a fenced-code-aware tracked relative Markdown-link
check also passed. Initial sandbox-only cache, CoreSimulator, Wrangler-log, and local worker
restrictions passed on approved host-access retries. No signed-in provider process, Cloudflare
state, secret, or real usage was accessed.

The `test_runner` repeated the complete gate on the enhanced shared worktree on 2026-10-24.
Project generation with XcodeGen 2.46.0, Swift format lint, strict SwiftLint with zero violations
across 198 files, import checks, the Mac scheme's four reported Swift test groups (71, 238, 85,
and 40 tests) plus the Mac smoke test, relay dependency installation, 24 Workers Vitest tests,
nine Node tests, TypeScript checking, and the non-deploying Wrangler dry run all passed. The
initial Xcode/Swift cache attempt needed the same approved host-access retry. `git diff --check`,
explicit whitespace inspection of both untracked M10 files, and a fenced-code-aware relative
Markdown-link check covering 131 links also passed. No signed-in provider process, profile,
account value, real usage, network deployment, or Cloudflare state was accessed. This validates
the enhanced plan; it does not replace the isolated clean baseline required after the owner
answers all seven decisions and implementation begins.

## Risks

- **Installed-schema drift.** A future Codex version may change methods or fields. Generate and
  inspect the installed schema during calibration, tolerate additive fields, and fail closed on
  missing required semantics rather than adapting from raw live output.
- **Profile confusion.** Login items have sparse environments and the owner has more than one
  profile. Persist the confirmed launch environment and bind every run to it; never consult an
  ambient selector after setup.
- **Unbounded subprocess input.** Pipe APIs can buffer before a decoder sees a frame. The child
  host and frame reader must enforce the byte cap incrementally and kill a violating process.
- **Timer duplication.** Poll, notification, reset, foreground, wake, and manual triggers can
  coincide. One actor-owned read gate and replaceable timer set must coalesce them without
  advancing `observedAt` on skipped or failed work.
- **False privacy confidence.** Synthetic redaction tests cannot prove a live provider emitted no
  sensitive unknown field. Production decodes only allowlisted fields, never renders raw errors,
  and the owner reviews sanitized calibration output before evidence is recorded.
