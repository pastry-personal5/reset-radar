# Phase 1 changelog

Status: Active

Decisions and plan changes for Phase 1 that are not clear from commits.

## Entries

- 2026-10-26 — Claude Code — Finished the agent-side P1-M14 checks against the overview
  checklist. New reader tests cover a camera that cannot scan, per-account Refresh refusals, a
  mismatched result followed by a delayed match, a sleeping Mac, and Account Row reading order.
  Simulator screenshots showed three layout defects, now fixed. The iPad sidebar overlapped the
  two rings, and the iOS Account Details bitmap had flattened edges; the app now uses the intact
  M13 Mac asset. The in-ring percentage also did not grow at accessibility sizes. An unsigned
  Release build confirmed the app embeds its widget and the Watch app with its complication. M14
  stays `Active`. Its entry criterion is still unmet and the two owner questions are still open.
  The physical-device checks, the deployed manual-refresh evidence, and the seven-day re-sign
  remain owner-run, so M14 can close no earlier than seven days after the owner's first
  Sideloadly install.

- 2026-10-26 — Claude Code — Measured slow iOS runs: compilation was not the cause (incremental
  iOS builds take about 4 s; an empty-DerivedData build about 107 s, with the shared packages
  compiled for both iOS and watchOS because the iOS app embeds the Watch app). About 12 UI tests
  took about 137 s of the 151 s iPhone run and 175 s of the 210 s iPad run, and the gate ran the
  destinations one after another. XCTest's waits check about once a second, and on iPad every
  Main Toolbar lookup used its full 2-second timeout. The UI tests now poll every 0.1 s with the
  same timeouts and assertions; in alternating same-machine runs, iPhone UI tests fell from about
  137 s to 87 s and iPad from 165 s to 102 s. The gate and `make test` now test both iOS
  destinations concurrently in one `xcodebuild` invocation (`make test-ios-ipad`); `make test-ios`
  and `make test-ipad` remain for one destination. At the owner's request, UI tests sharing a
  scenario and launch arguments were merged into three tests: the toolbar and the unpaired Home;
  the paired rows, Account Details, and Home Refresh; and the Settings routes and Forget Mac. All
  assertions are kept and the gate passed in 118.5 s. The owner also approved deleting six
  DerivedData folders left by removed `/tmp` checkouts.

- 2026-10-26 — Claude Code — The owner directed completion of P1-M14 while P1-M9 remains
  `Active` (its release promotion/rollback and verdict items are open) and P1-M10 is `Active`. The
  M14 entry criterion is therefore recorded as unmet rather than waived. The agent-side reader is
  implemented and M14 is `Active`. The baseline iPhone run failed: unsigned Development builds
  have no App Group on the simulator, so the app crashed at launch, and three Mac-only Keychain
  tests failed on iOS. The iOS composition now injects every port and falls back to isolated
  Development storage only in unsigned Development builds; Release fails closed. Keychain tests
  are split by platform, and the iOS initializer again requires its explicit access group.
  Implementation review fixed defects in the earlier draft: launch called `retryCleanup()`
  unconditionally, which forgets an intact pairing; rings treated the 0–100 percentage as a
  fraction; stale readings hid their value; Home Refresh posted `allCodex` without Codex
  accounts; leaving the foreground cancelled relay reads into a false offline status; and the
  300 px toolbar and Account Details bitmaps had opaque fills that rendered as solid shapes. The
  bitmaps are now 25 pt and 24 pt template sets with the same outlines.
  `RequestMacRefresh` gained an optional progress callback, so relay contact and an accepted
  request show separately from Mac completion. `LoadUsageDetails` now reports Last Synced. Shared
  reader presentation lives in `ResetRadarUI`, while the app's `ReaderEnvironment` holds iOS
  screen state as the scene and refresh driver. That is narrower than the UI architecture's
  observable screen models. It and the unsigned Development storage fallback are open owner
  questions in the M14 overview; neither binding document was changed to adopt them. `make test` now runs the
  Apple suites in sequence because they share one build database. Physical installation, the
  seven-day re-sign, and deployed manual-refresh evidence remain owner-run.

- 2026-10-26 — Codex — Reviewed the P1-M14 plan against the implemented reader queries and the
  approved iPhone/iPad UX. Corrected the Application, iOS, and UI architecture query names;
  clarified pending activation, first publication, preserved cache, refresh feedback, account
  selection, pairing privacy, and large-text checks in the plan and UX docs. M14 remains planned
  behind its entry dependencies; the iOS target is still a scaffold.

- 2026-10-26 — Codex — Wrote the P1-M14 iOS core app overview and sequence. The plan keeps M9's
  synthetic gate as an entry dependency, restores both iOS simulator runs during M14, starts
  physical Sideloadly re-sign evidence with the first installable reader, and assigns widget and
  scheduling checks to M15 and Watch delivery checks to M16. M14 remains `Planned`; no iOS
  implementation or owner-run installation began.

- 2026-10-25 — Codex — Reviewed M12/M13 startup and menu behavior. A failed Release signing
  check now leaves provider sources stopped and shows a collection pause; successful relay
  activation rebuilds the collector and rechecks signing. The open menu reevaluates allowance
  freshness and reset transitions every 30 seconds. Focused regressions and the complete gate
  were rerun for this review.

- 2026-10-25 — Codex — Completed P1-M13 and the requested M12/M13 review. The Mac Main
  Sidebar now presents Home's persistent Account List and Account Details, standard and
  additional provider windows, setup guidance, account-scoped Refresh, inline alias editing,
  and a shared Global Messages pane. The menu shows per-account allowance status and session
  publication state while Settings is the only open window, then reopens Main on demand.
  Lifecycle review covered second-instance exit, one pairing activation poller, and manual
  request readiness after relay and reader changes. Development Settings now explains its
  isolated storage and secrets without suggesting that the development build needs Release
  signing. Live Main, Settings, and menu accessibility inspection passed; the final delegated
  `make gate` passed project generation, format, strict lint, imports, Mac tests, 28 relay tests,
  TypeScript typecheck, and Wrangler dry run.

- 2026-10-25 — Owner/Codex — Reset Radar Settings directly edits the default Claude Code user
  settings file after exact preview and confirmation. The owner's current `bash $HOME/<script>`
  status-line command exposed the previous single-path parser limit. The approved narrow form now
  validates the owner-owned script and Bash shebang, compares the original Bash invocation with
  direct helper execution on synthetic input, retains the original command for restore, and leaves
  broader shell commands untouched. The installed command's synthetic Bash and direct executions
  matched privately; the complete delegated gate passed 703 Mac tests, strict formatting and
  lint, import checks, 59 relay tests, TypeScript, and Wrangler dry run.

- 2026-10-25 — Codex — Fixed Claude Code Sources preview preparation. Production had created
  a helper installer but never invoked it, so a missing helper blocked preview; the generic UI
  error also hid an existing command that uses shell arguments and expansion. Normal Mac launch
  and safe preview now install or refresh the verified helper, while preview explains helper and
  existing-command failures separately. Unsafe owner settings remain untouched. The focused
  configurator restore suite and delegated complete contribution-guide gate passed.

- 2026-10-25 — Codex — Investigated unavailable Mac rings after source setup. The saved
  Development `CODEX_HOME` had trailing whitespace, pointed to a missing directory, and the
  Codex child exited before producing windows. Sources now rejects surrounding whitespace and
  missing directories before discovery and offers confirmed Change Home replacement of an
  existing account. The inactive-publication message now states that local readings remain on
  the Mac and directs relay setup to Settings. Focused Mac tests, the complete delegated gate,
  and diff hygiene passed.

- 2026-10-25 — Codex — Fixed Mac Codex Add discovery for an owner-installed executable outside
  the standard Homebrew paths. The Mac now supplies the current user's login shell to the
  existing bounded `command -v codex` lookup while preserving the selected `CODEX_HOME`,
  allowlisted launch environment, validator, and exact confirmation preview. Focused Mac tests,
  the complete delegated contribution-guide gate, and diff hygiene passed.

- 2026-10-25 — Codex — Added a Mac-only troubleshooting log with separate Development and
  Release `~/Library/Logs` locations, typed startup/runtime/publication/diagnostic records,
  owner-only permissions, daily and size rotation, and an eight-UTC-day limit. Diagnostics
  Settings exposes the active folder so local coding agents can investigate failures. Log
  fields omit provider identities, usage, paths, secrets, and raw error text. Four focused log
  tests and the delegated full gate passed, including strict lint, Mac tests, 59 relay tests,
  TypeScript, and the Wrangler dry run.

- 2026-10-25 — Codex — The Mac Global Messages Pane now reports typed publication stop and
  pause reasons, including relay conflict, authorization failure, rejected payload, incompatible
  protocol, oversized envelope, unavailable secrets, and inactive publisher state. The Mac driver
  reports only a changed blocking outcome and a later recovery for ordinary or reader-requested
  publication; startup and relay activation also use fixed reason-specific copy rather than
  exposing raw errors or relay responses. The delegated complete gate passed project generation,
  format, strict lint, imports, Mac tests, relay tests, TypeScript, and the Wrangler dry run.

- 2026-10-25 — Codex — Added the P1-M13 Global Messages Pane to the Mac main and Settings
  detail columns. One bounded, session-local history follows collector lifecycle and curated
  owner-flow messages across both windows and collector rebuilds; inline duplicate status text
  moved into the pane. No provider responses or secret values are copied into it. The delegated
  complete gate passed project generation, format, strict lint, imports, Mac tests, relay tests,
  TypeScript, and the Wrangler dry run.

