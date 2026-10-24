# P1-M11: Claude Code adapter sequencing

Status: Planned

Work order and acceptance tests for the
[M11 overview](milestone-11-claude-code-adapter-overview.md). Binding behavior remains in
[ProviderAdapters](../architecture/provider-adapters.md); this sequence names implementation
seams, test-first order, checkpoints, and the owner-run calibration boundary.

## Constraints

- Production adapter code stays in
  `ResetRadarKit/Sources/ResetRadarProviderAdapters/ClaudeCode/`, tests in
  `ResetRadarKit/Tests/ResetRadarProviderAdaptersTests/ClaudeCode/`, and the executable entry
  point in `ResetRadarStatusLine/`. Shared fixtures are synthetic and local to provider tests
  unless an existing repository fixture is intentionally reused.
- ProviderAdapters imports only the approved Domain, Application, Foundation, and system-
  framework dependencies. The helper composition root imports Domain and ProviderAdapters. Use
  Swift 6 strict concurrency and Swift Testing; add no external package, script runtime, service,
  or build tool.
- Inject clocks, filesystem roots, process sessions, file metadata, watcher events, and helper
  source/destination paths. Real provider homes and settings are never test fixtures. Small
  integration suites exercise real temporary files, locks, `Process`, and atomic replacement.
- Never copy production logic from the JavaScript calibration harness. It supplies reviewed
  behavioral evidence and synthetic shapes; Swift owns its bounded decoder, record transaction,
  settings editor, parser, runner, watcher, merger, and tests.
- Raw status-line input and settings content never reach logs, diagnostics, assertion messages,
  thrown descriptions, snapshots beyond allowlisted fields, restore storage beyond an absence
  marker or the prior safely parsed status-line command, or checked-in evidence. Fixture sentinels
  make leakage checks deterministic.
