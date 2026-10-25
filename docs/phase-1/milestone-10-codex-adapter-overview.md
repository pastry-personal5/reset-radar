# P1-M10: Codex adapter overview

Status: Active

Implement the macOS-only, two-account Codex app-server half of
`ResetRadarProviderAdapters` and the account-aware contracts it requires. The
[sequence](milestone-10-codex-adapter-sequence.md) orders the shared account model, revised UX
contracts, configuration, bounded JSON-RPC, normalization, scheduling, synthetic tests, and the
owner-present signed-in calibration.

## Goal

Up to two explicitly selected Codex profiles can be read concurrently through separate
first-party `codex app-server --listen stdio://` processes without Reset Radar reading or copying
a provider credential. Each locally configured account has a stable opaque identifier, global
account number, optional Mac-authored alias, independent source state, and isolated schedule.
Successful responses become complete account-scoped `SourceSnapshot`s with every valid limit
bucket, an opaque provider account scope, the compatibility bucket marked as default,
provider-reported percentage used, and absolute reset instants. Source failures produce typed
state-only reports, preserve only applicable last-valid windows, and retry on the approved
per-account bounded schedule.

The adapter and its synthetic tests pass the complete
[contribution-guide gate](../contribution-guide.md#required-validation). The owner-present
calibration separately proves the installed Codex schema, bounds, profile isolation, response
latency, clean shutdown, update notification behavior, and the proposed 15-minute current-data
window without retaining raw usage or identity data.

## Why this milestone can proceed

[Phase 1](phase-1.md#order-and-dependencies) now makes M10 depend on M5, M7, and M8 because the
owner-expanded account scope revises the implemented Transport and relay refresh contracts. Those
milestones are done: M5 supplies `UsageSource`, `SourceConfigurator`, `AccountScoper`,
`ReadReceipt`, and source-preserving reducer behavior, while M7 and M8 supply the v1 transport and
refresh-request implementation that M10 migrates. The ProviderAdapters target and test target
exist but contain only scaffold symbols. M10 can run in parallel with M9; M11 may prepare its
source-specific work, but production integration waits for M10 Checkpoint A's shared contracts.

M9 is not an M10 dependency. This milestone does not deploy, contact Cloudflare, handle a relay
secret, or publish real usage. It does revise and offline-test the account-targeted manual-refresh
contract at `/v2/refresh-requests`; the owner directed M10 not to run or manage M9. M12 owns
composition into the Mac collector.

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
- [UX GUI](../ux-gui.md), [information architecture](../ux-information-architecture.md), and
  [UX terms](../ux-terms.md) now define the owner-approved Account List, Account Row, and Account
  Details behavior. M10 supplies their shared contracts and read models; M13, M14, and M16 retain
  ownership of the actual Mac, iPhone/iPad, and Watch SwiftUI screens.
- The current implementation contracts are `UsageSource.refresh() -> ReadReceipt`,
  `SourceConfigurator`, `AccountScoper`, product-only sources, and four fixed `HomeSlot`s. The
  approved decisions below replace those assumptions with account-aware contracts and require
  focused Domain, Application, Storage, Transport, relay, and UI-model regression tests.

## Entry criteria

- [x] The M10 overview and sequence are linked from the phase plan and documentation index and
  reviewed against the binding architecture, current package, source-calibration workflow, and
  M5 ports. Evidence: the plan review below and the 2026-10-24 changelog entry.
- [x] The enhanced plan resolves the follow-up contract, lifecycle, scheduling, privacy, and
  verification findings recorded in [Plan review](#plan-review), with delegated validation
  evidence and no signed-in provider access. Evidence: the follow-up result under
  [Plan validation](#plan-validation) and the 2026-10-24 changelog entry.
- [x] The owner answers all [implementation decisions](#owner-decisions), and the
  answers are recorded in [changelog.md](changelog.md) and the binding docs they affect.
  Evidence: the 2026-10-24 Owner/Codex entry and the revised UX GUI, information architecture,
  and terms.
- [x] The revised UX and M10 plans pass a cross-document consistency review covering account
  labels and ordering, empty and unavailable states, refresh affordances, per-window surfaces,
  source-state mapping, retry behavior, and protocol bounds. Evidence: the final delegated gate,
  `git diff --check`, and the active-document link/anchor audit under
  [Plan validation](#plan-validation) pass on the reviewed worktree.
- [x] Record the implementation branch, starting commit, and complete worktree state. Preserve
  unrelated concurrent M9 and M11 work as separate pre-existing work. Evidence: implementation
  branch `feat/p1-m10-codex-adapter` started at `5b4725d` on 2026-10-24 after the then-current M9
  commits were fast-forwarded to `main`; `git status --short` was empty.
- [x] The `test_runner` passes the complete gate on the recorded baseline before production
  implementation begins. Evidence: delegated validation on 2026-10-24 passed project generation,
  Swift format and strict lint, import enforcement, the macOS scheme, 26 relay Vitest tests, 31
  relay Node tests, relay typecheck, and the Wrangler dry run. The Swift/Xcode checks were rerun
  successfully with cache and CoreSimulator access after their sandbox-only first attempt.
- [x] Task 1 makes the Codex calibration independently runnable, passes every offline test and
  installed-schema preflight, and retains the runbook's privacy and cleanup boundaries. Evidence:
  the Codex-only preparation, preflight, verifier, calibration projection, cleanup, and synthetic
  tests pass against public Codex 0.164.0 schemas without starting app-server or reading an
  account; delegated shell/Node validation and the installed-schema checks passed on 2026-10-24.

## In scope

- Owner-confirmed launch configurations for at most two active Codex profiles, persisted with
  owner-only permissions and isolated so one corrupt or unsafe configuration does not stop the
  other account.
- A global account catalog supporting two Codex accounts and one future Claude Code account:
  opaque `AccountID`, smallest-unused stable account number, optional alias of at most 32 UTF-8
  bytes, exact effective-display-label uniqueness, localized display ordering, confirmed removal,
  and replacement that retains the row identity and alias.
- Account-aware Domain/Application/read-model contracts, inner `UsageSnapshot` schema 2, and the
  binding Account List UX documentation. Actual platform screens remain in their UI milestones.
- Bounded executable discovery and validation, an owner-confirmed minimal child environment,
  version/change detection, direct `Process` launch without a shell, stale-session fencing,
  bounded pipe handling, and clean stop.
- A newline-delimited JSON-RPC client with initialization, request correlation, timeouts,
  notification dispatch, and a one-MiB pre-decode frame limit.
- Additive decoding of `account/rateLimits/read` and the approved optional account-status read,
  strict validation of the allowlisted fields, account scoping, default-bucket reconciliation,
  and normalization of all valid buckets.
- One `CodexAppServerSource` actor and `CodexSchedule` per configured account: concurrent startup,
  five-minute polling, notification refetch no more than once per 60 seconds, reset reads after
  30 seconds, immediate per-account coalesced refresh, ten-second request timeouts, and independent
  one/two/five/fifteen-minute restart backoff.
- Typed source outcomes and retry policies for not installed, signed out, incompatible, timeout,
  process exit, malformed input, permission denial, account-scope failure, and temporary
  unavailability, with redacted diagnostics.
- Synthetic unit and integration fixtures plus the owner-present Codex half of source
  calibration. Only sanitized structural and timing evidence enters the repository.
- Account-targeted `/v2/refresh-requests`, per-account result reporting, and an in-place Durable
  Object schema migration, with offline tests only and no deployment or M9 work.
- Necessary focused Domain, Application, Storage, Transport, relay, and UI-model contract changes,
  their tests, removal of the ProviderAdapters scaffold, and affected active documentation.

## Out of scope

- Claude Code parsing, session records, helper installation, settings edits, or its 60-minute
  calibration (P1-M11).
- Mac collector wiring, launch at login, SwiftUI screen implementation, Keychain, publication, or
  timer-drift observation (P1-M12 through M16).
- Relay deployment or any local or remote publication of real usage (M9 and M12). The live
  calibration talks only to the already signed-in first-party Codex process.
- More than two concurrent Codex profiles or more than one Claude Code account in the first
  version.
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
- Owner-only account metadata may contain a random Reset Radar `AccountID`, stable number, and
  optional alias. Per-account launch configuration may contain the confirmed executable and
  environment paths needed to reproduce that selection. End-to-end encrypted snapshots may
  contain the account metadata, approved percentage, reset, limit identity, opaque provider scope,
  and public source version. Provider account identifiers, raw JSON-RPC bytes, stderr, prompts,
  responses, and every rejected or ignored field are never persisted or logged. A profile name is
  never stored as a separate field or logged; any profile-bearing path required for launch stays
  only in the owner-only configuration. Aliases, launch paths, and normalized usage values never
  enter diagnostics or calibration evidence.
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

## Owner decisions

The owner resolved the implementation choices on 2026-10-24. These are binding:

1. **Accounts and identity.** Support two concurrent Codex accounts and one Claude Code account.
   Global `Account #N` numbering uses the smallest unused positive number and stays with the row
   until confirmed removal. A replacement or provider sign-in change retains the local row ID,
   number, and alias but clears windows from the prior provider scope. Two profiles resolving to
   the same provider account are not duplicated: the lower-numbered row remains active and the
   other becomes incompatible.
2. **Aliases and presentation.** Only Mac edits aliases for now. An alias is optional, at most 32
   UTF-8 bytes, follows the Domain safe Unicode profile, contains at least one visible
   letter/number/punctuation/symbol, and rejects exact effective-label duplicates. Accepted input
   preserves case and leading/trailing ASCII spaces without Unicode normalization; empty input
   restores the default. Aliases travel only in the encrypted snapshot, publish immediately after
   a change, sort with localized natural comparison, and appear in notifications and supported
   compact surfaces with middle truncation. Watch Home keeps aliases hidden and derives a distinct
   stable pastel Account Palette from each global account number: #1 lavender, #2 mint, and #3
   peach, each with contrast-safe appearance variants. The binding Account List and palette
   behavior is in the UX documents.
3. **Configuration contract.** Add opaque option identity, exact owner-visible launch previews,
   preview revisions, selected add/replace intent, confirmed removal, and an `incompatible` state.
   Apply revalidates the exact executable, applicable Node interpreter, and complete allowlisted
   environment: four required values plus optional `CODEX_HOME`. `codex-profile` may assist
   owner-present discovery but is never a runtime dependency.
4. **Provider identity and state.** A missing provider account identifier is incompatible; paths
   never substitute for it. Add `ordinaryUsageDisallowed`, preserve the approved reached/allowed/
   disallowed/unknown precedence, and never infer provider state from usage. Use structured
   `account/read` with `refreshToken: false`; never classify sign-in from provider prose. The
   [account-status matrix](../architecture/provider-adapters.md#account-status) is exhaustive.
5. **Isolation and retry.** Run one child and independent schedule/backoff per Codex account.
   Concurrent startup is allowed. A corrupt configuration or transient failure affects only that
   row. Use the [source-state and retry matrix](../architecture/provider-adapters.md#source-states-and-retry)
   and retry only transient running-source failures at one, two, five, then fifteen minutes;
   manual, wake, and foreground requests respect active backoff.
6. **Tests and account-aware contracts.** Add the existing Domain and Application targets to the
   ProviderAdapters test target. Replace product-only sources, fixed Home slots, and manual refresh
   results with account-aware equivalents. Home Refresh targets all Codex accounts; Account Details
   targets one account; partial successes are committed and reported separately.
7. **Wire versions and scope.** Use inner `UsageSnapshot` schema 2 while preserving the approved
   envelope, encryption, pairing, and snapshot relay v1 contracts. Add strict
   `/v2/refresh-requests` with opaque account or `allCodex` targets and one reader-global request
   per minute. Migrate relay SQL in place, preserving durable relay state while discarding legacy
   pending refresh rows. M10 performs offline tests only: no deployment, real publication, or M9
   work.
8. **Calibration close-out.** Calibrate two signed-in profiles for one initial and six scheduled
   reads over 30 minutes, with one ordinary owner-controlled Codex turn per profile. If both runs
   satisfy every defined criterion, record 15 minutes as confirmed rather than retaining candidate
   wording.

## Completion checklist

- [x] A synthetic regression fixture modeled on the sanitized live owner-selected Codex response
  passes the inbound frame decoder, account-status decoder, rate-limit decoder, and normalizer;
  ignored additive fields cannot cause an `incompatible` result. Evidence: the bounded live
  one-read probe stayed within every frame and structure limit, the focused observed-shape test
  passed, and the complete contribution-guide gate passed with zero SwiftLint violations.
- [x] Live Codex app-server replies without a `jsonrpc` member are accepted after bounded
  structural validation, while an explicit wrong version and malformed envelopes still fail
  closed. A regression test covers the installed response shape and the Mac setup preview makes
  the selected `CODEX_HOME` visible before apply. Evidence: a sanitized live probe of the
  installed Codex 0.164.0 response shapes, five protocol and six client tests, the complete
  contribution-guide gate, and a signed Release build with a matching helper and installed-app
  team identity. After installation, the previously incompatible saved Codex source reported
  `reporting` in the Release snapshot.
- [ ] Entry criteria hold with recorded owner decisions, baseline evidence, and no unrelated
  work attributed to M10.
- [ ] Owner-confirmed discovery selects at most two approved executable/profile environments,
  persists only required launch material with symlink-safe owner-only permissions, rejects stale
  or altered previews, unsafe `PATH` entries, executable/interpreter substitution, and a third
  Codex account, and never falls back to an ambient profile. One corrupt account configuration
  does not prevent the other account from running.
- [ ] The account catalog assigns unique random IDs and smallest-unused global account numbers,
  enforces the approved alias rules and product caps, preserves identity across replacement,
  confirms removal before deleting metadata, and publishes alias changes immediately without
  advancing an observation. A removed number is reusable.
- [ ] `UsageSnapshot` schema 2, sources, windows, Home/Details read models, notification and
  activity selections, Watch payloads, widgets, and diagnostics are account-aware. Invalid or
  dangling account references fail closed, and the binding UX documents consistently specify the
  Account List rather than the superseded four-cell grid.
- [ ] App-server initialization, request matching, sparse-notification dispatch, timeout,
  cancellation, stdout EOF, bounded stderr draining, clean stdin-close shutdown, and
  executable-version/modification restart pass deterministic tests. A session generation fences
  every late response, exit callback, and notification from a replaced or stopped child.
- [ ] The frame reader rejects an unterminated or delivered frame over 1 MiB before JSON decode;
  malformed UTF-8/JSON, duplicate object keys, decoded keys or strings over 4 KiB of UTF-8,
  nesting over 32, more than 128 bucket entries, and more than 128 candidate windows terminate
  that child without leaking input or erasing the last valid observation. LF and CRLF delimiters
  have the same payload bounds, and JSON-RPC request IDs stop at `2^53 - 1` without reuse.
- [ ] Single-bucket, multi-bucket, and compatibility-only fixtures normalize without duplicate
  windows. Exactly the uniquely reconciled compatibility bucket is default; two same-duration
  limits do not collide; map keys and embedded IDs cannot disagree or repeat; unknown limit IDs
  survive; missing identity never gains a fabricated ID or scope; and a response with no valid
  allowance window fails state-only rather than reporting a false successful refresh.
- [ ] Percentages remain provider-reported integer percentage used with `fractionDigits == 0`;
  reset instants remain absolute; missing duration/reset stays nil; invalid windows are rejected
  individually with redacted diagnostics; explicit provider state is never inferred from usage.
- [ ] A valid provider account identifier crosses only the injected `AccountScoper` call and the
  output contains only its opaque scope. Account change replaces prior scoped windows only in its
  local row. Missing identity follows the fail-closed rule, and two profiles resolving to the
  same scope deterministically keep only the lower-numbered row active.
- [ ] Concurrent `start`, five-minute polls, sparse updates, reset-plus-30-second reads, immediate
  refreshes, `stop`, and one/two/five/fifteen-minute restart backoff are proven with injected time
  for two accounts. Reads never overlap within an account, sibling accounts do not share backoff,
  notifications refetch no more than once per 60 seconds per account, and reset timers are
  replaced when a newer complete report changes that account's deadline set. A notification newer
  than an in-flight request leaves one trailing refetch.
- [ ] Every failure class maps to the approved source state and a state-only `SourceSnapshot`;
  retry and non-retry behavior follows the approved table. `start()` keeps operational failures
  observable instead of tearing down the runtime, one physical read produces at most one stream
  event, and every coalesced caller receives the same `ReadReceipt`. Receipt times bound the
  actual read and report success only for a complete normalized response. A backoff-deferred
  receipt has no fabricated attempt times or report and cannot satisfy `codexRead`. M5 ingestion
  and manual-refresh tests pass with the real adapter seam.
- [ ] Strict `/v2/refresh-requests`, per-account results, one-reader-per-minute limiting, replay
  behavior, and the in-place SQL migration pass Swift and TypeScript tests. M10 performs no relay
  deployment, Cloudflare call, real publication, or M9 work.
- [ ] Privacy tests prove that configuration contains only approved account and launch fields and
  that diagnostics, thrown errors, and the app/test process's own output contain no fixture
  sentinel representing a provider account ID, alias, profile/path, prompt, response, limit ID,
  percentage, reset, child stderr, or raw frame. Random Reset Radar `AccountID`s appear only in
  approved typed records; aliases appear only in the owner-only catalog or inside encrypted
  snapshots.
- [x] Owner-present calibration passes for both selected profiles: installed schema, initial plus
  six scheduled reads, ten-second latency, legitimate-response measurements below all approved
  input bounds, unambiguous default bucket, account-identifier presence/type, approved sign-in
  discriminator shape, process exit within five seconds, profile isolation, and the 15-minute
  decision. Synthetic tests, not live input, prove rejection at each exact bound. A notification/
  refetch may be explicitly deferred, but is not reported as passed. Evidence: the 2026-10-25 [Codex calibration entry](../research/phase-1/spike-results.md#codex-source-calibration--2026-10-25) records both profiles passing every technical check (seven reads each, latency under 1 s, all bounds respected, unique default bucket, present string account identifier, clean shutdown) with 15 minutes confirmed by the owner; the update notification is deferred to M12 and not reported as passed, and the owner relaxed the `requiresOpenaiAuth` criterion.
- [x] The calibration cleanup succeeds before one redacted Codex evidence entry is added to
  [spike-results.md](../research/phase-1/spike-results.md). No raw or identifying value enters
  version control. Evidence: cleanup printed `codex calibration disposable files removed and repository unchanged: PASS` before the single entry was added; it contains no raw or identifying value.
- [x] Live calibration shows that each selected Codex profile reports only distinct five-hour or
  weekly default-bucket windows, at least one per profile. The harness records only a coarse
  duration class per decoded window (`300`, `10080`, or `other`, never an exact other value), the
  verifier checks it, and the owner re-ran a short owner-present check (one initial read, no
  30-minute soak) without any percentage, reset, limit ID, or bucket key in the report. The
  owner relaxed the original "one of each" rule because a profile may report weekly only.
  Evidence: the 2026-10-25 duration-class entry in
  [spike-results.md](../research/phase-1/spike-results.md#codex-source-calibration--2026-10-25):
  profile 1 reported both windows and profile 2 only the weekly window.
- [ ] The ProviderAdapters placeholder and smoke test are removed, affected active docs match
  the implementation, and P1-M10 moves to `Done` only after every required item has evidence.
- [x] The `test_runner` passes the complete contribution-guide gate from the final reviewable
  worktree; focused ProviderAdapters tests, `git diff --check`, and relative Markdown links also
  pass. Evidence: on 2026-10-25 the delegated gate passed project generation, format lint, strict SwiftLint, import checks, the macOS scheme, relay `npm ci`/tests/typecheck/dry run, and the 5 calibration synthetic tests; 190 focused ProviderAdapters tests passed. A docs-only changelog and checklist edit followed, then `git diff --check` and the relative-link check on changed Markdown passed.

## Checkpoints

- **A: Account, configuration, and process boundary** (Tasks 0 to 3): decisions, baseline,
  revised UX and account contracts, calibration workflow repair, configuration persistence,
  child host, and bounded framing.
- **B: Schema, source, and refresh behavior** (Tasks 4 and 5): decoder, normalizer, account scope,
  two source actors, schedules, error mapping, Application integration, and offline refresh-v2
  implementation.
- **C: Owner calibration and close-out** (Task 6): owner-run signed-in evidence, cleanup, final
  gate, documentation, and M12 handoff.

## Calibration outcome

The owner-present calibration ran on 2026-10-25 for both profiles (see
[spike-results.md](../research/phase-1/spike-results.md#codex-source-calibration--2026-10-25)).
The signed-in installed Codex reports `requiresOpenaiAuth: true` for an authenticated ChatGPT
account, contradicting the plan's `== false` rule. The owner relaxed the criterion: a supported
ChatGPT account object with a boolean `requiresOpenaiAuth` of either value is authenticated; a null
account with `true` stays `signedOut`; every other combination stays `incompatible`. The decoder,
synthetic fixtures, verifier, runbook, and ProviderAdapters matrix now agree. Neither profile
observed an update notification, so that path is deferred to M12.

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

The review originally found no reason to make M9 a dependency or broaden M10 into multi-account
behavior. The later owner interview supersedes only that product-scope conclusion: M10 now owns
the two-account Codex contracts, revised UX specifications, and offline refresh-v2 changes, while
still excluding Claude acquisition, platform SwiftUI screens, deployment, and real publication.
The first two plan-validation results below predate that revision and remain baseline evidence;
the final result validates the owner-revised plan and binding documentation.

A follow-up review on 2026-10-24 found and corrected additional execution gaps:

- The original privacy sentence forbade persisting the executable, home, percentages, resets,
  and limit IDs even though the plan requires an owner-only launch file and normalized snapshots.
  The invariant now names those narrow exceptions and still excludes every raw, provider-identity,
  separate profile-name, rejected-field, diagnostic, and calibration-evidence path.
- The launch configuration pinned only `PATH` and `CODEX_HOME` while the child also inherited
  `HOME`, `USER`, and `LANG`. Preview, storage, validation, and launch now bind the same complete
  allowlisted environment, a safe absolute-only `PATH`, a fixed working directory, and the
  executable identity. npm-script discovery also binds the actual `node` selected by that `PATH`.
- The plan promised `signedOut` without a stable discriminator. Official app-server source uses a
  generic invalid-request error for an unauthenticated rate-limit read, while `account/read`
  exposes structured account presence and `requiresOpenaiAuth`. The revised owner decisions make the narrow
  read-only status method explicit and forbids matching provider error prose.
- Product-visible source state, retry eligibility, and provider diagnostics were under-specified;
  account-scoper failure was omitted entirely. The revised plan now requires exhaustive
  account-status and source-state/retry matrices and keeps diagnostics enum-backed and string-free.
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
- Earlier Markdown validation considered only then-tracked files, so the follow-up explicitly
  inspected both M10 plan paths; the earlier result was not reused as link evidence for their
  enhanced contents.

A cross-document UX and execution review later on 2026-10-24 corrected these remaining gaps:

- The phase table still let M10 precede M7/M8 even though refresh v2 revises their implemented
  contracts, and it let M11 production code race the shared account-contract rewrite. M10 now
  depends on M7/M8, while M11 integration waits for Checkpoint A.
- Setup wording incorrectly emptied the Mac list when only relay or pairing setup was incomplete,
  Home Refresh had no defined containment, and notification controls covered only standard
  windows despite the account-window scheduling contract. The UX documents now preserve configured
  rows, separate Home and Account Details refresh scopes, and cover every eligible account window.
- Two alias rules produced blank or unsafe visible identity. Custom aliases now require a visible
  scalar, use the dependency-free safe Unicode profile in Domain, and retain exact accepted text.
  The owner also chose stable pastel Account Palettes to distinguish alias-free Watch Home rows.
- The plan referred to approved sign-in and retry tables that did not exist. ProviderAdapters now
  contains exhaustive account-status and source-state/retry matrices, including non-retrying
  incompatible input and the duplicate-account rule.
- A manual refresh during source backoff lacked an honest receipt shape and could falsely satisfy
  `codexRead`. The revised contract returns an immediate deferred receipt with no fabricated read
  times or report.
- CRLF framing, JSON-RPC request-ID exhaustion, launch-path privacy exceptions, and out-of-range
  percentage rejection were inconsistent or implicit across active documents. They are now
  explicit and aligned.

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
decisions are recorded and implementation begins.

After the owner resolved the account, UX, alias, and refresh-v2 decisions, the `test_runner`
validated the final reviewed documentation worktree on 2026-10-24. Project generation, Swift format
lint, strict SwiftLint with zero violations, import checks, the Mac scheme, 26 relay Vitest tests,
31 relay Node tests, relay typechecking, and the non-deploying Wrangler dry run passed. A relative
Markdown-link scan across active `docs/` and `git diff --check` also passed. Initial Xcode/Swift
cache access required the same approved host-access retry. No signed-in provider process,
Cloudflare call, deployment, secret, account value, or real usage was accessed. This validates the
owner-revised plan and documentation; implementation and owner-present calibration remain open.

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