- 2026-10-25 — Codex — Started P1-M13 Mac UI with the Sources settings layout. The Codex card
  presents configured aliases and selected Home Folders in a table with a bitmap Add control and
  an editable draft row. The Claude Code card groups its guided connection and restore actions.
  Discovery, exact-change preview, confirmation, source limits, and local-only configuration are
  retained; the Mac installation guide reflects the new flow. The delegated complete gate passed
  project generation, format, strict lint, imports, Mac tests, relay tests, TypeScript, and the
  Wrangler dry run.

- 2026-10-25 — Codex — Post-implementation review hardened the M12 owner flows: pairing now
  stops activation polling and conditionally clears any copied pairing package when its screen
  hides, while an independent deadline remains armed for expiry revocation. Sources Settings now
  supports the required alias editing path and publishes the metadata-only update immediately.
  The phase plan correctly remains `Active` while P1-M13 through P1-M16 are still planned. The
  focused Mac suite passed 23 tests after the changes. The delegated complete gate then passed:
  project generation, formatting, strict lint, import checks, Mac tests, relay tests, TypeScript,
  and the deployment dry run.

- 2026-10-25 — Codex — Completed P1-M12. The Mac collector now composes live sources by default,
  supports explicit synthetic integration, protects the signed Keychain path, drives publication
  and manual refresh, and exposes every required functional owner flow. Confirmed source changes
  rebuild the collector immediately. The accepted runtime-validation waiver remains explicitly
  recorded; the final delegated `make gate` passed project generation, formatting, strict lint,
  imports, all 21 Mac tests, relay install and 59 relay tests, TypeScript checking, and the
  no-deployment Wrangler dry run.

- 2026-10-25 — Owner/Codex — Resolved the M12 source-lifecycle question: a confirmed source add,
  removal, or Claude Code restore rebuilds the collector immediately from its persisted catalog.
  The rebuild stops the prior source runtime before composition restarts, so removed sources cannot
  continue publishing and newly configured sources do not wait for an app relaunch.

- 2026-10-25 — Codex — Reconciled P1-M12’s active plan with the owner’s later relay decision
  and the implemented composition root. M9 remains an independent synthetic relay gate and no
  longer blocks live publication: normal launches use configured sources and `--synthetic` is the
  explicit fixture route. The plan now defers Mac notifications and menu-bar status presentation
  to P1-M15 and P1-M13 respectively, records the accepted owner-run validation-risk waiver, and
  makes the functional Sources screen expose two Codex discovery inputs plus confirmed removal of
  configured sources.

- 2026-10-25 — Codex — Completed P1-M12 Checkpoint B. Normal launches now compose live sources
  from the account catalog; `--synthetic` selects a fixture source without an M9 gate. The single
  process environment owns source ingestion, one-timer publication, manual-request polling,
  App Nap, wake/session/foreground and network-restored event translation, session-secret retry,
  and clean shutdown. The synthetic integration starts local Wrangler/Miniflare, retains a
  canonical test `workers.dev` origin, registers and activates a reader, publishes a real AES-GCM
  envelope through `HTTPRelayGateway`, and authenticates and decrypts read-back. The delegated
  complete gate passed with 0 SwiftLint violations, all Mac tests, 28 relay Vitest tests, 31 relay
  Node tests, TypeScript checks, and Wrangler dry-run.
- 2026-10-25 — Codex — Completed P1-M12 Checkpoint A. The exact Release and `.dev`
  Application Support and Keychain namespaces, injected signing outcomes, non-interactive
  session cache, one-minute/session-active recovery seam, and matching app/helper Release signing
  enforcement are implemented. The complete delegated gate passed. A signed Release build passed
  the post-action on 2026-10-25; the signing team identifier's SHA-256 fingerprint is
  `45e2f26cab945f930afb4916a8ca8d0ebead7a36e9b6bc6ed040c805e431c5ab`. No raw team identifier is
  tracked.
- 2026-10-25 — Owner/Codex — Started P1-M12 from clean baseline
  `abaf26e9973432976745251913dcc07da7d94c46`. Locked M12 to live-by-default publishing with
  `--synthetic`/injection for fixtures (no M9 gate), `.dev` Development namespaces, temporary
  test storage and in-memory secrets, sidebar Settings, local Miniflare integration, explicitly
  selected `CODEX_HOME` folders, hashed-only signing evidence, and automated close-out with the
  owner-run reboot, eight-day Keychain, and 24-hour drift gates waived as accepted risk. Baseline
  sandbox limitations include Xcode caches, CoreSimulator, Wrangler logs, and localhost binding;
  affected commands require escalation rather than changing the validation contract.
- 2026-10-25 — Owner/Codex — Completed P1-M11 Task 7 from clean revision `f6c3300` after the
  timer-trigger repair passed its offline and complete gates. Two isolated Claude Code 2.1.310
  sessions supplied exactly four owner-entered ordinary turns; response-linked activity, both
  sessions' idle non-advancement, A-after-B isolation, public five-hour and seven-day shapes, and
  A's unchanged observation at least 60 minutes after its last increase all passed. The redacted
  verifier reported privacy-shape, cross-session, and 60-minute technical PASS, and the owner
  confirmed the 60-minute current-data window. Exact cleanup then passed the real-settings,
  history-prefix, generated-session UUID, repository, and disposable-directory checks before
  sanitized evidence was recorded. Active architecture and research now treat both current-data
  windows as confirmed. Final close-out passed 199 focused ProviderAdapters tests, 78 focused
  Domain tests, six calibration tests, the complete gate with zero SwiftLint violations across
  286 files, 28 Workers tests, 31 relay Node tests, TypeScript checks, Wrangler dry-run, a zero-hit
  scaffold search, diff hygiene, and 730 fenced-code-aware relative links. P1-M11 is `Done` and
  hands the implemented source to M12.
- 2026-10-25 — Owner/Codex — Ran the first P1-M11 Task 7 owner calibration from clean revision
  `a8b4c0d`. Two A turns and one B turn produced the required response-linked activity
  classifications, but neither Wave Terminal resize produced an idle status-line event. The owner
  stopped before B's second turn and the 65-minute check, made no 60-minute decision, ran the
  expected failing verifier, and completed exact cleanup with settings, history, UUID scan,
  repository, and disposable-directory checks passing. Current official Claude Code documentation
  does not list terminal resize as an update trigger; it does list optional `refreshInterval` for
  idle updates. The attempt is recorded as deferred rather than as a source-rule failure. The
  isolated temporary settings, offline test, sequence, runbook, and research now use a bounded
  30-second refresh timer before a fresh owner run. The delegated six-test calibration suite and
  complete gate passed project generation, Swift format, strict SwiftLint with zero violations
  across 286 files, import checks, the macOS suite, 28 Workers tests, 31 relay Node tests,
  TypeScript checks, and Wrangler dry-run; diff hygiene and 729 fenced-code-aware relative links
  passed. M11 remains `Active`.
- 2026-10-25 — Codex — Expanded P1-M11 Task 7 into one explicit owner route from clean-revision
  approval through the three-terminal Claude Code observation, 65-minute idle check, redacted
  verification, owner decision, exact cleanup, sanitized evidence handoff, and agent close-out.
  The runbook now distinguishes the one optional early idle deferral from the response, B-idle,
  cross-session, and 60-minute evidence required to pass. The delegated offline calibration suite
  passed six synthetic tests plus preparation isolation; the complete gate passed project
  generation, Swift format, strict SwiftLint with zero violations across 286 files, import checks,
  the macOS suite, 28 Workers tests, 31 relay Node tests, TypeScript checks, and Wrangler dry-run.
  Diff hygiene and 727 fenced-code-aware relative Markdown links passed. No signed-in provider
  process, real usage, or external deployment was accessed.
- 2026-10-25 — Owner/Codex — Resolved the surfaced P1-M11 Claude Code version-discovery
  inconsistency as a documentation correction. Guided setup does not invoke `claude --version` or
  otherwise probe the installed Claude Code version because no setup contract consumes it. Each
  decoded status-line observation supplies its actual public version, and recording and merging
  preserve that observation provenance. Owner-run public version collection remains milestone
  evidence only. Updated the binding ProviderAdapters architecture, M11 sequence, overview
  decision 12, and completion evidence; no production behavior changed. The complete gate passed
  project generation, Swift format, strict SwiftLint with zero violations across 286 files, import
  checks, macOS tests, 28 Workers tests, 31 relay Node tests, TypeScript checks, and Wrangler
  dry-run. Diff hygiene and relative links in all four changed documents passed.
- 2026-10-25 — Codex — Reviewed and hardened the P1-M11 implementation. Setup now keeps its
  restore transaction pending until the Claude Code account row is durable, configuration
  inspection requires that row, same-preview recovery completes interrupted installs only after
  validating compose artifacts, and post-write settings conflicts preserve recovery evidence and
  block a new preview until the owner resolves them. Added the planned Claude Code catalog load and
  state operations, and bound executable hashing to stable descriptor and path metadata. Focused
  Claude Code tests and the complete ProviderAdapters target passed; the complete gate passed
  project generation, Swift format, strict SwiftLint (zero violations across 286 files), import
  boundaries, macOS tests, 28 Workers tests, 31 relay Node tests, TypeScript checks, and Wrangler
  dry-run. Diff hygiene and the fenced-code-aware relative Markdown link check passed. Owner-run
  Claude Code calibration and cleanup remain open, so M11 stays `Active`.
