# P1-M11: Claude Code adapter overview

Status: Done

Implement the macOS-only Claude Code status-line half of
`ResetRadarProviderAdapters` and the `ResetRadarStatusLine` helper. The
[sequence](milestone-11-claude-code-adapter-sequence.md) orders the bounded helper and session
format, safe guided setup, multi-session collection, synthetic tests, and owner-present source
calibration.

## Goal

Claude Code can send its first-party `rate_limits` status-line data to a local Reset Radar helper
without Reset Radar reading or copying provider credentials, prompts, responses, project paths,
or authentication files. The helper writes one privacy-minimized record per Claude Code session;
the source merges the freshest observation for each window kind into complete `SourceSnapshot`s
for the one Claude Code account row (a stable `AccountID`, no provider scope) while preserving
last-response freshness and dropped-window semantics.

Guided setup installs only after the owner confirms the exact change. It never replaces an
existing status-line command that cannot be parsed and proved safe, and a later restore never
overwrites a user change. The adapter, helper, and synthetic tests pass the complete
[contribution-guide gate](../contribution-guide.md#required-validation). Owner-present calibration
separately validates the installed Claude Code field shape, activity signal, two-session
isolation, idle behavior, and proposed 60-minute current-data window without retaining raw usage
or identity data.

## Why this milestone can proceed

[Phase 1](phase-1.md#order-and-dependencies) makes production work depend on M10 Checkpoint A.
That checkpoint has landed on `main` (commits `18f5723`, `1c791bc`, `8eb5c3d`, and `b8d64bd`): the
account catalog and account-aware `AccountSource`/`UsageSource` contracts, `ConfigurationState`
(`notConfigured`, `configured`, `incompatible`, `unsafe`), opaque `ConfigurationOptionID` and
`ConfigurationPreviewRevision`, `ConfigureSources` with its `unsafeExistingConfiguration` guard, the
`ReadReceipt` cases (`performed`, `deferred`, `unavailable`), the `ProviderAccountCatalogStore`, and
the Domain/Application test imports. M10's owner-run Codex calibration is still open and is not an
M11 dependency. The ProviderAdapters Claude Code directory and the `ResetRadarStatusLine`
executable (`main.swift` holds only a scaffold comment) do not exist yet.

M9 is not an M11 dependency. M11 remains local and never publishes a snapshot, contacts the relay,
starts a Claude Code turn, or reads Codex. Its source-specific calibration preparation may proceed
independently, but implementation must consume rather than duplicate M10's shared account
contracts. M12 owns composition into the Mac collector and invokes the helper installer and
configurator built here.

## Planning basis

- [ProviderAdapters](../architecture/provider-adapters.md) defines the selected classic status-
  line surface, allowed fields, observation-time rule, dropped-window behavior, safe command
  composition, session merge, eight-day pruning, and adapter dependencies.
- [Upstream automatic usage sources](../research/phase-1/upstream-automatic-usage-sources.md)
  distinguishes the classic snake-case input from the unselected early-access function hook and
  defines last-response rather than queryable freshness.
- The [source-calibration runbook](../research/phase-1/source-calibration-spike-runbook.md)
  defines the privacy boundary and owner-run evidence. Task 1 must make its Claude Code half
  independently runnable before a live observation.
- Claude Code's official [status-line documentation](https://code.claude.com/docs/en/statusline)
  defines the strict `statusLine` object, event and cancellation behavior, input fields, and
  optional presentation members. Its
  [settings-precedence documentation](https://code.claude.com/docs/en/settings#settings-precedence)
  makes user settings lower precedence than managed, command-line, and project settings and
  documents the optional `CLAUDE_CONFIG_DIR` relocation.
- [Domain](../architecture/domain.md) defines Claude Code's account-scoped window identity, exact
  standard-window durations, reported/retained behavior, and presentation thresholds.
  [Application](../architecture/application.md) owns ingestion and setup confirmation;
  ProviderAdapters does not reproduce those policies.
- M10 Checkpoint A owns the shared `UsageSource`, `SourceConfigurator`, account-catalog,
  `ConfigurationPreview`, and `ConfigureSources` revisions, now implemented. M11 builds on those
  contracts and reopens only the narrow preview-shape extension in decision 1.
- The M10 Codex code supplies patterns M11 reuses rather than copies: `JSONStructuralPreflight`
  (duplicate-key, 4 KiB string, 32-level nesting checks), the owner-only lock/atomic-write file
  primitives behind `ProviderAccountCatalogStore`, `CodexSchedule`'s backoff ladder, and the
  coalesced-receipt source pattern. Task 2 first moves the neutral primitives into a shared,
  non-Codex-named location inside ProviderAdapters; adapters still never import each other.

## Entry criteria

- [x] The M11 overview and sequence are linked from the phase plan and documentation index and
  reviewed against the binding architecture, current targets, M4/M5 contracts, source research,
  and calibration programs. Evidence: the plan review below and the 2026-10-24 changelog entry.
- [x] The follow-up review closes the stream-forwarding, settings-scope, transaction, decoder,
  watcher, lifecycle, and privacy gaps recorded under [Plan review](#plan-review), and delegated
  validation covers both untracked M11 plan files plus every affected tracked document. Evidence:
  the follow-up result under [Plan validation](#plan-validation) and the 2026-10-24 changelog entry.
- [x] M10 Checkpoint A's shared contracts are implemented on `main` and the M11 plan is rebased
  on them. Evidence: commits `18f5723` to `b8d64bd`, the 2026-10-25 refresh under
  [Plan review](#plan-review), and the narrowed decisions 1 and 6 below.
- [x] The owner answers all [implementation decisions](#implementation-decisions), and the
  answers are recorded in [changelog.md](changelog.md) and the binding docs they affect.
  Evidence: the three 2026-10-25 Owner/Claude changelog entries.
- [x] Record the implementation branch, starting commit, and complete worktree state. Preserve
  the pre-existing M9 and M10 planning edits as separate work. Evidence: branch
  `m11-claude-code-adapter` from `e20c7fe`; `git status --short` was empty (no pre-existing M9 or
  M10 edits). Public versions: Swift 6.4, Xcode 27.1, Claude Code 2.1.310.
- [x] The `test_runner` passes the complete gate on the recorded baseline before production
  implementation begins. Evidence: 2026-10-25 run on `e20c7fe`: project generation, format lint,
  strict SwiftLint, import check, 85 Mac-scheme tests, relay install, 28 Workers Vitest and 31
  Node tests, typecheck, and Wrangler dry run all passed.
- [x] Task 1 adds a Claude Code-only `--mode claude` to the calibration programs (M10 delivered
  `codex` and the Codex-requiring `combined`), passes its offline tests, and retains the runbook's
  owner-presence, clean-approved-revision, temporary-settings, privacy, and exact-cleanup rules. Evidence: `zsh spikes/provider-source-calibration/test.zsh`
  passes (5 Node tests and the Codex-only and Claude-only prepare/cleanup suites); runbook sections
  1, 6, 9, 10, and 11 name `--mode claude`.

## In scope

- A single-pass status-line input pump that preserves the complete stream for an approved existing
  command while capturing at most the approved Reset Radar byte bound, followed by a structurally
  bounded decoder for the public version, session ID, optional cumulative API activity counter,
  and non-spend rate-limit windows only.
- A versioned, owner-only per-session record whose filename is derived from the session ID but
  reveals none of it, plus atomic updates under one fixed cross-process transaction lock that
  preserve observation time on idle redraws without accumulating one lock file per session.
- The `ResetRadarStatusLine` composition root, helper copy/version management, and direct
  execution of one approved existing status-line executable with the identical complete input
  stream.
- A bounded Claude Code settings editor, status-line-only restore record, exact preview/apply
  revision, safe single-executable command parser, synthetic composition check, and conflict-safe
  restore.
- The single Claude Code account row: creating it in the owner-only account catalog when setup
  is confirmed, the smallest-unused global number, alias preservation across reinstall, and the
  `AccountID` stamped on every window and source the adapter emits. Claude Code windows carry no
  provider scope.
- Directory watching, bounded record reads, per-kind multi-session merging, dropped-window
  retention, source-owned pruning, foreground/manual rescans, and no forced Claude Code refresh.
- Typed source outcomes for not configured, helper mismatch, malformed or incompatible records,
  permission denial, and temporary filesystem/watch failures, with redacted diagnostics.
- Synthetic unit and integration fixtures plus the owner-present Claude Code half of source
  calibration. Only sanitized field-shape, transition-count, timing, and verdict evidence enters
  the repository.
- Necessary focused Domain/Application contract changes approved below, their tests, removal of
  the ProviderAdapters and helper scaffolds, and affected active documentation.

## Out of scope

- Codex process discovery, JSON-RPC, profile selection, or 15-minute calibration (P1-M10).
- Mac composition-root lifecycle, launch at login, UI, relay publication, or timer-drift work
  (P1-M12 and M13).
- The early-access Claude Code function-hook API, a private endpoint, browser automation, API-key
  mode, reading Claude Code credentials, or generating a turn to make usage fresher.
- General Claude consumer-product usage, gateway `spend_limit`, token cost, dollar amounts,
  model usage, prompt/response content, project paths, or fixed assumptions about unknown window
  kinds.
- Automatic composition of an existing command with arguments, environment assignments,
  variable expansion beyond a leading owner-home `~/`, redirection, pipes, shell operators, or
  any string that cannot be proved to be one executable path.
- Editing managed, command-line, shared-project, or project-local Claude Code settings; scanning
  projects to discover overrides; or claiming that a user-settings installation overrides a
  higher-precedence `statusLine` value. The owner decision below defines first-version handling of
  a relocated user configuration root.
- A whole-settings backup, persistence of unrelated Claude Code settings, external package
  dependency, new build tool, or relay transmission of real usage.

## Security and privacy invariants

- Read status-line input once. When composition is active, forward every byte to the approved
  child with backpressure even after Reset Radar's capture bound is exceeded; an oversized input
  produces no Reset Radar record. Decode only a complete in-bound capture and only allowlisted
  fields after duplicate-key and structural checks. Never log, echo, diagnose, or include in an
  error the raw input, session ID, usage percentage, reset instant, activity counter, prompt,
  response, project path, or unrelated JSON. The local session record persists only the explicitly
  allowlisted counter and normalized window fields needed for freshness and collection.
- Scope the raw session ID to decoding and digest construction, retain only the approved fixed-
  length key afterward, and write only regular files inside the validated owner-only Reset Radar
  directory. Refuse symlinks, unexpected owners, unsafe modes, incompatible formats, and over-
  limit files. Do not claim that Swift can zero or prove immediate release of immutable string
  storage.
- The helper never uses a shell, network, Keychain, provider authentication file, or relay. An
  approved composed executable receives byte-identical input through a direct `Process` launch;
  recorder failure never substitutes Reset Radar output for the existing command's output.
- Parse the selected Claude Code user-settings file in memory under fixed byte and structural
  bounds, reject duplicate members, preserve every unrelated value and every non-`command`
  member of an accepted `statusLine` object byte-for-byte outside the edited JSON token/range, and
  persist only an absence marker or the prior safely parsed command plus transaction metadata needed
  to restore it. Never copy the whole `statusLine` object or whole settings document to Reset Radar
  storage or diagnostics.
- Preview and apply are revision-bound. A detected settings, helper, or existing-command change
  after preview causes a fresh preview instead of a best-effort overwrite. Reset Radar serializes
  its own transactions, checks immediately before replacement, and verifies afterward; the plan
  does not claim an atomic compare-and-swap against an uncooperative external writer. Unsafe or
  unprovable input changes no setting and creates no restore record.
- `observedAt` advances only when the per-session activity counter increases or normal rate-limit
  windows first appear after that session previously had none. An idle or value-only redraw keeps
  the earlier time; another session's activity cannot freshen it. A backward wall clock leaves the
  record unchanged rather than regressing or fabricating observation time.
- Missing `rate_limits` never erases a session's windows. A missing window remains retained; its
  old observation is unavailable after the last known reset. Unknown normal kinds survive with
  no invented duration; `spend_limit` never enters a record. The source emits the account row's
  `AccountID` and no `AccountScope`; the helper process never learns an `AccountID`.
- All tests and fixtures are synthetic. Only the owner starts signed-in Claude Code, supplies the
  four ordinary calibration turns, makes the 60-minute decision, and completes cleanup before
  sanitized evidence is written.

## Implementation decisions

These are newly exposed M11 choices, not permission to invent behavior. Implementation remains
blocked until the owner answers them. A compatible M10 decision may satisfy the shared items if
it lands first and is explicitly referenced from the M11 implementation record.

1. **Revision-bound setup and restore conflict.** *Owner-approved 2026-10-25: recommendation below.* M10 already supplied the `incompatible` and
   `unsafe` setup states, opaque option and preview-revision identities, and `ConfigureSources`'
   stale-preview rejection. What remains is that `ConfigurationLaunchPreview` is Codex-shaped
   (executable, interpreter, and Codex-only environment keys) and cannot show the exact
   status-line change, and `restore()` has no conflict outcome. Recommend adding to
   `ConfigurationPreview` a second, explicitly display-only status-line detail (selected settings
   scope, helper path, optional existing-executable path, and an add-or-replace change kind) and a
   typed restore-conflict error. These fields are exceptions to diagnostic/evidence redaction and
   are never relayed. Apply must serialize Reset Radar transactions, compare the revision
   immediately before replacement, and verify the result. When an accepted object existed, restore
   only its command and only while the current type and command still equal Reset Radar's installed
   values, preserving later sibling-field edits. When the setting was absent, remove only the exact
   minimal object Reset Radar installed. Every other current value leaves both settings and restore
   record untouched and requests owner resolution. This is optimistic conflict detection, not an
   unimplementable promise of filesystem compare-and-swap against an arbitrary concurrent editor.
2. **Resource bounds and composition validation.** *Owner-approved as proposed 2026-10-25.* Recommend the calibration harness's 1 MiB
   Reset Radar capture ceiling; 4 KiB decoded-key and allowlisted-string ceilings; 128-byte ASCII
   grammars for the public version and unknown window kinds; 32-level nesting; duplicate-member
   rejection; 128 total `rate_limits` members before `spend_limit` is ignored or an invalid entry
   is rejected;
   a 64 KiB session/compose/restore-record ceiling; a 1 MiB settings-file ceiling; a 64 MiB streamed
   executable-identity ceiling; a one-second session-record lock timeout; at most 1,024 recognized
   session records and 4,096 total directory entries visited per scan; and exact numeric parsing
   that rejects precision loss in activity counters, percentages, and Unix seconds. Unknown string
   values remain ignored under the total-input bound rather than becoming an accidental 4 KiB
   compatibility requirement. Recommend a five-second synthetic-command timeout with 64 KiB each
   for captured stdout and stderr; production composition streams the approved command's output
   instead of accumulating it. A legitimate installed payload, setting, directory, or command that
   exceeds a bound returns the bound for review rather than widening it silently.
3. **Private session-key dependency.** *Owner-approved 2026-10-25: recommendation below, CryptoKit included.* The architecture requires a truncated SHA-256 session
   filename but does not choose its length or list the required system framework. Recommend the
   first 128 digest bits encoded as 32 lowercase hexadecimal characters and approval for
   ProviderAdapters to import Apple's CryptoKit. No raw or reversible session identifier is
   retained.
4. **Records without an observation.** *Owner-approved as recommended 2026-10-25.* The eight-day rule covers a record with a newest
   observation but not a session that never receives `rate_limits`. Recommend storing a redacted
   last-invoked time and pruning such source-owned records eight days after that time; once any
   observation exists, prune only from its newest `observedAt` as the architecture already says.
5. **Mixed installed versions.** *Owner-approved as recommended 2026-10-25.* Two open Claude Code sessions can outlive a CLI upgrade and
   produce records with different public versions. Recommend continuing the per-kind freshest
   merge, retaining each window's actual `sourceVersion`, and setting `AccountSource.version` to
   the version on the newest selected observation. Idle invocation under a newer CLI version must
   not restamp an older observation. Exact-time entries that are field-for-field equivalent after
   normalization may collapse; if only report state differs, prefer `reported`; every other value,
   reset, kind, precision, or version conflict is incompatible rather than broken by filename or
   directory order.
6. **Provider test imports.** Resolved by M10: `ResetRadarProviderAdaptersTests` already imports
   `ResetRadarDomain`, `ResetRadarApplication`, and `ResetRadarTestSupport`. No `Package.swift`
   test-target change remains; only the CryptoKit decision above touches the production target's
   imports.
7. **Trusted existing executable.** *Owner-decided 2026-10-25: owner-only files, a stricter
   choice than the recommended user-or-root test.* Automatic composition accepts only a regular
   executable owned by the current user whose resolved path is inside the owner's home directory
   and whose resolved ancestor chain is owned only by the current user or root and is not writable
   by group or other. A system-installed or root-owned executable is refused with setup explained
   as unavailable. Bind preview and synthetic validation to device/inode, owner/mode,
   size/modification metadata, and a streamed SHA-256 content digest; apply revalidates the same
   identity. Runtime revalidates path, type, ownership, and modes but permits a later legitimate
   executable upgrade. Do not trust a path prefix alone.
8. **Settings scope and precedence.** *Owner-approved 2026-10-25: default user file only.* Claude Code can relocate its user root with
   `CLAUDE_CONFIG_DIR`, and managed, command-line, project-local, and shared-project values can all
   override user `statusLine`. Recommend first-version automatic setup for the default
   `~/.claude/settings.json` only, with an exact preview naming that scope. A custom root or higher-
   precedence effective setting that the owner identifies or the configurator can prove remains
   untouched and reports automatic setup unavailable. Because Reset Radar never scans projects or
   starts an interactive session to infer effective settings, the preview must also disclose that
   it cannot prove no higher-precedence override exists. Supporting an owner-selected custom user
   root requires an explicit persisted configuration path and M12/M13 UI, so it must be approved
   rather than inferred from the Mac app's sparse environment.
9. **Source failure, lifecycle, and diagnostics contract.** *Owner-approved 2026-10-25: recommendation below.* Recommend an exhaustive mapping before
   code: not configured, helper absent/mismatched, or no first usable observation to `unavailable`;
   malformed schema/record, legitimate bound violation, or conflicting merge tie to
   `incompatible`; and permission, watcher, or temporary filesystem failure to `sourceOffline`.
   Status-line data cannot prove `signedOut`. Expected operational failures emit one state-only
   result and keep the actor available for bounded revalidation; setup failures wait for a
   configuration change, while watcher-root recovery uses the approved one/two/five/fifteen-
   minute ceiling and foreground/manual refresh may trigger one immediate revalidation. `stop()`
   is terminal, finishes the stream once, and fences every late callback. The table must also name
   safe `AccountSource.version` provenance before the first valid record and add only enum-backed,
   string-free provider diagnostic factories.
10. **Helper failure and exit behavior.** *Owner-decided 2026-10-25: stricter than the recommended
    quiet success when no command is composed.* A Reset Radar recording failure exits nonzero
    without output even when no composed command exists, so Claude Code can surface the failure;
    staleness in the source remains the owner-visible signal. Once a composed child launches,
    preserve its stdout, stderr, and exit status regardless of recorder success. A compose-record,
    trust, launch, or pipe failure before the child can run is quiet but nonzero; cancellation
    terminates and reaps only that child and leaves no orphan.
11. **Claude Code account row lifecycle.** *Owner-approved 2026-10-25: recommendation below.* The catalog allows one Claude Code row, but
    `ProviderAccountCatalogStore` can add, replace, load, and remove only Codex rows, and
    `ConfigureSources.remove`/`restore` are separate confirmed actions. Recommend: a verified
    install creates the row (random `AccountID`, smallest unused number) in the same catalog lock as
    the restore record; reinstalling after a restore reuses the existing row and keeps its number
    and alias; `restore()` reverts the status line, leaves the row, and reports `unavailable`
    until reinstalled; `remove(accountID:)` deletes the row and its windows after confirmation and
    throws a typed error, changing no setting, while a Reset Radar installation is still active, so
    the owner restores first. Replace is not offered for Claude Code (there is one status line).
    The Mac app (M12) reads the `AccountID` from the catalog; the helper never does.
12. **Setup-time Claude Code version discovery.** *Owner-approved 2026-10-25: documentation
    correction, no probe.* Guided setup reads and edits only its approved settings and helper
    artifacts; it does not invoke `claude --version` or otherwise discover the installed Claude
    Code version. The decoder obtains the actual public version from each status-line observation,
    and the recorder and merger preserve that version as observation provenance. Public version
    strings gathered by owner-run milestone tooling remain evidence only and do not create a
    runtime setup contract.

## Completion checklist

- [x] The M11 calibration harness uses Claude Code's documented temporary `refreshInterval`
  trigger for idle observations rather than assuming a terminal resize invokes the status line.
  Its cadence keeps the 65-minute reports bounded, offline tests prove the exact temporary
  settings shape, and the owner runbook uses timer-driven idle and cross-session checks. Evidence:
  `prepare.test.zsh` proves the exact isolated `refreshInterval: 30` settings and cleanup boundary;
  on 2026-10-25 the delegated six-test calibration suite and complete contribution-guide gate
  passed, `git diff --check` passed, and 729 fenced-code-aware relative links were valid. No
  signed-in provider process or external service was accessed.
- [x] The owner-facing M11 Task 7 calibration runbook gives one unambiguous Claude Code-only path from
  prerequisites and clean-revision approval through the three-terminal observation, private
  verification, exact cleanup, sanitized evidence handoff, and post-run close-out. Every command,
  expected safe output, stop condition, permitted deferral, and prohibited evidence field is
  explicit; the documented procedure and offline harness tests pass before the live run begins.
  Evidence: the Task 7 owner route and sections 3 through 6 and 9 through 12 of the
  [source-calibration runbook](../research/phase-1/source-calibration-spike-runbook.md); on
  2026-10-25 the delegated offline suite passed six synthetic tests plus preparation isolation,
  the complete gate passed, `git diff --check` passed, and 727 fenced-code-aware relative links
  were valid. No signed-in provider process or external deployment ran.
- [x] The binding architecture and M11 sequence state that guided setup does not probe the
  installed Claude Code version. Version provenance comes only from each decoded status-line
  observation, so setup has no undefined `claude --version` discovery contract. Evidence: owner
  decision 12, ProviderAdapters guided setup, sequence Tasks 0 and 4, the passing complete gate,
  diff hygiene, and relative-link validation.
- [x] Entry criteria hold with recorded owner decisions, baseline evidence, and no pre-existing
  M9/M10 work attributed to M11. Evidence: the entry criteria above; no M9/M10 work is attributed to M11.
- [x] One status-line input pump forwards complete input byte-for-byte to an approved composed
  child while capturing no more than 1 MiB for Reset Radar. Over-bound input creates no record but
  still reaches the child; only a complete in-bound capture reaches structural and semantic decode.
  Only the public version, session ID, optional cumulative activity counter, and allowlisted
  `rate_limits` fields enter typed intermediates. `spend_limit` and every unrelated field are
  ignored and absent from records and diagnostics. Evidence: `StatusLineHelperTests` (chunk sizes 1 to 4,096, byte-identical child input, over-1 MiB input reaching the child with no record) and the capture-bound test in `StatusLineDecoderTests`.
- [x] Session IDs become only approved digest keys; directories, locks, temporary files, and
  records are owner-only and symlink-safe. Concurrent helper invocations cannot partially write,
  regress the observation time, or lose a newer observation. Evidence: `StatusLineRecorderTests` and `SessionRecordFileTests` (owner-only modes, symlink and mode refusal, held-lock timeout, concurrent writers, digest-only names).
- [x] Five-hour, seven-day, missing/empty, dropped, unknown-kind, malformed, exact-bound, and
  over-bound fixtures prove percentage/reset validation, exact known durations, no invented
  unknown duration, `fractionDigits == 1`, strict identifier grammar, duplicate/nesting/count
  rejection, optional-activity handling, and the approved observation-time rule. Evidence: `StatusLineDecoderTests` (every listed fixture class) and `StatusLineRecorderTests`.
- [x] The catalog store gains Claude Code add/load/remove/state operations that follow decision 11,
  share the Task 2 owner-only primitives, keep the one-row cap, and pass catalog regression tests;
  `ClaudeCodeSource` and `ClaudeCodeConfigurator` use that single `AccountID`, and no window or
  source carries an `AccountScope`. Evidence: `ClaudeCodeCatalogTests`, `ClaudeCodeConfiguratorTests`, and the Codex catalog regression tests, all passing.
- [x] The helper copy is version checked and atomically refreshed at the stable Application
  Support path. The executable target records locally, optionally runs one approved composed
  executable directly with identical input, preserves its visible output and exit behavior, and
  emits no Reset Radar error text or private input. Evidence: `StatusLineHelperInstallerTests` and `StatusLineHelperTests` (version flag, pre-launch refusals, no output of its own).
- [x] Guided setup previews the exact revision-bound status-line change, preserves every
  unrelated setting and non-command `statusLine` member byte-for-byte outside the edited range,
  writes only a status-line restore record before mutation, survives each interrupted transaction
  point, verifies its write, and leaves unsafe or changed configurations untouched. It neither edits
  nor claims precedence over managed, command-line, project-local, or shared-project settings. Evidence: `ClaudeCodeSettingsEditorTests`, `ClaudeCodeConfiguratorTests` (byte preservation, stale preview, managed and relocated-root refusal, interruption points).
- [x] Existing-command parsing accepts only the approved single-path grammar and validates the
  resolved executable and ownership. Arguments, assignments, expansion, shell syntax,
  redirection, non-executable or replaced files, secret-bearing/unparseable strings, timeouts,
  or synthetic output/exit mismatches create no restore record and make no settings change. Evidence: `ExistingStatusLineParserTests`, `ExecutableIdentityTests`, and the synthetic-check tests in `ClaudeCodeConfiguratorTests` (mismatch, timeout, output cap).
- [x] Restore replaces only the prior safe command in an existing object or removes the exact
  minimal object installed over an absent setting. It preserves unrelated and sibling-field edits,
  is idempotent, and follows the approved conflict rule when the current type/command no longer
  matches Reset Radar's installed value. Evidence: `ClaudeCodeConfiguratorRestoreTests` (sibling edits kept, conflict refusal, absent-prior exact-object rule, interrupted install). A second restore reports there is nothing to restore rather than repeating work.
- [x] Directory watching is armed before the initial scan, survives atomic file replacement,
  detects watched-root replacement, and fences callbacks from older watch generations. Events
  coalesce over two seconds, and an event newer than an in-flight enumeration leaves one trailing
  scan; start, foreground, and manual refresh rescan. Scans enforce record and total-entry bounds,
  ignore unrelated files, reject unsafe records, coordinate pruning with the fixed writer lock, and
  never generate a Claude Code turn. Evidence: `DirectoryWatcherTests` (real `DispatchSource`, atomic replacement, renamed root) and `ClaudeCodeSourceTests` (arm before scan, two-second coalescing, generation fencing).
- [x] Multi-session fixtures select each kind's newest observation, keep another session from
  freshening idle data, preserve dropped windows as retained, handle deterministic ties and
  mixed versions by the approved rule, and prune observed and never-observed records correctly. Evidence: `SessionMergerTests` and `SessionReaderPrunerTests`.
- [x] `ClaudeCodeSource` implements the approved exhaustive source-state/revalidation table, emits
  complete reports only from a valid bounded scan, emits typed state-only failures otherwise,
  deduplicates unchanged scans, returns identical receipts to coalesced callers for the actual
  rescan, and terminally stops its watcher/stream without a late publication. A real
  `CollectUsage` integration proves complete replacement, retained missing windows, duplicate
  stream/receipt ingestion idempotence, and failure preservation. Evidence: `ClaudeCodeSourceTests` (failure table, backoff ladder, deferred receipts, terminal stop) and `ClaudeCodeCollectUsageTests` (real `CollectUsage`).
- [x] Privacy tests prove session records contain only the allowed synthetic digest, public
  per-observation source version, invocation/observation metadata, activity counter and first-
  observation marker, and normalized windows. Restore records, diagnostics, thrown errors, helper
  output, and test failures contain no sentinel representing a raw session ID, unrelated setting,
  activity counter, percentage, reset, prompt, response, provider path, or raw payload. The restore
  record may contain only an absence marker or the explicitly approved prior safe command plus
  transaction metadata; an ephemeral owner-facing preview may show the exact approved local
  settings/helper/executable paths but never raw input or usage values. Evidence: recorder and restore-record sentinel tests, decoder error redaction tests, and the helper output tests.
- [x] Owner-present calibration passes four response-linked observations across two isolated
  sessions, at least one activity increase per session, idle redraws that do not advance time,
  cross-session isolation, a 60-minute unchanged idle event, and valid normal-window shapes. A
  missing idle redraw may be deferred only where the runbook permits and is never reported as
  passed. Evidence: the final 2026-10-25 entry in
  [spike-results.md](../research/phase-1/spike-results.md#claude-code-source-calibration--2026-10-25)
  records the passing redacted verifier counts, public `five_hour` and `seven_day` kinds,
  cross-session isolation, and 60-minute result. The earlier terminal-resize attempt remains
  recorded separately as deferred and supplies no pass evidence.
- [x] Calibration cleanup succeeds before one sanitized Claude Code evidence entry is added to
  [spike-results.md](../research/phase-1/spike-results.md). The owner records `60 minutes
  confirmed` or `60 minutes rejected`; no raw or identifying value enters version control.
  Evidence: exact cleanup reported PASS before the final sanitized entry was added, and the owner
  recorded `60 minutes confirmed`. The entry contains only public versions, aggregate counts,
  public window kinds, technical verdicts, the owner decision, and cleanup results.
- [x] The ProviderAdapters and helper scaffolds are removed, active docs match the implementation,
  and P1-M11 moves to `Done` only after every required item has evidence. Evidence: the final
  scaffold/placeholder/TODO/FIXME search found zero source/helper matches; 199 focused
  ProviderAdapters tests, 78 focused Domain tests, and six calibration tests passed; the complete
  gate passed with zero SwiftLint violations across 286 files, 28 Workers tests, 31 relay Node
  tests, TypeScript checks, and Wrangler dry-run; `git diff --check` and 730 fenced-code-aware
  relative links passed on 2026-10-25.
- [x] The root `Makefile` exposes the documented local validation commands through named `.PHONY`
  targets, and its aggregate gate matches the contribution guide.
- [x] The composed-command termination regression uses the launched child's process identifier
  directly and proves termination reaps only that child without output or a filesystem race.
  Evidence: the focused SwiftPM test passed 10 consecutive runs, and the named test passed in the
  macOS Xcode test run.
- [x] `make test` uses built-in quiet modes without hiding failures and passes repeated complete
  macOS and relay test runs without a flaky failure. Evidence: the Codex privacy suite passed 10
  consecutive focused runs, and three consecutive `make test` runs each passed 655 Swift tests,
  both relay suites, and the composed-child termination regression with about 105 output lines.
- [x] The Claude Code timeout, interrupted-restore, and helper-install regressions pass together
  without being failed by the concurrent composed-child termination regression. Evidence: all
  three passed together 10 consecutive times, the complete 655-test Mac suite passed 10
  consecutive times, and the complete contribution-guide gate passed on 2026-10-25.
- [x] `make test` overlaps the independent Mac and relay suites with bounded concurrency, retains
  both suites' native internal scheduling and failure propagation, and demonstrates a repeatable
  wall-clock improvement without reviving the process-launch regressions. Evidence: alternating
  sequential/concurrent runs improved median wall time from 14.40 to 13.43 seconds (6.7%); 10
  consecutive concurrent runs passed all 655 Mac and 31 relay tests with a 12.87-second median;
  the complete contribution-guide gate passed on 2026-10-25.
- [x] Whole-milestone review follow-up keeps setup non-configured until the Claude Code account row
  is durable, preserves recovery artifacts after post-write conflicts, validates every
  interrupted-install artifact before completing it, and binds trusted executable identity to
  stable descriptor and path metadata across hashing. Focused regression tests and the complete
  contribution-guide gate passed on 2026-10-25.
- [x] The `test_runner` passes the complete contribution-guide gate from the final reviewable
  worktree; focused ProviderAdapters/helper tests, `git diff --check`, and relative Markdown
  links also pass. Evidence: the 2026-10-25 review run passed XcodeGen generation, Swift format,
  strict SwiftLint with zero violations across 286 files, import boundaries, the macOS scheme,
  28 Workers tests, 31 relay Node tests, TypeScript checks, Wrangler dry-run, focused Claude Code
  configurator/catalog/settings tests, the complete ProviderAdapters target, diff hygiene, and the
  fenced-code-aware relative-link check.

## Implementation status

All three checkpoints are complete. The `ResetRadarStatusLine` scaffold comment and
ProviderAdapters placeholder are replaced by the tested helper and adapter implementation. The
first owner-present Task 7 attempt stopped safely when the undocumented terminal-resize trigger
produced no idle event; cleanup passed, the result was recorded as deferred, and the harness was
repaired to use Claude Code's documented temporary `refreshInterval`.

The fresh owner run from clean revision `f6c3300` then passed four response-linked observations,
both sessions' idle checks, cross-session isolation, public five-hour and seven-day shapes, and an
A idle observation at least 60 minutes after its last increase. The owner confirmed 60 minutes,
exact cleanup passed, and sanitized evidence was recorded. Final focused tests, the complete gate,
the scaffold search, diff hygiene, and relative-link validation passed on 2026-10-25. P1-M11 is
`Done` and hands the implemented Claude Code source to M12 composition.

## Checkpoints

- **A: Helper and safe setup** (Tasks 0 to 4): decisions, baseline, independent calibration,
  bounded decoder/record format, helper composition, install, settings transaction, and restore.
- **B: Collection and merge** (Tasks 5 and 6): bounded record reads, watcher, merge/prune rules,
  source actor, state mapping, and Application integration.
- **C: Owner calibration and close-out** (Task 7): owner-run signed-in evidence, cleanup, final
  gate, documentation, and M12 handoff.

## Plan review

The 2026-10-24 review traced the milestone against the phase dependency table, Domain and
Application contracts, current Swift package and executable targets, ProviderAdapters
architecture, pinned upstream research, source-calibration programs, and privacy rules. It found
and addressed these plan gaps:

- The maintained calibration programs are tracked in the current history, but the runbook still
  requires a nonexistent exact spike branch. Preparation and verification also require Codex and
  Claude Code together. M11 needs a Claude Code-only mode that does not enumerate profiles, start
  Codex, require `codex-profile`, or wait for a Codex report.
- `ConfigurationPreview` carries only product and generic change type. It cannot present the exact
  settings edit, bind apply to the inspected file revision, or safely arbitrate a later
  `statusLine` restore conflict. The plan exposes one shared Application-contract decision rather
  than hiding mutable state in the adapter.
- The architecture mandates truncated SHA-256 session keys while ProviderAdapters is documented
  as Foundation-only. The digest length and CryptoKit dependency must be approved before code or
  package/docs drift appears incidentally.
- The architecture says input is bounded but supplies no status-input, record, directory-count,
  or synthetic-command bounds. The plan proposes explicit reviewable limits and requires a live
  contradiction to return to the owner.
- Eight-day pruning has no anchor for a session record that never receives its first rate-limit
  observation. Mixed-version records also have no rule for the single summary version carried by `AccountSource`. Both are explicit decisions instead of timestamp or directory-order guesses.
- Atomic replacement prevents torn records but not two helper processes from losing a newer
  update. The initial review required cross-process serialization, strict monotonic activity
  handling, and interrupted-write tests; the follow-up below replaces an unbounded per-session
  lock-file namespace with one fixed record-transaction lock.
- M11 can build the installer, configurator, helper, and source behind injected paths, but M12
  still owns `Bundle.main` lookup and collector lifecycle wiring. The milestone boundary now
  states that seam explicitly.
- The ProviderAdapters test target needs direct inward imports for normalized Domain records and
  real Application integration. The local dependency change is called out for approval.
- The architecture test list said “settings backup” even though the security design forbids a
  whole-settings backup. The wording is corrected to the intended status-line-only restore
  record.

The review originally found no reason to add M9 or M10 as a dependency, adopt the early-access
function-hook API, broaden collection beyond Claude Code coding allowances, or let a manual
refresh create a provider turn. The later M10 owner interview supersedes only the dependency
conclusion: M11 production work now waits for M10 Checkpoint A's shared account contracts. The
other conclusions remain unchanged. Plan validation results are recorded here after the delegated
gate completes.

A follow-up review on 2026-10-24 found and corrected additional execution gaps:

- The bounded reader could not reject an oversized input and also forward the complete original
  bytes to a composed command. The helper now has one streaming pump: child forwarding continues
  with backpressure while Reset Radar abandons an over-bound capture without decoding or writing
  it.
- The decoder incorrectly required `cost.total_api_duration_ms`, although the binding architecture
  says absence after a reading keeps data stale. It now treats activity as optional, rejects an
  invalid present value, and adds exact-number, duplicate-key, nesting, total-member, identifier,
  and precision requirements before semantic decoding.
- One lock file per session would grow without bound or introduce an unsafe unlink race. One fixed
  owner-only transaction lock now coordinates helper writes with pruning while record replacement
  remains atomic.
- The settings plan treated `statusLine` like one command string and ignored its object members,
  user/project/managed precedence, command-line overrides, and `CLAUDE_CONFIG_DIR`. It now changes
  only an accepted object’s `command`, losslessly preserves bytes outside the edited JSON range,
  stores only a safe prior command or absence marker, exposes the supported settings scope as an
  owner decision, and refuses to claim that user settings override higher scopes.
- Revision checking around an atomic rename is not a filesystem compare-and-swap against an
  uncooperative editor. The plan now promises serialization of Reset Radar operations, an immediate
  pre-write revision check, and post-write verification/recovery while exposing the remaining race
  honestly in the owner decision and risk table.
- The privacy checklist prohibited local paths in the exact owner-facing preview that guided setup
  requires, and its session-record allowlist omitted the activity metadata the recorder needs. The
  exceptions and prohibited persistence/diagnostic/evidence paths are now explicit.
- The original start order scanned before registering the directory watcher, allowing a record
  replacement in between to be missed. The watcher now arms before the initial scan, generations
  fence stale callbacks, watched-root replacement triggers revalidation, and coalesced explicit
  callers share one receipt.
- Source-state mapping, retry eligibility, terminal-stop behavior, pre-observation version
  provenance, and quiet helper exit behavior were unspecified. Decisions 9 and 10 make those
  contracts explicit instead of leaving them to incidental implementation.
- Per-window source versions could be restamped by an idle invocation after a CLI upgrade, and
  exact-time ties did not cover report state or all normalized fields. The mixed-version decision
  and merge tests now preserve observation provenance and define every tie outcome.

A refresh review on 2026-10-25, after M10 Checkpoints A and B landed on `main`, compared the plan
with the implemented code and found and corrected these gaps:

- The plan named `ProductSource`, which M10 replaced with account-scoped `AccountSource`; it also
  said no account appears in M11 output. The single Claude Code row, its `AccountID`, and the
  catalog-store operations to create, load, and remove it were never planned. Decision 11 and the
  new scope, checklist, and Task 2 and 4 items close this.
- Decisions 1 and 6 described contracts M10 had since delivered (option and revision identities,
  `incompatible`, `unsafe`, `ConfigureSources` stale-preview rejection, and the provider test
  imports). They are narrowed to the remaining Claude-specific preview shape and restore conflict.
- Task 1 assumed the calibration programs lacked independent modes. M10 added `--mode codex` and a
  `combined` mode that still needs `codex-profile` and Codex; the exact-branch claim is already
  gone. The task now adds a Claude Code-only mode in prepare, verify, cleanup, and the runbook.
- Reusable M10 code (`JSONStructuralPreflight`, owner-only lock and atomic-write primitives, the
  backoff ladder, receipt coalescing) was not referenced, which invited a second incompatible
  implementation. Tasks 2, 5, and 6 now start from those seams.
- Source outcomes ignored the `ReadReceipt.deferred` and `.unavailable` cases and Codex's
  one-state-only-report-per-failed-attempt rule; Task 6 now maps them.

## Plan validation

On 2026-10-24, the `test_runner` ran the complete
[contribution-guide gate](../contribution-guide.md#required-validation) on the shared planning
worktree. Project generation, import checks, the Mac scheme, relay dependency installation, all
24 Workers Vitest tests, TypeScript checking, and the non-deploying Wrangler dry run passed.
`git diff --check` and a fenced-code-aware check of 61 tracked and untracked Markdown files found
no bad relative links. Initial sandbox-only compiler, CoreSimulator, Wrangler-log, and local-
listener restrictions used approved host-access retries where applicable.

That earlier complete-gate attempt was not green, so it supplied no baseline or close-out evidence.
Swift format lint and strict SwiftLint found the same six line-length violations in the pre-existing
concurrent `ResetRadarKit/Tests/ResetRadarTransportTests/ResponseMapperTests.swift`; SwiftLint also
encountered an unrelated sandbox denial while writing a simulator plist. `npm --prefix relay test`
passed its 24
Workers Vitest tests, then failed two concurrent M9 harness tests:
`stateful reader commits only authenticated newer compatible envelopes` and
`all planned client faults preserve the last valid cache`. None of those failures is in the M11
plan files, and this review did not change the concurrent Transport or relay work. No signed-in
provider process, real settings file, helper installation, provider history, Cloudflare state,
secret, or real usage was accessed.

The `test_runner` repeated the complete gate on the enhanced shared worktree on 2026-10-24.
Project generation with XcodeGen 2.46.0, Swift format lint, strict SwiftLint with zero violations
across 198 files, import checks, the Mac scheme's 85 Swift package tests, 40 gateway tests, and Mac
smoke test, relay dependency installation, 24 Workers Vitest tests, 12 Node tests, TypeScript
checking, and the non-deploying Wrangler dry run all passed. Initial sandbox-only cache, log, and
local-listener denials passed on approved host-access retries. `git diff --check`, explicit trailing-
whitespace and carriage-return checks of both untracked M11 files, and a fenced-code-aware check of
686 relative links across 65 Markdown files also passed. No validation file was modified, and no
signed-in provider process, real settings/history, helper installation, Cloudflare mutation,
secret, or real usage was accessed. This validates the enhanced plan; it does not replace the
isolated clean baseline required after the owner answers every implementation decision.

After the documentation-only evidence and consistency refinements, the `test_runner` repeated
`git diff --check`, both untracked M11 whitespace/carriage-return checks, and the fenced-code-aware
relative-link check. All passed across the same 65 Markdown files and 686 relative links.

## Risks

- **Settings loss or surprise.** The file may change between preview, apply, and restore.
  One Reset Radar transaction lock, immediate revision checks, status-line-only records, write-
  before-mutate ordering, post-write verification, and conflict refusal narrow the race. An
  uncooperative external writer cannot participate in an atomic compare-and-swap, so setup must
  disclose that residual race and never claim stronger protection.
- **Settings scope mismatch.** User settings may be relocated or overridden by managed,
  command-line, or project settings. Setup names the exact supported scope, never scans or edits a
  project to force precedence, and reports an override it can prove as unavailable.
- **Existing-command side effects.** Even a syntactically safe user executable can have behavior.
  Setup shows the exact resolved path, requires confirmation, runs only a bounded synthetic check,
  and never adds arguments or a shell.
- **Composition backpressure.** A bounded recorder cannot truncate the input seen by the owner's
  existing command. The single-pass pump forwards every byte with concurrent output draining,
  abandons only Reset Radar's over-bound capture, and terminates/reaps its child on cancellation.
- **Freshness inflation.** Claude Code redraws cached data and concurrent sessions independently.
  Per-session activity state and newest-observation merge prevent redraws or another session from
  advancing an idle session's observation.
- **Local-file substitution.** The helper, settings, compose configuration, and session directory
  are user-writable local assets. Every boundary validates ownership, type, mode, expected path,
  ancestor chain, and preview identity before use; unsafe changes fail closed.
- **Installed-schema drift.** A future Claude Code version may alter status-line fields or trigger
  behavior. Decode additive fields conservatively, reject missing required semantics, and return
  a legitimate calibration contradiction to the owner rather than scraping another source.
- **False privacy confidence.** Synthetic sentinel tests cannot prove every future provider field
  is harmless. Production keeps only allowlisted typed values, avoids raw error descriptions, and
  permits only owner-reviewed sanitized calibration evidence.