- Run focused ProviderAdapters and helper tests while iterating and the complete
  [gate](../contribution-guide.md#required-validation) at the baseline, each checkpoint, and
  close-out. Delegate command execution and first-pass failure analysis to `test_runner`.

## Commit strategy

After the owner resolves the overview decisions, prefer one conventional commit per checkpoint:
helper/setup boundary, source/merge behavior, and calibration close-out. A commit is eligible only
after its complete gate passes. Do not mix the pre-existing M9 or M10 planning work into M11
evidence or commits.

## Task 0: Decisions, branch, and baseline

Record the implementation branch, starting commit, and `git status --short`. Resolve every
overview decision and update the changelog plus affected binding architecture before code uses
the result. If M10 already resolved a compatible configuration-preview, test-dependency, source-
state, or diagnostic choice, cite that decision rather than deciding it twice. Set M11 to `Active`
only when implementation begins.

Add approved direct local test dependencies and the approved CryptoKit architecture dependency.
Record public Swift, Xcode, and Claude Code version strings without executable paths, settings,
session IDs, or account data. Have the `test_runner` execute the complete clean baseline gate.

Done when the overview entry criteria contain concrete evidence and no open decision is embedded
as an implementation assumption.

## Task 1: Make Claude Code calibration independent and runnable

Before any signed-in observation, reconcile the maintained runbook and tracked programs. If M10
has already introduced independent modes, extend and test that interface instead of creating a
second workflow.

1. Replace the stale exact-branch claim with the repository's actual tracked-program arrangement.
   Require the approved clean M11 revision and prove the worktree stays unchanged throughout the
   live run; do not claim the programs exist only on an absent disposable branch.
2. Add an explicit Claude Code-only path through preparation, verifier, cleanup, and evidence. It
   must not inspect Codex profiles, require `codex-profile`, generate Codex launchers/reports,
   start app-server, or wait for Codex polling. Preserve a combined mode only if its behavior
   remains tested and documented.
3. Preserve two generated Claude Code session IDs, isolated empty work directories, temporary
   `--settings` files, exact history/session cleanup, real-settings and repository checksums,
   owner-only randomized `/private/tmp` storage, four owner-entered turns, and the 65-minute wait.
   No live step edits the owner's real Claude Code settings.
4. Keep reports structural: public version type, activity classifications, allowed key names,
   public window kinds, counts, timing, and verdicts only. Actual counters, percentages, resets,
   session IDs, prompts, responses, paths, and unrelated fields remain private and ephemeral.

Offline tests cover mode/argument validation, Claude Code-only tool discovery, missing reports,
cross-label contamination, activity first/increase/unchanged/decrease/absence, idle deferral,
60-minute boundaries, malformed and over-limit inputs, output redaction, wrong revision or dirty-
worktree refusal, settings/history verification, and exact cleanup scope. Run JavaScript and Zsh
syntax checks. A cleanup failure never broadens a path or deletes by wildcard.

If the installed field shapes or activity rule contradict the binding design, stop. Update the
research and return the freshness/source decision to the owner; do not patch production from raw
live output.

## Task 2: Status-line input and versioned session records

Write failing boundary and privacy tests, then implement these pure or injected seams with exact
public names finalized during review:

- `BoundedStatusCapture` accepts chunks from the Task 3 input pump, retains a complete input only
  while its total remains at or below the approved ceiling, and irreversibly abandons the capture
  on the first over-bound byte. It never returns a truncated payload and never controls whether a
  composed child continues receiving bytes.
- Before semantic decoding, an iterative JSON lexical/structural preflight validates UTF-8 and
  JSON tokens, rejects duplicate object members, measures decoded keys and allowlisted string values
  after escape expansion, skips unknown string values under the total-input bound, enforces the
  approved nesting and `rate_limits` member counts, and emits only enum-backed errors. Count every
  member before ignoring `spend_limit` or rejecting an invalid normal window, so empty or ignored
  entries cannot evade the bound.
- `StatusLineDecoder` requires one JSON object and decodes only a bounded public `version`,
  nonempty `session_id`, optional exact finite nonnegative `cost.total_api_duration_ms`, and the
  bounded `rate_limits` object. Present malformed activity fails the invocation; absent activity
  remains absent for the recorder's stale-data rule. Version and window kinds must satisfy the
  approved printable grammars so arbitrary raw strings cannot cross into records or publication.
  Every unrelated key is ignored without reflecting its key or value in an error.
- `SessionKey` scopes the raw session ID to one digest construction and retains only the approved
  digest/encoding afterward. Its description and errors never reveal source text or the digest
  input; it makes no unprovable memory-zeroing or immediate-release claim.
- `SessionRecordFile` defines an explicit schema version, strict keys, owner-only permissions,
  bounded canonical encoding, a validated directory, one stable cross-process transaction lock,
  a bounded acquisition timeout, and atomic replacement. It stores only the digest key, approved
  invocation/retention timestamps, prior activity counter, whether a normal window has appeared,
  and normalized non-spend windows with each observation's actual public Claude Code version.
- `StatusLineRecorder` performs one locked read-modify-write. An increased activity counter or the
  first normal-window appearance in a session advances observation time for currently present
  valid windows; unchanged or absent activity and value/reset-only changes retain the earlier
  time and source version. A decrease or invalid present counter fails without regressing state.
  An injected wall time earlier than the record's last invocation or any retained observation also
  leaves the record byte-for-byte unchanged; the helper neither regresses nor fabricates a clock.
  Missing `rate_limits` retains prior entries; missing kinds become `retained`; a newly appearing
  kind without an observation signal is not added until a later valid signal can timestamp it.
  Any malformed non-spend candidate rejects the whole invocation rather than partially mutating a
  session record.

Map exact `five_hour` and `seven_day` kinds to 300 and 10,080 minutes. Preserve unknown valid
bounded normal kinds with no duration. Mark all accepted Claude Code account-level windows
default, keep provider-reported percentage used with at most one decimal place and presentation
metadata `fractionDigits == 1`, and accept only integral Unix seconds in the documented numeric
range for `resets_at`; an absent reset stays nil. Never infer a percentage, reset, duration,
account scope, or provider state. Ignore `spend_limit` completely after counting its member.

Fixtures cover no prior file; first appearance; absent/empty limits before and after a reading;
activity absence before/after a reading, increase, equality, decrease, invalid type, exact numeric
precision, and overflow; value/reset-only changes; a new kind without a response signal; dropped
and reappearing windows; known and safe/unsafe unknown kinds; spend limit alone and mixed;
missing, integer, one-decimal, over-precise, negative, NaN/infinite, 0/100, and over-100 percentage;
missing/malformed/fractional/expired reset; missing/empty/overlong/unsafe version and session ID;
duplicate JSON keys at every relevant depth; exact/over input, decoded-key/allowlisted-string,
nesting, record, total-member, and window bounds; an overlong ignored string that remains ignored;
escaped Unicode growth; invalid UTF-8/JSON; unsafe owner/mode/type/
symlink; incompatible record versions; fixed-lock contention; stale temporary files; write
interruption; equal and backward clocks; and two concurrent writers where an older update finishes
last. Privacy assertions prove an over-bound, malformed, or clock-regressed invocation leaves the
prior record byte-for-byte unchanged.

## Task 3: Helper composition root and stable installation

Implement `StatusLineHelperMain` in ProviderAdapters and make
`ResetRadarStatusLine/main.swift` only wire standard streams, the real clock/filesystem, and the
optional compose configuration. It validates any compose record and executable before consuming
standard input, launches the approved child if present, then uses one `StatusLineInputPump` to read
chunks exactly once. The pump concurrently drains child stdout/stderr, forwards every input byte
to child stdin with backpressure, and offers the same chunks to `BoundedStatusCapture`. At EOF it
closes child stdin; an abandoned over-bound capture is never decoded or recorded. A normal
invocation follows the approved exit decision:

- with no approved original command, drains input, writes no output, and exits successfully even
  when Reset Radar recording fails;
- with a compose record, launches only the stored resolved executable directly, sends the exact
  same complete input bytes to stdin even when Reset Radar's capture overflows, streams its stdout/
  stderr to the matching helper streams, and preserves its exit status; and
- if recording fails, never prints Reset Radar details and still preserves an approved original
  command's behavior. A pre-launch compose/trust/pipe failure is quiet and nonzero; source
  staleness exposes the missing update.

`ComposedCommandRunner` never invokes a shell, adds an argument, or accumulates output. It
revalidates that the compose record and current executable still satisfy the approved absolute-
path, type, ownership, mode, and trust policy before launch, and forwards the invocation
environment without persisting or logging it. Its three pipe pumps cannot deadlock when the child
writes before reading or closes one stream early. Stop, a broken pipe, or Claude Code cancelling an
in-flight status line closes stdin, terminates and reaps only the child it created, and fences every
late callback without hanging or printing Reset Radar text.

Implement `StatusLineHelperInstaller` behind injected URLs. It validates the embedded helper,
destination hierarchy, ownership, modes, regular-file type, content identity, and baked public
version without executing an untrusted destination. It creates only missing Reset Radar-owned
directories with owner-only modes, copies to a same-directory temporary file, sets the approved
executable mode, atomically replaces the stable
`~/Library/Application Support/ResetRadar/bin/reset-radar-statusline` path; and verifies the
installed version. It never follows an unexpected symlink or deletes a broad directory. M12 will
provide the embedded bundle URL and invoke refresh during app lifecycle composition.

Tests run the real helper against synthetic stdin with and without a fake composed executable,
split input at every relevant boundary, compare byte-identical forwarding for in-bound and over-
bound payloads, stream large interleaved stdout/stderr while the child delays reading stdin, and
cover exit success/failure, early pipe close, missing/replaced executable, recorder failure,
synthetic-check timeout versus production cancellation, space-containing paths, abrupt helper
termination, orphan prevention, interrupted installs, version match/mismatch, permissions,
symlinks, and sentinel redaction. They prove helper output is exactly the original command's output
or empty and that an oversized composed input creates no session record without truncating what
the original command receives.

## Task 4: Safe settings transaction, preview, and restore

Implement these setup seams after the approved generic Application preview contract is available:

- `ExistingStatusLineParser` accepts exactly one absolute executable path, optionally quoted for
  spaces, or one unquoted `~/` path containing no whitespace. It performs owner-home expansion
  itself and rejects a quoted tilde, arguments, assignments, other expansion, escapes outside the
  approved grammar, redirection, pipes, operators, control characters, and trailing text without
  invoking a shell. This matches shell tilde-expansion semantics instead of accepting a quoted
  `~/` spelling that Claude Code's shell would treat literally.
- `ExecutableIdentityValidator` resolves the path and ancestor chain without trusting a prefix,
  requires the approved regular-file ownership and modes, streams a content digest, and captures
  the approved identity needed to detect substitution between preview, synthetic validation, and
  apply. The persistent compose record remains the resolved executable path required by the
  architecture; runtime revalidates that current path rather than freezing a user-owned executable
  against legitimate upgrades.
- `ClaudeCodeSettingsEditor` operates only on the approved user-settings scope. It reads the file
  under the approved byte and structural bounds without exporting it; rejects duplicate members;
  validates the top-level object and an absent value or an object whose `type` is exactly
  `command` and whose `command` is one string; and uses a bounded lossless JSON token/range editor
  so every byte outside the inserted/replaced `statusLine` range survives, including number lexemes,
  member order, whitespace, all top-level siblings, and accepted non-`command` members such as
  `padding`, `refreshInterval`, or `hideVimModeIndicator`. It requires a regular current-user-owned
  file and validated ancestor chain, rejects group/other write access, preserves an existing safe
  mode, uses owner-only mode for a new file, computes an opaque revision over the original bytes,
  and performs optimistic replacement under one dedicated fixed settings-transaction lock with
  immediate pre-write and post-write verification.
- `StatusLineRestoreStore` writes only a schema version, prior-setting absence or safely parsed
  prior command, exact installed type/command, revision/transaction metadata, and timestamp with
  owner-only permissions. It never copies sibling fields or the settings object. It writes before
  the settings mutation, supports idempotent crash recovery, and never overwrites the original
  prior command with Reset Radar's own command.
- `ClaudeCodeConfigurator: SourceConfigurator` inspects, previews, validates, applies, and restores
  through those seams. It reports rather than editing a custom/higher-precedence configuration the
  owner identifies or it can prove, discloses that it cannot establish the absence of project,
  command-line, or managed overrides without forbidden discovery, and probes the public Claude Code
  version under fixed time/output bounds, but never starts an interactive session or reads provider
  state.

For an absent status line, preview creation of `{ "type": "command", "command": <quoted stable
helper> }`. For an accepted object, preview replacement of only `statusLine.command`, keeping every
sibling member, and show the exact selected settings/helper/existing-executable paths through the
approved display-only fields. Disclose that confirmation will run a bounded synthetic equivalence
check and that an uncooperative external editor cannot join Reset Radar's optimistic transaction.
After confirmation, `apply` creates an isolated temporary compose record, runs the original alone
and the complete helper path on one synthetic payload, and requires exact approved visible-output/
exit equivalence before any persistent write. The test must not touch the production session
directory, compose record, or restore store. Both executions receive the same bounded environment,
working directory, and input, and the preview states the unavoidable twice-run side effect.

Apply revalidates the helper, settings revision, existing executable identity, and exact preview;
writes the restore record; atomically writes the compose record if needed; then atomically changes
only `statusLine.command` for an accepted existing object or creates the minimal object when absent.
It verifies the installed bytes after replacement. Define and test recovery at every interruption
point so a retry either completes the same transaction or safely restores the prior value. A post-
write revision mismatch preserves the restore record and reports a conflict instead of claiming
success. Restore follows the approved conflict rule and removes only Reset Radar's compose/restore
artifacts after the prior command or absence is durable. For a prior existing object, it requires
the current type/command to remain Reset Radar's exact installed values and restores only `command`,
preserving sibling edits. For a prior absent setting, it removes only the exact minimal object Reset
Radar installed; any added member is a conflict.

Tests cover absent/malformed/oversized/deep/duplicate-key settings; exact `statusLine` object shape;
byte preservation outside the edited range, including large numeric lexemes, whitespace, member
order, optional and unknown sibling members, unrelated nested values, and later unrelated
edits; default versus relocated user roots, each provable precedence refusal, and disclosure when
absence of an override cannot be proved; missing or safe existing commands; absolute quotes/spaces,
unquoted `~/`, and quoted-tilde refusal; every refused syntax class; user/root ownership and every
ancestor mode; non-executable, wrong-owner, group/world-writable, symlink/replaced/content-changed
files; exact/over executable identity bounds; helper mismatch; stale preview; settings changes to
another safe or unsafe command; a
simulated external edit before the immediate pre-write check and after replacement; synthetic
timeout, output cap, stdout/stderr/exit mismatch, and side-effect isolation; install, idempotent
reapply, every crash point, post-write verification failure, restore, missing/corrupt/orphan
records, and a post-install user status-line edit. Unsafe cases make no settings, compose, or
restore write.

**Checkpoint A:** Tasks 0 to 4 pass focused package/helper tests and the complete gate, are
reviewed, and are committed before session collection begins.

## Task 5: Bounded record reads, merging, and pruning

Implement `SessionRecordReader`, `SessionMerger`, and `SessionPruner` over the approved record
format. The reader streams directory enumeration without first materializing every name, stops at
the approved total-entry work bound, accepts at most the approved number of exact record names,
applies per-file caps before decode, refuses links and unsafe metadata, and returns typed per-file
outcomes without raw names or payloads in errors. One malformed, incompatible, unsafe, or over-
bound recognized record makes that physical scan state-only; unrelated non-record entries are
ignored only while total enumeration remains in bound.

`SessionMerger` selects each limit kind's newest observation across sessions. Preserve its actual
source version and report state. A newer reported value replaces an older retained value; a
missing kind in one session cannot erase a newer value from another. Exact-time conflicts follow
the approved full-normalized-value rule rather than filename, enumeration, or locale order. Idle
invocations under a newer CLI never restamp the selected observation. The product summary version
follows the approved mixed-version decision, and state-only results use only the approved safe
pre-observation version provenance.

`SessionPruner` deletes only regular files with an exact generated name inside the already
validated session directory and never uses a wildcard or follows a link. It takes the same fixed
transaction lock as the recorder, reopens and revalidates a candidate after locking, then applies
the existing eight-day observation rule and the approved never-observed rule. A concurrent fresh
write therefore cannot be deleted from stale enumeration metadata. A deletion failure is a
redacted temporary failure and cannot broaden cleanup.

Tests cover one and two sessions, independent kinds, active versus idle sessions, another
session's activity, dropped/retained/reappearing windows, exact observation ties, conflicting
ties across every normalized field, reported/retained ties, mixed versions and an idle post-upgrade
invocation, enumeration order, corrupt/incompatible/unsafe siblings, exact and over recognized-
record and total-entry counts, streaming enumeration, eight-day boundaries for observed and never-
observed records, clock skew, writer-versus-pruner races, partial prune failure, and a malicious
unrelated file that is never read or deleted.

## Task 6: Directory watcher, source actor, and Application integration

Implement `SessionDirectoryWatcher` against an injectable watcher session and
`ClaudeCodeSource: UsageSource` as the actor owning watcher lifecycle, coalescing task, rescan gate,
latest successful projection, watch generation, revalidation backoff, and update stream. Implement
the approved source-state/retry/diagnostic table exhaustively before wiring branches ad hoc.

- `start()` is idempotent while running. It validates/creates the owner-only directory, arms a
  directory watch, records its generation, and only then performs the initial complete scan so no
  replacement can land between scan and subscription. An event during that scan leaves one
  trailing coalesced scan. Expected operational failures emit one state-only result and keep the
  runtime available for approved revalidation instead of escaping `start()` and silently removing
  collection. After terminal `stop()`, a later `start()` fails deterministically without creating
  a watcher.
- Watch events coalesce over two seconds into one scan. Foreground and `refresh()` request an
  immediate scan, coalesced with one already in flight; they never launch Claude Code or alter
  its settings. An event received after a physical scan started leaves one trailing coalesced scan;
  the older enumeration cannot satisfy a newer filesystem change.
- Watched-root rename, deletion, replacement, or descriptor failure invalidates that watch
  generation. The source closes it, revalidates the configured path and metadata under the
  approved backoff, arms a new generation before rescanning, and prevents every callback from the
  old generation from publishing.
- A valid scan with at least one usable normal window emits one complete reporting snapshot. An
  unchanged projection emits nothing. No usable first reading yields the approved unavailable
  state-only result; malformed/unsafe/incompatible records and watcher/filesystem failures map to
  the approved redacted source state without erasing Application-owned windows.
- `refresh()` returns times around the actual coalesced rescan and succeeds only when that scan
  produces a valid complete projection. It returns the exact report even when unchanged and no
  stream event is needed. Every explicit caller coalesced into one physical scan receives the same
  receipt, and that scan produces at most one stream event.
- `stop()` is idempotent, cancels watcher/coalescing/scan work, finishes the update stream once,
  fences the active generation, and prevents a late enumeration, backoff, or callback from
  publishing.

Use injected time and watcher events to test the arm-versus-initial-scan race, an event during the
initial scan, exact coalescing edges, event storms, atomic record rename, watched-root replacement,
generation fencing, an event newer than an in-flight enumeration, backoff boundaries, simultaneous
start/foreground/manual events, identical coalesced receipts, cancellation, terminal restart
refusal, no scan or publication after stop,
unchanged receipt versus stream suppression, every failure-table row, recovery after failure, and
stream termination. Run `CollectUsage` with an in-memory store to prove valid reports replace
Claude Code windows, missing kinds are retained, state-only failures preserve windows and
observation times, duplicate receipt/stream ingestion is idempotent, expired retained Home windows
become unavailable, and no account scope or relay operation appears.

**Checkpoint B:** Tasks 5 and 6, focused ProviderAdapters tests, Application regressions, helper
tests, and the complete gate pass and are committed.

## Task 7: Owner calibration and close-out

After Checkpoint B is reviewable, the owner follows the repaired Claude Code-only runbook on the
owner's Mac. The agent may prepare and review commands but never types a prompt, handles raw
reports, changes the real settings, starts a signed-in Claude Code process, or receives raw output.

The owner runs two isolated temporary-settings sessions, enters exactly four ordinary turns,
performs idle redraw checks in both, proves B activity cannot make idle A fresh, and records an A
unchanged idle event at least 60 minutes after its last increase. The verifier requires valid
public version/window shapes, two response-linked observations per session, at least one activity
increase per session, no decrease/invalid transition, idle non-advancement, cross-session
isolation, privacy shape, and cleanup readiness. A missing optional redraw is deferred only as the
runbook permits; a required response event or the 60-minute event cannot be fabricated.

The owner records `60 minutes confirmed` or `60 minutes rejected`. A rejection, activity-rule
contradiction, legitimate bound violation, missing normal window shape, settings/history mismatch,
or cleanup failure stops close-out and returns the relevant rule to the owner. Do not widen a
bound, send another unplanned turn, read credentials, dump JSON, adopt the early-access hook, or
substitute a private endpoint.

After exact verified cleanup, append one sanitized Claude Code calibration entry to
[spike-results.md](../research/phase-1/spike-results.md). If the owner confirms 60 minutes, remove
candidate wording for Claude Code in `CurrentDataWindow` and affected docs without claiming that
Codex's window is confirmed if M10 remains open.

Remove the ProviderAdapters and helper scaffold symbols, search for them and forbidden fixture
sentinels, update the overview checklist, phase plan, docs index, architecture, research, and
changelog. Have the `test_runner` run focused tests and the complete gate. Inspect
`git diff --stat`, the complete diff, `git diff --check`, and tracked relative Markdown links.
Mark M11 `Done` only when every non-deferred required item has direct evidence.

## Review focus

1. One input stream is pumped once. A composed child receives every byte with backpressure while
   Reset Radar decodes only a complete in-bound capture; overflow abandons recording rather than
   truncating the owner's command. Only the approved local session-record fields may retain the
   counter and normalized usage/reset values; no raw field, unrelated setting, identifier, or
   allowlisted value leaks through output, errors, diagnostics, tests, or evidence.
2. Observation time advances only from the approved per-session signals. Idle redraws, value-only
   changes, directory events, rescans, and another session's activity cannot freshen data.
3. Preview, apply, compose validation, and restore are revision-bound Reset Radar transactions.
   They preserve the accepted `statusLine` object's sibling members, disclose the exact supported
   scope and residual external-writer race, and never claim precedence over or edit project,
   command-line, or managed settings.
4. The helper launches at most one proven executable directly, preserves its output/exit behavior
   even when recording fails, and never turns a command string into shell code.
5. The fixed transaction lock, record reads, merge, and pruning are bounded and deterministic
   across concurrent processes, atomic replacements, dropped windows, corrupt siblings, exact
   ties, and upgrades without an ever-growing lock-file namespace.
6. Watch subscription precedes the initial scan, generations fence stale root callbacks, and the
   exhaustive source-state/revalidation table makes failures state-only while preserving
   Application-owned windows. A complete bounded scan alone changes Claude Code windows, and
   manual refresh never creates a provider turn.
7. Live calibration is temporary-settings, owner-run, structural, sanitized, and fully cleaned.
   It proves the installed version observed that day, not future compatibility or the Swift
   implementation itself.
8. M11 remains a local adapter milestone: no Cloudflare request, relay secret, real publication,
   Codex process/profile, Mac lifecycle wiring, or general Claude consumer usage enters its
   acceptance evidence.