- 2026-10-25 — Owner/Claude — Completed the Codex duration-class re-check. Profile 1 reports five-hour and weekly windows; profile 2 reports weekly only. The owner relaxed the criterion from "exactly one five-hour and one weekly window" to "at least one distinct standard window, none unclassified", since an account may have no five-hour window (cause unverified: no five-hour limit on that account, or its weekly limit reached). Reset Radar never invents a five-hour value; that ring is unavailable.
- 2026-10-25 — Owner/Claude — Added an open P1-M10 item: calibrate that each Codex profile reports a five-hour and a weekly default-bucket window by recording only a coarse duration class (`300`, `10080`, `other`) per decoded window. The 2026-10-25 calibration recorded window counts but not durations, so the mapping is currently synthetic-only evidence.
- 2026-10-25 — Owner/Claude — Completed the P1-M10 owner-present Codex calibration for two profiles: all technical checks passed, the owner confirmed the 15-minute Codex current-data window, and the update-notification path is deferred to M12 operational observation. The installed Codex reports `requiresOpenaiAuth: true` for a signed-in ChatGPT account, contradicting the planned `== false` rule, so the owner relaxed it: a ChatGPT account object with any boolean `requiresOpenaiAuth` is authenticated, a null account with `true` is `signedOut`, anything else is `incompatible`. This also fixed a production decoder defect that would have marked healthy accounts incompatible. M10 stays `Active` until the remaining checklist items have recorded evidence.
- 2026-10-25 — Owner/Claude — Removed the synthetic-data gate as a requirement: real usage and provider adapters may use the relay without waiting for P1-M9 to close. The M9 overview, sequence, runbook, harness, and evidence stay as history and optional validation. Updated AGENTS.md, owner decisions, product behavior, the phase plan, and the M2 out-of-scope list.
- 2026-10-25 — Owner/Claude — Planned P1-M12 ([overview](milestone-12-mac-collector-overview.md), [sequence](milestone-12-mac-collector-sequence.md)). Decided: M12 delivers all of [Mac app](../architecture/mac-app.md) except `NotificationDriver`, with functional unstyled screens, and P1-M13 becomes GUI polish only; M12 is synthetic-only behind a `PublishingMode` guard until M9 passes; code-complete M10 and M11 on `main` start M12 and their open calibration gates only the final real-data step; reset notifications on the Mac move to P1-M15; the Personal Team identity exists, so the first signed Release build starts the eight-day Keychain clock; tracer-first sequencing. Four implementation decisions remain open in the overview.
- 2026-10-25 — Claude — Implemented P1-M11 Checkpoints A and B on branch
  `m11-claude-code-adapter`: the Claude Code-only calibration mode, the bounded status-line
  decoder, per-session records, helper composition root and installer, settings transaction with
  status-line-only restore, and the directory-watching source with merge, pruning, and the failure
  table. Rulings recorded for owner review: an expired reset is accepted and left to the Domain; a
  value-only redraw updates the stored percentage but keeps the observation time and version; a
  clock regression fails the invocation (nonzero, per decision 10) while a decreased counter resets the session baseline without advancing observation time; the first
  counter appearance after a reading is a baseline; `refresh()` during a revalidation backoff
  returns a deferred receipt; the synthetic composition check runs the helper in-process against
  an isolated temporary root; the installed Claude Code version is not probed because no contract
  field consumes it. Owner-present calibration (Checkpoint C) is outstanding; M11 stays `Active`.

- 2026-10-25 — Owner/Claude — Answered P1-M11 decisions 9 and 10, completing the interview.
  The source-state table and retry model follow the recommendation (setup failures wait for a
  configuration change; watcher recovery uses the one/two/five/fifteen-minute ladder). The owner
  chose a nonzero, output-free helper exit on any recording failure, including when no existing
  command is composed, instead of the recommended quiet success. All M11 implementation decisions
  are now answered; the implementation branch, baseline, and Task 1 remain.

- 2026-10-25 — Owner/Claude — Answered P1-M11 decisions 2, 4, 5, and 7. Bounds, never-observed
  pruning (eight days after last invocation), and freshest-per-kind mixed-version merging follow
  the recommendations. The owner chose a stricter executable trust test than recommended: only a
  user-owned executable inside the home directory is composed, and system-installed or root-owned
  executables are refused; ProviderAdapters architecture updated. Decisions 9 and 10 stay open.

- 2026-10-25 — Owner/Claude — Answered P1-M11 decisions 1, 3, 8, and 11 as recommended: a
  status-line display-only preview plus typed restore conflict; CryptoKit for the 128-bit session
  key; automatic setup for the default `~/.claude/settings.json` only; and a Claude Code account row
  that survives restore, with removal refused while installed. Decisions 2, 4, 5, 7, 9, and 10 stay
  open.

- 2026-10-25 — Claude — Reviewed the P1-M11 plan and the ProviderAdapters architecture against
  the code M10 landed. M11 now builds on the implemented account contracts: it plans the single
  Claude Code catalog row (`AccountID`, no provider scope) and catalog-store operations (new
  owner decision 11), replaces `ProductSource` with `AccountSource`, narrows decisions 1 and 6 to
  what M10 left open, reuses M10's structural JSON preflight, owner-only file primitives, backoff
  ladder, and receipt semantics, and adds a Claude Code-only calibration mode in place of the
  Codex-dependent `combined` mode. Architecture changes: ProviderAdapters documents its Darwin use
  and shared neutral primitives, the Claude Code account row, and that sign-out is Codex-only;
  repository layout no longer says "Planned". No owner decision was answered; M11 stays `Planned`.

- 2026-10-24 — Codex — Began P1-M10 implementation by making source calibration explicitly
  Codex-only or combined. The Codex-only preparation now requires an owner-approved exact clean
  revision, accepts no more than two privately selected profiles, creates no Claude Code state,
  and cleanup proves the revision and worktree stayed unchanged before removing only its exact
  disposable directory. The sanitized harness now checks structured `account/read`, classifies
  the rate-limit response's account-identifier presence/type without retaining its value, measures
  decoded keys and strings in UTF-8 bytes, and reports separate bucket-entry and candidate-window
  maxima. Offline calibration tests and installed public-schema generation passed without starting
  a signed-in process or reading usage. The recorded public tools are Swift 6.4, Xcode 27.1,
  Codex 0.164.0, and `codex-profile` 1.3.0. Implementation also started the shared account model
  with opaque `AccountID`, standard `AccountWindow`, safe exact aliases, bounded catalog
  invariants, and the approved Domain/Application dependencies for provider-adapter tests.

- 2026-10-24 — Owner/Codex — Started P1-M10 on `feat/p1-m10-codex-adapter` from
  `5b4725d` after fast-forwarding the then-current M9 commits to local `main`; the recorded clean
  baseline passed the complete delegated gate. The owner replaced the planned single Codex
  profile and fixed four-cell Allowance Grid with an account model: at most two concurrent Codex
  accounts and one Claude Code account, global smallest-unused `Account #N` numbering, Mac-only
  aliases, and a vertically scrolling Account List. Aliases are optional, exact, at most 32 UTF-8
  bytes, require a visible letter/number/punctuation/symbol, and accept only Unicode letters,
  marks, numbers, punctuation, symbols, and ASCII spaces. They reject invisible/control/format,
  private-use/unassigned, noncharacter, non-ASCII-space, whitespace-only, and exact duplicate
  labels; publish immediately in the encrypted snapshot; sort with localized natural comparison;
  and use middle truncation.
  Replacement or a provider sign-in change keeps the local row identity and alias; confirmed
  removal deletes them and releases the number. Two Codex profiles resolving to the same provider
  account keep only the lower-numbered row active. The owner approved one isolated child and
  independent backoff per Codex account, structured `account/read`, fail-closed missing identity,
  `ordinaryUsageDisallowed`, direct Domain/Application provider-test dependencies, and the typed
  failure table. Home Refresh targets all Codex accounts with per-account outcomes; Account
  Details refreshes one account. A source in restart backoff returns an immediate deferred receipt
  that cannot masquerade as a completed Codex read. The encrypted usage snapshot advances to
  schema 2 while the
  envelope remains v1; strict account-targeted refresh moves to `/v2/refresh-requests` with an
  in-place SQL migration and reader-global rate limit. M10 will validate those relay edits offline
  only: the owner directed it not to deploy, publish real usage, run M9, or change M9 tracking.
  iPhone uses compact rounded account rows with two rings and a circular bitmap detail button;
  iPad and Mac use split list/detail layouts; Watch uses an N-by-two ring matrix without visible
  Home aliases and assigns each account a stable, distinct pastel palette derived from its global
  account number (#1 lavender, #2 mint, and #3 peach, each with contrast-safe appearance
  variants); widgets select one account; notifications and supported compact surfaces identify
  the alias. Palette never encodes usage or source state. Actual SwiftUI screens remain in M13,
  M14, and M16. The expanded milestone depends on completed M7/M8. Because M10 now owns
  shared account and configuration contracts, M11 may prepare independently but its production
  work waits for M10 Checkpoint A. Close-out calibrates two profiles for 30 minutes with one
  ordinary update-producing turn each and confirms the 15-minute Codex freshness window only when
  all defined evidence passes.

- 2026-10-24 — Owner/Codex — The repaired P1-M9 run from clean commit `9720206` passed private preflight, bounded provisioning and deployment, the exact ten-operation smoke, one uninterrupted 1,422-request sample, dashboard reconciliation, all nine client fault cases, and all seven remote fault cases. The sample completed in 1,803,433 ms with 426,261 response bytes, overall p50/p95 latency of 251.79/834.78 ms, zero dashboard errors, disabled observability, no unexplained activity, and US$0 billing. The owner explicitly waived the physical cellular check before preparation or Scriptable installation and accepted the missing evidence; no cellular pass is claimed. The assistant then incorrectly omitted the mandatory second compatible release deployment. Because the initial code deployment reconciled the Durable Object `exports` lifecycle after secret provisioning, default rollback targeted an incompatible pre-lifecycle version and Cloudflare rejected it as designed. No post-rollback smoke or storage-coherence evidence exists, so the release criterion remains open. The owner completed authenticated empty-state proof, bounded Worker deletion, dashboard cleanup, recovery-retention acknowledgement, final US$0 billing, six-secret deletion, and pasteboard clearing.

- 2026-10-24 — Codex — Diagnosed the latest P1-M9 soak drift as a harness workload-ordering defect: each manual round issued all 30 bounded snapshot reads sequentially in one slot, contrary to the binding initial-plus-nine-five-second-read cadence, and combined 37 to 41 requests in a burst. The repair retains the 5.05-second drift rejection and exact 900-read and 1,422-request accounting, schedules three concurrent due reads across each of ten consecutive slots, and drains the final accepted round through its bounded 1,802.85-second target without starting new regular post-deadline work. A fresh deployed sample is still required.

- 2026-10-24 — Owner/Codex — A fresh P1-M9 run from clean commit `45b3b29` passed the complete local gate, private Free-plan and US$0 preflight, bulk secret provisioning, bounded deployment, required-metric and disabled-observability checks, and the exact ten-operation finite smoke. The uninterrupted `caffeinate` soak then failed closed because it fell more than one 5.05-second slot behind schedule; no partial duration, counts, bytes, latencies, or dashboard sample are accepted, and no later fault, cellular, or release exercise ran. The owner completed authenticated destruction with empty active state, bounded Worker deletion, dashboard cleanup, recovery-retention acknowledgement, final US$0 billing, six-secret deletion, and pasteboard clearing. The safe failure does not identify whether client, network, platform latency, or workload ordering caused the overrun, so the sample remains open and no timing threshold is changed without further evidence.

- 2026-10-24 — Owner/Codex — The public strong-ETag repair passed the owner-run finite smoke with its exact ten-operation summary, proving the deployed `no-transform` response path. The subsequent 30-minute sample stopped on a scheduled manual request that received HTTP `429`; no partial counts or timings are accepted. The owner completed authenticated destruction and bounded Worker deletion, confirmed cleanup and final Workers Free US$0 billing, deleted the six fresh synthetic secrets, and cleared the pasteboard. Review found that the soak's nominal 60.6-second rounds were not a per-reader guarantee because one reader's ten follow-up reads delayed the next reader by a variable amount. The repair gates each reader from its prior accepted response, posts all three requests before follow-up reads, distinguishes relay rate limiting from an unrecognized `429`, waits for all concurrent posts to settle on failure, rejects catch-up beyond one slot and invalid measurements, preflights schedule state and generated request IDs before mutation, and reports observed elapsed time before another uninterrupted sample.

- 2026-10-24 — Owner/Codex — The repaired P1-M9 deployment wrapper emitted only its fixed redacted summary, and private owner checks passed the Free plan, US$0 billing, exact resources and bindings, disabled observability, active deployment, and availability of request, CPU, Durable Object duration, row, and storage metrics. The finite smoke stopped at the first public snapshot read because its strong ETag was not preserved. The owner ran authenticated destruction and bounded Worker deletion, confirmed cleanup and final US$0 billing, deleted the six fresh synthetic secrets, and cleared the pasteboard. Cloudflare's documented delivery compression can weaken a strong ETag when it transforms an uncompressed JSON response; the relay now requires `no-store, no-transform`, and the smoke distinguishes header transformation from stored-body mutation before another clean retry.

- 2026-10-24 — Owner/Codex — A fresh P1-M9 owner-run preflight, authentication, six-secret generation, bulk provisioning, and immediate post-provision dashboard review passed, but the first deployment command emitted the raw Worker origin and version identifier. The owner stopped before metric acceptance or any smoke, soak, fault, cellular, or release exercise, completed authenticated destruction and Worker teardown, confirmed final Workers Free US$0 billing and dashboard cleanup, deleted the six temporary password-manager items, and cleared the pasteboard. The attempt satisfies no remote criterion. The deployment, default-prior-version rollback, and confirmed deletion paths now require bounded wrappers that suppress Wrangler output and emit fixed redacted summaries before a clean retry.

- 2026-10-24 — Codex — Final P1-M9 local revalidation exposed and fixed one flaky concurrency test before a deployment retry. Four reader registrations correctly raced for three slots, but the test always activated the first three tokens even though any three registrations could win; it now activates and exercises the actual winners while preserving the concurrent cap boundary. The fault client also now routes snapshot successes and typed rate, quota, and offline failures through an explicit ingest path and reports only redacted before/after cache sequences. Five consecutive relay-suite runs passed with 26 Worker and 18 Node tests each, followed by the complete gate. Current official Cloudflare Free limits and structured Error 1027 fields are recorded in spike results; no Cloudflare account, secret, deployment, or real usage was accessed.

- 2026-10-24 — Codex — Re-reviewed the P1-M9 implementation after the first remote smoke failure. The review found that Wrangler configuration did not declare its two existing secret bindings as required, fresh idempotent destruction unnecessarily created and immediately deleted the SQLite schema, response timeouts ended before streamed bodies completed, canonical JSON did not recurse into arrays, synthetic envelope and secret-set validation was weaker than the v1 contract, the remote harness trusted status-only responses and did not prove the final reader list was empty, and the daily workload omitted 1,440 acknowledgements from the architecture's additive maximum. The fix declares the exact required secrets so deployment fails before serving without them, leaves fresh state unmaterialized on destroy, performs explicit administration and write authority preflights, retains timeouts through bounded strict-UTF-8 bodies, rejects unreviewed routes and noncanonical envelope fields, validates exact canonical response shapes and final empty state, prevents caller headers from bypassing token validation, clears the pasteboard even when prompting fails, pins the exact dependency set, and corrects the daily total from 68,005 to 69,445 while retaining the executable 1,422-request sample.

- 2026-10-24 — Codex — Re-reviewed and strengthened the untracked P1-M11 plan on
  `plan/p1-m11-claude-code-adapter`. The follow-up replaces the impossible bounded-read/complete-
  forward combination with one streaming input pump; makes the activity counter optional as the
  binding freshness rule requires; adds duplicate, nesting, member, numeric, identifier,
  executable, directory, and lock bounds; uses one fixed record lock; preserves per-observation
  versions; and arms the directory watcher before its initial scan with generation fencing. Guided
  setup now models the complete `statusLine` object, preserves non-command members, distinguishes
  owner previews from persisted diagnostics, stores only a safe prior command or absence marker,
  states the residual external-writer race honestly, and accounts for user/project/managed
  precedence and `CLAUDE_CONFIG_DIR`. Three additional owner decisions, bringing the total to ten,
  now block implementation: supported settings scope, the exhaustive source-state/lifecycle/
  diagnostic contract, and quiet helper exit behavior. The delegated complete gate passed
  project generation, Swift formatting and strict lint, imports, the Mac scheme, relay tests,
  typecheck, and dry run; explicit whitespace checks of both untracked M11 files, diff hygiene, and
  686 relative links also passed. No signed-in provider process, real Claude Code setting/history,
  helper installation, Cloudflare mutation, or real usage was accessed.

- 2026-10-24 — Owner/Codex — The first P1-M9 deployment passed the owner-observed Free-plan, configuration, required-metric-availability, and billing checks, but the finite smoke stopped at its initial authenticated destruction with an unexpected HTTP status. The independent authenticated destroy command failed at the same operation. Per the runbook, no later exercise ran; the owner deleted the isolated Worker, confirmed cleanup, cleared the pasteboard, and deleted the six temporary secrets. The attempt satisfies no remote smoke criterion. Because the harness's redaction collapsed safe status metadata, it now reports only the numeric actual and expected HTTP statuses while continuing to suppress the body, origin, credentials, and identifiers; a Node regression pins that boundary before a clean retry.

- 2026-10-24 — Codex — Re-reviewed and strengthened the untracked P1-M10 plan on
  `plan/p1-m10-codex-adapter`. The follow-up resolves the privacy contradiction between required
  owner-only launch storage, normalized snapshots, and the prior blanket persistence ban; binds
  the complete allowlisted environment, safe `PATH`, executable/interpreter identity, and working
  directory; fences stale child generations; rejects duplicate JSON keys and bounds empty bucket
  maps; orders default-bucket identity reconciliation; requires a valid surviving allowance
  window; and preserves a trailing refetch for notifications newer than an in-flight request. Two
  additional owner decisions now block implementation: whether to use the structured read-only
  `account/read` discriminator instead of parsing generic error prose, and the exhaustive source-
  state/retry/enum-backed diagnostic mapping. The JSON-lines architecture wording now counts the
  actual delimited payload rather than a nonexistent declared length. The delegated complete gate,
  explicit whitespace checks for both untracked plan files, diff hygiene, and 131 relative links
  passed. No signed-in provider process, profile, account value, real usage, network deployment,
  or relay state was accessed.

- 2026-10-24 — Owner/Codex — Approved and implemented temporary Scriptable use for the P1-M9 synthetic cellular check, followed by deletion of the script and app. The artifact self-tests WebCrypto against the public v1 AES-GCM vector before prompting, accepts the reader token and content key only through secure fields, bounds and authenticates the response, commits only to memory, activates only after commit, clears the pasteboard, and reports only pass/fail and byte counts. A deterministic owner-run preparation command resets the synthetic relay, registers a pending reader, and publishes the fixed public cellular profile. The delegated complete gate passed with 85 Swift package tests plus Mac smoke, 24 Worker tests, 11 Node tests, TypeScript, deployment dry run, diff hygiene, and 61 tracked documentation link checks. No Cloudflare state changed; the physical cellular run remains open.

- 2026-10-24 — Codex — Implemented and locally validated the initial P1-M9 harness checkpoint. The M8-native scripts fail-close deployment configuration, bulk-provision both digest secrets through one standard-input process, run the ten-operation stateful encrypted smoke, generate the additive daily model and owner-approved 1,422-request 30-minute sample, exercise cache-preserving faults, and prove authenticated destruction. Transport narrowly recognizes Cloudflare's documented bounded structured Error 1027 form. The active runbook covers owner-only deployment, metric/billing checks, promotion/rollback, and teardown. The complete local gate passed with 85 Swift package tests plus Mac smoke, 24 Worker tests, and nine Node tests; no Cloudflare state changed. The later review above corrects the initial daily acknowledgement count. Remote evidence and the physical cellular run remain open.

- 2026-10-24 — Codex — Created and reviewed the P1-M11 Claude Code adapter plan on `plan/p1-m11-claude-code-adapter`. The plan keeps M11 local and independent of M9/M10, orders a bounded status-line helper and versioned session records, revision-bound safe setup and restore, multi-session collection, synthetic integration, and owner-present calibration, and carries seven owner decisions before implementation. Review found that the calibration workflow is branch-stale and couples both providers; the generic configuration port cannot express or bind the exact settings edit; truncated session hashing lacks a decided length and CryptoKit dependency; status input, session records, enumeration, and synthetic command execution lack fixed bounds; never-observed records and mixed-version sessions lack deterministic policies; the trusted-system executable rule is undefined; atomic replacement alone does not prevent lost concurrent helper updates; and the provider test target needs approval for direct inward dependencies. The architecture test wording now names the intended status-line-only restore record instead of a forbidden whole-settings backup. Delegated plan validation passed project generation, imports, the Mac scheme, 24 relay Vitest tests, relay typecheck/dry-run, diff hygiene, and relative links; the complete shared-worktree gate remains red on six concurrent Transport-test line-length violations and two concurrent M9 harness tests, so its plan items remain unchecked. M11 remains `Planned`; no signed-in provider process, real Claude Code setting/history, helper installation, or real usage was accessed.

- 2026-10-24 — Owner/Codex — Resolved the remaining P1-M9 execution decisions. The isolated account is Workers Free with no paid add-on or existing Worker. The owner approved promote-to-100%, private active-version verification, immediate smoke, and rollback because Durable Object Workers have no Version URL; no metadata or observability binding is added. Required metrics are checked immediately after initial deployment with teardown on a gap. The owner replaced the 24-hour soak with one uninterrupted 30-minute sample, accepting its weaker stability and daily-quota evidence while retaining checked-in 24-hour workload accounting, and confirmed the owner-run commands, iPhone cellular check, private synthetic-secret storage, and final deletion.

- 2026-10-24 — Codex — Created and reviewed the P1-M10 Codex adapter plan on `plan/p1-m10-codex-adapter`. The plan keeps M10 local and independent of the M9 relay gate, orders profile configuration, bounded JSON-RPC, normalization, scheduling, synthetic integration, and owner-present calibration, and carries five owner decisions before implementation. Review found that the source-calibration runbook requires a nonexistent exact branch and couples Codex to Claude Code; the generic configuration port cannot express an owner-selected profile/launch preview; optional upstream account identity is insufficient for the reducer's account-isolation guarantee; provider limit state needs an explicit false case; and the provider test target needs approval for direct inward test dependencies. The delegated complete gate, diff hygiene, and tracked relative Markdown links passed. M10 remains `Planned`; no signed-in provider process or real usage was accessed.

- 2026-10-24 — Codex — Began P1-M9 Task 1 from commit `dc3e102`, recording the five-document planning worktree and a passing delegated baseline gate. XcodeGen 2.46.0, Node 26.8.1, npm 11.19.0, and Wrangler 4.151.2 matched the documented toolchain; project generation, Swift checks, 39 Swift package tests plus the Mac smoke test, 23 relay tests, TypeScript, deployment dry run, diff hygiene, and tracked relative Markdown links passed. No Cloudflare state changed. Account/metric preflight and the release-smoke owner decision remain open.

- 2026-10-24 — Codex — Reviewed and strengthened the P1-M9 relay synthetic-data gate. The plan now uses the completed M8 hardening handoff, separates M9 relay adoption from P1-M14 Sideloadly validation, requires a stateful synthetic client and reproducible fault commands, pins additive worst-case workload accounting, treats secret provisioning as a deployment-capable mutation, establishes metric evidence before the 24-hour run, mandates teardown after failure, and avoids editing the archived P1-M2 record. The review found one owner decision that must precede implementation: Cloudflare does not generate Version URLs for Durable Object Workers, while the binding design requires a version-URL smoke and forbids Preview/Version URLs; a 0%-traffic override cannot be verified without forbidden observability or a new metadata binding. The recommended replacement is promote-then-smoke with immediate rollback on the isolated synthetic-only M9 Worker. The complete local gate and Markdown-link check passed; M9 remains `Planned` and no Cloudflare state changed.

- 2026-10-23 — Claude Code — Drafted the P1-M9 relay synthetic-data gate overview and sequence. The plan ports the unmerged `spike/cloudflare-relay` harness onto the M8 relay with pinned versions, keeps all Cloudflare authentication, deployment, billing, and secrets owner-run, and moves the Sideloadly re-sign check to P1-M14. It requires the open M8 reader-revalidation hardening to be resolved first and records four owner decisions: finish the M8 hardening first, use a synthetic Shortcut or script for the cellular read, allow `node --test` for harness tests, and use the existing Free account with a simulated rather than exhausted quota boundary. No code or deployment changed; M9 remains `Planned`.
- 2026-10-23 — Codex — Hardened the completed P1-M8 relay review: invalid reader requests no longer initialize Durable Object storage, and authenticated snapshot reads preserve valid envelopes up to the 64 KiB wire limit. New regression coverage and the complete gate passed with synthetic data only.
- 2026-10-23 — Codex — Completed P1-M8 Relay implementation. The Worker and SQLite Durable Object enforce the frozen v1 fixtures for all ten operations, strict canonical and streamed request validation, digest-only authority, reader lifecycle, refresh mailbox replay rules, byte-preserving ETags, and atomic destruction. The final 21-test Workers Vitest suite covers fixture parity, boundaries, expiry, concurrency, privacy, and schema failure. The full gate passed with synthetic data only; deployment, Free-plan/billing, capacity, cellular, and teardown evidence remain P1-M9 work.
- 2026-10-23 — Codex — Completed P1-M7 Transport crypto and protocol. The frozen cross-language fixture revision is `5d69907210abdf502a855136c6cd00900c0dde80314e7995886f40ce901d5c81`, covering canonical envelope and pairing bytes, all ten operations, error responses, ETags, registration collisions, refresh-ID collisions, and the sequence bound. The final test-runner gate passed project generation, formatting, strict lint, imports, 238 Swift package tests, the Mac scheme test, six relay tests, typecheck, and a non-deploying Wrangler dry run. The M8 plan now records the fixture handoff; real Keychain and deployed Cloudflare evidence remain owned by their later milestones.
- 2026-10-23 — Codex — Started P1-M7 from HEAD `353043ddc791856b17a06a66f26b7391020bef8c`, preserving the separate M6/M8/protocol documentation edits. The isolated clean baseline and the current Transport checkpoint both passed the complete contribution-guide gate with test-runner evidence. Added the approved local Transport test imports, synthetic shared protocol fixtures, crypto, pairing, Keychain policy, clipboard, and HTTPS relay adapters; M7 remains `Active` while the remaining acceptance and close-out evidence is gathered.
- 2026-10-23 — Owner/Codex — The owner directed P1-M8 implementation to wait for M7 checkpoint A to be completed separately. For the later relay handoff, the owner approved exact reader-registration retry with the original expiry and generic `400 badRequest` for changed or reused digests, including privileged-role digests. The owner also approved separate last-accepted and last-completed refresh IDs: an expired last-accepted ID retry or cross-reader live-ID collision returns generic `400 badRequest`, while the last completed ID retains `409 requestAlreadyCompleted`. The last-accepted guard is replaced by a different accepted ID. These outcomes are documented in the relay contract and must be pinned in M7's shared fixtures before M8 state-machine work.
- 2026-10-23 — Codex — Reviewed the P1-M8 plan against the relay and Transport contracts, the current scaffold, and the earlier synthetic relay evidence. Tightened canonical-byte and streamed-size tests, fail-closed role and expiry handling, collision and replay-state checks, and close-out validation. The review found two protocol question groups for owner resolution before their implementation: repeated or colliding reader registration, and expired or cross-reader manual request ID reuse. The relay design now makes clear that an invalid read token cannot trigger expiry cleanup. The complete contribution-guide gate passed on the revised planning worktree with test-runner evidence in the M8 overview. M8 remains `Planned`, dependent on M7 fixtures.
- 2026-10-23 — Codex — Drafted the P1-M8 relay implementation overview and sequence. The plan ties all ten Worker operations and SQLite state transitions to the approved v1 contract, makes M7's frozen shared fixtures an entry condition, and leaves owner-present deployment, quota, billing, cellular, and 24-hour measurements with P1-M9. The current planning worktree passed the complete gate after the test runner retried Apple-side checks with approved host cache access; this is not M8's isolated implementation baseline. M8 remains `Planned` until fixture and baseline evidence is available.
- 2026-10-23 — Owner/Codex — Approved the P1-M7 v1 protocol profile: sorted-key authenticated header JSON, strict compact outer JSON with unpadded base64url binary fields, operation-specific versioned relay bodies and stable error codes, a strong ETag, a symmetric 30-second local pairing-deadline allowance, the two existing local test-target dependencies, and the injected macOS pasteboard helper in Transport. A follow-up choice caps v1 JSON-number sequences at `2^53 - 1` for exact Swift/TypeScript comparison. The exact profile is recorded in [Transport](../architecture/transport.md#v1-wire-profile) and [relay](../architecture/relay.md#v1-http-body-profile); P1-M7 remains `Planned` until implementation and the baseline gate.
- 2026-10-23 — Codex — The complete contribution-guide gate passed for the current plan-review worktree after redirecting compiler and Xcode caches to `/private/tmp/reset-radar-validation`: project generation, format lint, strict SwiftLint, import check, Mac `xcodebuild test`, relay `npm ci`, tests, typecheck, and deployment dry run. Initial default-cache runs failed because the sandbox denied writes to user cache directories; the retry passed. This is plan-review validation, not the isolated clean baseline required when M7 implementation starts.
- 2026-10-23 — Codex — Reviewed the P1-M7 plan against the six Application ports, ten relay operations, status fixtures, and owner decisions. Expanded the proposed contract to cover request bodies, error codes, ETags, canonical pairing bytes, shared fixture loading, response-size boundaries, setup-origin validation, and the separate M9 platform-quota evidence. The five owner questions remain open; no protocol or build-contract choice is treated as approved.
- 2026-10-23 — Codex — Drafted the P1-M7 Transport overview and sequence. The plan covers crypto, pairing, non-interactive Keychain behavior, the HTTPS relay client, and shared Swift/TypeScript fixtures. Five owner questions remain open on exact wire bytes, ambiguous response bodies, deadline tolerance, the test-target dependency, and the clipboard helper boundary; implementation remains `Planned` until answered.
- 2026-10-23 — Codex — Closed P1-M6 after the complete gate passed for the pre-implementation baseline (`a4066de`), checkpoint A (`db9f7cf`), and final code. The final result bundle reports 81 Storage tests and 488 total Mac tests; formatting, strict SwiftLint, imports, and relay test, typecheck, and dry run also passed. Added real-store integration for Watch erasure after re-pairing and interrupted manual-refresh and notification waits, and tightened permissions on existing Storage directories and lock files. The closing commit is rechecked from a clean checkout.
- 2026-10-23 — Codex — Reviewed the P1-M6 storage commits and fixed write-time validation, successful migration replacement, publisher sequence overflow, fast-path lock cancellation, notification-claim timing, and atomic-writer durability error reporting. Focused storage tests (77) and the full contribution-guide gate passed. Kept P1-M6 `Active` because the pre-change baseline and remaining completion checklist have no recorded evidence.
- 2026-10-23 — Owner/Claude — Accepted all seven recommended defaults for the P1-M6 open questions, including the `Package.swift` test-target dependency edit (Domain and Application added to `ResetRadarStorageTests`). The helper-executable alternative for cross-process evidence is declined. P1-M6 work moves to `feat/p1-m6-storage`; the plan commit left `feat/p1-m5-application-use-cases`.
- 2026-10-23 — Claude — Drafted the P1-M6 plan (overview and sequencing) for `ResetRadarStorage`. Storage goes before Transport and the relay because the Mac, iOS, and Watch roots all need it and P1-M5 deferred real cross-process lock evidence to it. Seven open questions carry recommended defaults (injected root URL, polled `flock` with a timeout, descriptor-level contention evidence, test-target imports, snapshot facade names, size and ring bounds, corrupt versus incompatible files); the milestone stays `Planned` until the owner answers.
- 2026-10-23 — Claude — Fixed the minor P1-M5 review findings. `ReaderRefreshPolicy` now follows the spec's "more than" for the 15-second and five-minute rules (the 60-second tick stays a minimum). `PairReader` revokes a superseded pending offer, keeps reporting `confirmed` after activation, and no longer calls an offer expired (and revokes it) when the relay list call fails. `AcceptPairing` deletes secrets only after the state clear succeeds and also clears the lease and pending request. `IngestRelaySnapshot` reports `storageFailed` instead of `invalidSnapshot` and keeps the ETag for an unchanged sequence. `RequestMacRefresh` shows a failed read for a Claude Code-only action. `ConfigureSources.restore` needs `confirmed: true`. `SecretStore.delete` is documented as idempotent. Reset reminders reconcile the remaining slots after one fails, `start` of a Live Activity ignores an overlapping tap, and a seal failure other than `unsupportedVersion` stops publication as `payloadRejected`. Not changed: out-of-order report regression in `SnapshotReducer` (the adapters own report monotonicity), and the `ForgetMac` cleared-payload `try?` (valid by construction).
- 2026-10-23 — Claude — Reviewed P1-M5 and fixed what the review confirmed. `PublishSnapshot` now serializes sends (overlapping publications no longer race for the relay sequence and halt on a false 409), restamps a snapshot with the active publisher ID, re-evaluates the oversized-envelope stop when result or diagnostic counts change, and guards the late pairing-floor write against a reset publisher. `CollectUsage` serializes load, reduce, and commit, and owns manual-result merging (`addManualResults`), so `HandleManualRefreshRequests` no longer writes the snapshot itself; it also commits results before marking requests handled and reports `sourceUnavailable` when ingest fails. `RequestMacRefresh` recognises a result committed by another process. `AfterCommitPipeline` keeps `needsAppReconcile` when a widget committed a newer snapshot. Reset reminders and Live Activities leave their effects alone when the store cannot be read (`VisibleSnapshot.load()` throws). `EraseWatchData.erase()` returns an `EraseOutcome`, `CommitWatchPayload` reports `storageFailed`, and the local-erase hold now applies before the first installation. Not changed, for owner or later-milestone decisions: `ReaderRefreshPolicy` inclusive thresholds versus the spec's "more than", `SecretStore.delete` idempotency in the port contract, and `PairReader` revoking a superseded pending offer.
- 2026-10-23 — Claude — Implemented P1-M5 in three checkpoint commits plus close-out. Choices the plan left open, for owner review: the iPhone, iPad, Mac, and Watch stores expose `load` and `transact` (an atomic read-modify-write under the adapter's lock) instead of `claimFetch`, `commitResult`, `commitRemote`, and `commitWatch`; `ReaderState` contains the committed snapshot so snapshot and reader state replace atomically; a new `WatchCacheStore` port holds the Watch cache, so there are 21 ports. `UsageSource.refresh()` returns a `ReadReceipt` that carries the normalized report. List and registration relay calls return `RelayResponse`. `SetUpRelay` has `prepare` (digests) and `activate` (wipe, then bind through `PublishSnapshot.bind`). `PublisherState.lastPublishedSequence` is the pairing floor. A `CollectUsage.heartbeat()` restamps `generatedAt` so liveness stays accurate. Domain gained four diagnostic categories with factories and `AllowanceWindow.markingRetained()`. `DestroyRelay` keeps the account-scope key, which is not a relay secret. `ReconcileReaders` flags a device missing on the relay instead of deleting it. `ForwardToWatch` sends nothing while activation is pending. The `ResetRadarApplicationTests` target now depends on `ResetRadarDomain` (owner-approved). **Needs owner confirmation before merge:** the store-port reversal of the accepted Q4 shape (see the first sentence), because Storage, Transport, and both provider milestones build on these ports. The final review was a self-review by the author, not a fresh reviewer.
- 2026-10-23 — Owner/Claude — P1-M5 plan review. Approved the one `Package.swift` edit (add `ResetRadarDomain` to `ResetRadarApplicationTests` dependencies). Declined an owner review gate after checkpoint A. Chose one commit per checkpoint. The review also added `badRequest` to the relay outcomes, a `ReadReceipt` for `UsageSource.refresh()`, reader-side backoff and secret-cache invalidation tests, and noted that `AccountScoper` has no calling use case.
- 2026-10-23 — Owner/Claude — Answered the ten P1-M5 open questions. Kept one milestone with three checkpoints. Domain may change freely, including incompatible changes (replaces the recommended additive-only rule). Renamed the `Clock` port to `AppClock` to avoid shadowing Swift's `Clock`. Accepted the recommendations for the rest: `Clock.sleep` only inside `RequestMacRefresh`'s bounded wait; base `SnapshotStore` plus three role protocols; `SecretGenerator.randomUnit()` for jitter; plain read-model structs; complication counters in `ReaderStore`, enabled flag in `PreferenceStore`, forced-read time in memory; all fetches suppressed while awaiting activation; background request defaults of `now + 1 min` and `lastSuccess + 15 min`; a rolling 24-hour complication budget.
- 2026-10-23 — Claude — Drafted the P1-M5 plan (overview and sequencing). It covers the whole Application module and TestSupport because no later milestone owns a use case, defines the error taxonomy application.md lacks, lists nine spec gaps and ten open questions with recommended defaults, and stays `Planned` until the owner answers them.
- 2026-10-23 — Claude — Implemented P1-M4. P1-M3 was fast-forwarded into local `main` at the owner's direction so the branch could start from `main`. Choices the plan left open, for owner review: a `completedAt` up to five minutes ahead of `now` is kept and anything later is dropped (the skew rule used for observations); `heartbeatSeconds` is valid only in `1...3600`; an invalid window is dropped whole rather than keeping a reset-only window; a retained window whose `resetsAt` is at or before `now` is `unavailable`, so `resetAwaitingRefresh` applies only to reported windows; `nextChange` is the next representable instant after the observation window ends; `HomeSlotResolver.resolve` takes `now` for the diagnostic timestamp; `ReaderID`, request, and installation IDs are 128-bit; diagnostics decoded from a snapshot are stamped with `generatedAt`.
- 2026-10-22 — Owner/Claude — Accepted the recommended defaults for the six P1-M4 open questions: ISO-8601 UTC dates with millisecond precision from one shared `WireCoding` pair; precision metadata as `fractionDigits` of 0 or 1; provider limit state as `reached`, `ordinaryUsageAllowed`, or `unknown`; a closed `DiagnosticEvent` category enum with an `unknown` decode fallback; rejection of a snapshot with non-positive `heartbeatSeconds`; and an unknown `TransportStatus` in a `WatchPayload` decoding to `incompatible`.
- 2026-10-22 — Claude — Drafted the P1-M4 plan (overview and sequencing). It implements `ResetRadarDomain` only, lists six wire-level open questions with recommended defaults for owner answers, and stays `Planned` until they are answered.
- 2026-10-22 — Owner/Claude — Extended Phase 1 with P1-M4 through P1-M16 (domain through Watch) and added matching exit criteria. Decided to build the Mac before iOS, and suspended the iPhone, iPad, and Watch `xcodebuild test` runs in the gate until implementation exists (iOS and iPad return in P1-M14, Watch in P1-M16). The schemes and targets are unchanged.
- 2026-10-22 — Owner/Claude — Closed P1-M2 as `Done` and extracted its unchecked validation work to [P1-M2 open work](../archive/p1-m2-open-work.md). Each item is now implemented and verified by the module that owns the related feature, not tracked at milestone level; the pre-scaffolding gate deferrals were closed because P1-M3 passed the complete gate. Archived work is referred to as archived work or a record, never as a plan.
- 2026-10-22 — Claude — Completed P1-M3. The scaffold (XcodeGen `project.yml`, `ResetRadarKit`, relay package, lint and format configuration, import-boundary and generation scripts) passes the complete gate from a fresh clone. Findings: the iOS destinations need `OS=26.1` because `name=` resolves to the newest runtime; the Mac signing check is a scheme post-action; the explicit SwiftPM import check is off by default and is run by `Scripts/check-imports.sh`; two moderate `npm audit` advisories exist in development dependencies and are left for an owner decision.
- 2026-10-22 — Owner/Claude — Started P1-M3 without waiting for P1-M2 ("Ignore P1-M2"), reversing the earlier wait-for-every-item decision. P1-M2 stays `Active`; its open spikes are not carried into P1-M3 and no physical-device check is assigned to P1-M3. Approved the proposed bundle identifiers as final. Approved exact relay development dependency pins from the validated spike lockfile: `@cloudflare/vitest-plugin` 1.4.5 (MIT), `typescript` 5.9.3 (Apache-2.0), `vitest` 4.1.11 (MIT), `wrangler` 4.151.2 (MIT OR Apache-2.0). Created the gate simulators: iPad Air 11-inch (M2) on iOS 26.1 and Apple Watch Series 11 (42mm) on watchOS 27.0 (the earlier watchOS 26.1 device was below the floor).
- 2026-10-22 — Owner/Claude — Reviewed the P1-M3 plan and decided: wait for every P1-M2 item before starting (no carry-forward); lower the iOS and iPadOS floor from 26.6.2 to 26.1 so the installed runtime hosts both reference devices (iPhone 17 Pro Max and iPad Air 11-inch (M2) create on 26.1 and refuse on 27.x); sign and check only Release Mac builds, leaving Development builds unsigned; use Swift Testing for package tests and XCTest for app-level and UI bundles; enforce XcodeGen 2.46.0 in the generation script; pin the four spike relay devDependencies exactly after owner approval. The plan also gained a proposed identifier table, import-boundary requirements, a note that the Mac signing check may need to run outside a build phase, and the sequencing file renamed from `-architecture` to `-sequence`.
- 2026-10-22 — Owner/Codex — Made the source-calibration spike explicitly `codex-profile` aware for the owner's two-profile setup. Preparation now prompts privately for every selected profile, creates isolated ordinal launchers and reports, ignores ambient `CODEX_HOME` selection, and verifies every selected profile without retaining profile names or homes in project evidence. This calibration support does not decide simultaneous multi-account product behavior.
- 2026-10-22 — Owner — Chose XcodeGen with its specification as the source of truth and generated `ResetRadar.xcodeproj` output left untracked. Set bundle prefix `com.unidentifiedstealthstartup`, main-app identifier `com.unidentifiedstealthstartup.ResetRadar`, and App Group `group.com.unidentifiedstealthstartup.ResetRadar`. Retained the approved iPhone 17 Pro Max and iPad Air 11-inch (M2) simulator destinations and will install a compatible iOS 26.x runtime. Accepted the XcodeGen-based repository layout and promoted it from `Proposal` to `Active`.
- 2026-10-22 — Codex — Added a synthetic-only, owner-run Mac Keychain validation runbook. It creates an isolated signed harness with no production target, relay integration, or provider data; specifies non-interactive, rebuild, login-launch, locked-Keychain, lifetime, renewal, and profile observations; and includes cleanup and redacted evidence instructions. The validation result remains open.
- 2026-10-20 — Owner — Approved the system architecture and all module designs for promotion from `Proposal` to `Active`. Explicitly accepted the five follow-up security findings, including the residual Universal Clipboard and offline-Watch risks, before targeted verification. This approval freezes the design for scaffolding; it does not waive runtime, synthetic, physical-device, cost, or signing gates, and no real usage data may reach the relay until its required gate passes.
- 2026-10-20 — Codex — Responded to the follow-up architecture security review with a durable Watch-erasure receipt and local erase hold, explicit manual-pairing clipboard handling, bounded Codex and relay input, a fixed HTTPS relay origin with redirects rejected, and one documented running-process Keychain-lock behavior. At that point these remained proposed designs; the approval entry above supersedes their review status, while physical and synthetic validation remain open. See the [review response](../research/spike-results.md#proposed-architecture-response).
- 2026-10-20 — Owner/Codex — Changed relay pairing activation to an explicit authenticated confirmation after the reader saves its Keychain and local state. The preflight read alone no longer activates a reader. Added a relay-assigned five-minute pending expiry, idempotent retry, staging recovery, and tests for local-save failure and expired registration.
- 2026-10-20 — Owner/Codex — Selected Mac-assisted manual refresh for iPhone and iPad in the first version, using short-lived authenticated relay requests and an encrypted result tied to the request. Also decided that a Home window absent from a provider report becomes unavailable after its last known reset passes, and that an existing Claude Code status-line command with possible inline secrets must be left untouched. Added protocol, capacity, latency, failure, and source-state verification requirements.
- 2026-10-20 — Owner/Codex — Requested an optional iPhone/iPad mode that fetches provider usage independently when selected, preferably through vendor-supported device login. The [official mobile access review](../research/official-mobile-usage-access.md) found no documented, permitted native iOS path to the required personal subscription windows for either provider, so the Mac collector remains the first-version source. Reviewed architecture contracts for local-versus-relay sequence ownership, conditional reads after cache loss, in-flight fetch completion, Watch message ordering after re-pairing, Claude Code observation timing, widget-only notification updates, and the Mac instance lock; added focused verification cases.
- 2026-10-19 — Owner — Selected Xcode 27.1 with `xcode-select` and accepted its license. Its iOS 27.1, watchOS 27.0, and macOS 27.0 SDKs satisfy the platform targets. Still missing: iOS and watchOS simulator runtimes, and a code-signing identity.
- 2026-10-19 — Owner/Claude — Reviewed the sync and refresh models, the Mac Keychain, and the module structure.
  - **Decided:**
    - widgets may refresh the cache from the relay during a reload, at most every five minutes;
    - the foreground app fetches every 60 seconds;
    - Mac secrets stay in the login keychain under one Apple Development identity, with ad-hoc builds rejected and non-interactive calls;
    - a clean-architecture `ResetRadarApplication` layer, with adapters depending only inward.
  - **Platform targets:**
    - iPhone 17 Pro Max and iPad Air 11-inch (M2) on iOS/iPadOS 26.6.2+;
    - Apple Watch Series 11 (42mm) on watchOS 26.6+;
    - MacBook Pro M5 Max 128 GB on macOS 26.7.1+.

    The same models are the simulator destinations, replacing the iPhone 17, iPad Pro 13-inch (M5), and Series 11 (46mm) destinations.
  - **Sync and refresh fixes:**
    - App Nap guard, plus wake and network-restore publication;
    - Codex notification reads at least 60 seconds apart, and a read after each reset;
    - a "material change" definition with 30-second coalescing;
    - foreground ticker, cross-process claim and compare-and-swap commit, and the widget-process `needsAppReconcile` flag;
    - background-task lifecycle aimed at just after the next reset;
    - Watch-initiated refresh and the complication budget;
    - recomputed relay capacity.
  - **Docs:**
    - twelve module designs under `docs/architecture/`, each with a Mermaid internal diagram;
    - `architecture.md` rewritten as the system overview;
    - the Mac Keychain research with its validation spike, and new P1-M2 checklist items.
  - **Toolchain finding:** the selected Xcode 26.1.1 cannot build these targets; Xcode 27.1 is installed but not selected, and this Mac has no signing identity.

- 2026-10-19 — Owner — Added an iPad simulator run (`iPad Pro 13-inch (M5)`, to be confirmed at scaffolding) of the `ResetRadar` scheme to the complete gate, because the iOS app is now universal.
- 2026-10-19 — Owner/Claude — Reviewed and revised the software architecture.
  - **Decided:**
    - universal iPhone/iPad app;
    - reset notifications on iPhone, iPad, and Mac;
    - Codex Home rings use the default bucket;
    - relay reader activation marker plus `GET /v1/readers`;
    - shared modules in a local `ResetRadarKit` Swift package.
  - **Claude Code status line:**
    - `observedAt` advances only on evidence of a new API response;
    - per-session files stop concurrent sessions from overwriting each other;
    - windows Claude Code drops after reset are retained;
    - `spend_limit` is excluded.
  - **Relay and pairing:**
    - setup now provisions, then wipes, then binds, so earlier tokens die before storage is reused;
    - a response-to-client-state table was added.
  - **Model:**
    - a first-class `HomeSlot` keys every selection;
    - per-window validation;
    - an explicit presentation-state precedence;
    - `SourceSnapshot` is defined;
    - Mac liveness is derived from `generatedAt`.
  - **Platform:**
    - the Live Activity's `staleDate` is now the earlier of freshness expiry and reset, and the app ends it on its next run;
    - a Watch App Group for the complication;
    - `completeUntilFirstUserAuthentication` protection for the iOS cache;
    - UTC-fixed notification triggers;
    - Codex discovery and child-process environment;
    - a single-instance Mac lock;
    - Mac signing without provisioning-profile entitlements.
  - **Docs:** fixed the stale section references in the P1-M2 overview and the "rotation" wording in the UX information architecture.

- 2026-10-19 — Owner — Approved the `ResetRadarMac` and `ResetRadarWatch` scheme names used in the gate and the build contract in [architecture.md](../architecture.md).
- 2026-10-19 — Owner/Claude — Moved the software architecture from `phase-1/milestone-02-software-architecture.md` to `docs/architecture.md` so it stands apart from planning documents; P1-M2 links to it.
- 2026-10-19 — Owner/Claude — Reviewed the P1-M2 plan. Decided: destroy-and-re-pair is the only key response (no in-place rotation); up to three paired iPhones/iPads with per-reader revocable read tokens; the gate adds Mac, Watch, and relay (`npm test`, `tsc --noEmit`) checks without a new TypeScript linter; spike harnesses stay out of the repo and evidence goes in `docs/research/phase-1/spike-results.md`. Fixed: availability split into wire source state and device-derived freshness, a `ResetRadarStatusLine` helper target with a stable install path, Mac App Sandbox off, persisted sequence counter, HMAC account scope, and Live Activity `staleDate`. Moved spike and validation sequencing from the architecture document to the overview.
- 2026-10-19 — Owner/Codex — Completed the architecture interview. Removed manual reset rules entirely; selected a native Mac sidebar plus menu-bar companion, standard Mac Settings, a Watch two-by-two grid with product details and one configurable complication, configurable single-window small/Lock Screen widgets plus a four-window medium widget, per-window opt-in notifications, user-started Live Activities, tintable familiar bitmap toolbar icons, QR pairing with a manual fallback, `AfterFirstUnlockThisDeviceOnly` iPhone relay keys, a guided Claude Code installer, and explicit launch-at-login opt-in.
- 2026-10-19 — Owner — Approved strict TypeScript, npm, Wrangler, Workers Vitest support, and a SQLite-backed Durable Object for the relay. Authorized owner-present synthetic Cloudflare deployment and owner-present read-only signed-in Codex and Claude Code schema smoke tests under the documented redaction boundary.
- 2026-10-19 — Owner — Defined the remaining iOS Main Toolbar destinations: Benefits with a gem bitmap icon, Community with a community bitmap icon, and Insight with an insight bitmap icon. Each currently opens its own intentionally empty screen.
- 2026-10-19 — Owner — Added an iOS Main Toolbar with five bottom items, each using a bitmap icon above its label. Home is first and shows the Allowance Grid; positions two through four remain TBD; All is fifth, uses a three-horizontal-bars icon, and shows an empty screen for now.
- 2026-10-19 — Owner — Provisionally chose a persistent first-screen grid instead of blocking onboarding. Before pairing or collector setup, rings remain visible as unavailable and a contextual Setup Banner offers the next action; this interaction may be revisited later.
- 2026-10-19 — Owner/Codex — Made ring navigation product-scoped: either Codex ring opens Codex Usage Details and either Claude Code ring opens Claude Code Usage Details, with the selected window initially emphasized. Usage Details shows both windows, exact reset timing, provenance, freshness, availability, synchronization, refresh, and disclosed diagnostics; excluded analysis features remain absent.
- 2026-10-19 — Owner — Chose percentage used as the binding orientation for every Allowance Ring and usage surface. Store and present the validated provider `usedPercent` value without converting it to percentage remaining; rings fill from 0% toward 100%. This supersedes the earlier remaining-percentage decision.
- 2026-10-19 — Owner — Required the first Mac screen to use the same Allowance Grid, Allowance Rings, cell placement, and information as the first iPhone screen.
- 2026-10-19 — Owner — Defined the first iPhone screen as a logical two-by-two Allowance Grid of circular Allowance Rings: Codex five-hour and weekly on the top row, Claude Code five-hour and weekly on the bottom row.
- 2026-10-19 — Owner/Codex — Defined **Codex** and **Claude Code** as the canonical tracked-product names, with **Codex app-server** and **Claude Code status line** reserved for acquisition provenance. Architecture documents must contain no phase or milestone references; planning documents may link to them.
- 2026-10-19 — Owner — Approved a narrow pre-scaffolding gate exception: a command that is inapplicable solely because its planned files or targets do not exist may be explicitly deferred to P1-M3, while all applicable checks must pass and P1-M3 must pass the complete gate. P1-M1 is complete and P1-M2 is active.
- 2026-10-19 — Owner — Reviewed and approved the complete P1-M1 research set. The research documents moved from `Draft` to `Active`; approval does not waive the validation evidence and conditional gates recorded in [owner-decisions.md](owner-decisions.md).
- 2026-10-19 — Owner — Added an Apple Watch app to the first-version scope. The watch receives normalized, credential-free snapshots through the paired iPhone and requires physical signing, installation, synchronization, stale-state, and seven-day refresh validation.
- 2026-10-19 — Owner — Resolved the remaining P1-M1 questions in [owner-decisions.md](owner-decisions.md): permanently excluded consumer credentials and API-key mode; chose blank manual ChatGPT setup and a neutral Reset Radar identity; included Live Activities for short windows; fixed recurring rules to their selected time zone with OS-local presentation; excluded threshold alerts, history, and forecasts; required the Mac collector in the first usable version; conditionally approved the encrypted Cloudflare relay with one authoritative Mac and opportunistic background refresh; and chose local development signing for the Mac collector.
- 2026-10-19 — Owner — Accepted the included `workers.dev` hostname for the Cloudflare relay. Reset Radar will not require or purchase a custom domain while the US$0 requirement applies; the separate decision on Cloudflare's trust boundary, one authoritative Mac, and the synthetic validation result remains open.
- 2026-10-19 — Owner/Codex — Required the Cloudflare relay to cost US$0 for personal use and requested a hidden-fee audit. The research now makes Workers Free, SQLite-backed Durable Objects, `workers.dev`, disabled observability, per-Worker secrets, and no paid add-ons a binding cost contract; it identifies the US$5 Workers Paid minimum, metered overages, custom-domain renewal, logging changes, Logpush, shared quotas, and external services as cost paths to avoid.
- 2026-10-19 — Owner/Codex — Directed synchronization research to treat Cloudflare as the major option. Current documentation changes the proposed primary from an iCloud Drive folder to an owner-operated Worker plus SQLite-backed Durable Object because it provides Free-plan, strongly consistent store-and-forward. At this point Q11 remained open; the later owner-decision entry above supersedes that status.
- 2026-10-19 — Codex — Compared cellular Mac-to-iPhone synchronization costs and constraints. A user-selected, application-encrypted iCloud Drive file was the first proposed P1-M2 spike; Tailscale was the no-storage fallback. The Cloudflare-primary entry above supersedes that proposed order; the comparison remains relevant for fallback selection.
- 2026-10-19 — Codex — Pinned the automatic-usage design to current `openai/codex` and `anthropics/claude-code` revisions. Codex supports active app-server reads plus sparse turn-derived updates; Claude exposes account-level last-response measurements through status-line/function-hook surfaces and therefore requires stricter freshness language.
- 2026-10-19 — Owner — Required automatic usage percentages. P1-M1 selects Codex app-server for Codex and Claude Code status-line snapshots for Claude, collected on Mac and synchronized as credential-free observations. Manual entry is no longer the primary source.
- 2026-10-19 — Owner — Added remaining-percentage usage tracking. Each service can have multiple independent allowance windows, including simultaneous five-hour and weekly windows. The initial manual-snapshot recommendation was superseded later the same day by the automatic-acquisition decision above.
- 2026-10-19 — Owner — Chose personal-use-only distribution with a free Apple account and sideloading. P1-M1 selects Sideloadly as the supported installation and seven-day refresh path; LiveContainer is excluded because guest app extensions cannot be registered, which conflicts with Reset Radar's widgets.
- 2026-10-19 — Codex — Added a separate GitHub prior-art study after screening the first 20 results from four repository searches. The study inventories 16 direct reset trackers, eight adjacent tools, their credential/data-source patterns, licenses, maintenance signals, and recurring public issue themes.
- 2026-10-19 — Codex — Re-ran P1-M1 from primary sources. Expanded the service matrix to every current individual tier, confirmed vendor automation restrictions, completed the Apple capability and security evidence, added public issue/review signals to prior art, and resolved former Q9: Claude paid weekly resets use a fixed account-assigned day/time shown in Settings > Usage.
- 2026-10-19 — Pastry Personal 5 — Phase 1 "Foundation" planned with three milestones: P1-M1 initial research, P1-M2 software architecture, P1-M3 scaffolding. The phase title is a working name.
- 2026-10-19 — Pastry Personal 5 — P1-M1 plan reviewed and expanded into a feasibility study. Deliverable moved to `docs/research/phase-1/initial-research-on-feasibility.md`. No accounts may be logged into or scraped without owner approval.
- 2026-10-19 — Pastry Personal 5 — P1-M1 covers Claude and ChatGPT only; other services are out of scope.
