# Provider source-calibration spike runbook

Status: Active

This owner-run procedure validates the installed, signed-in Codex app-server, Claude Code status
line, or both. It uses reviewed tracked programs from an
owner-approved clean revision and retains only privacy-safe structural and timing evidence. The
P1-M11 route below is Claude Code-only; it does not inspect or start Codex.

## 1. Authority, scope, and revision

Run this procedure only on the owner's Mac, with the owner present. It uses the owner's existing first-party sign-ins but never reads a provider authentication file or Keychain item directly. It does not connect to the Reset Radar relay, modify a real provider setting, install a dependency, or send provider data to Reset Radar infrastructure.

The executable calibration programs are tracked in the repository. Before the run, the owner and
reviewer choose the exact commit to calibrate. Record its public commit hash in the private
worksheet, then require that exact clean revision throughout preparation and cleanup:

```zsh
git rev-parse HEAD
git status --short
```

The first command must equal the owner-approved revision and the second must print nothing. The
scripts reject a different revision or dirty worktree and cleanup proves both remain unchanged.
M10 uses `--mode codex`; this mode does not inspect Claude settings or history, require the
`claude` executable, create Claude session identifiers or files, wait for Claude observations, or
delete Claude data. `--mode combined` still requires Codex profiles. `--mode claude` is the
Claude Code-only mode for P1-M11: it takes no profile count, never inspects Codex profiles,
requires neither `codex-profile` nor a Codex report, and creates no Codex launcher, report, or
state.

### P1-M11 Task 7 owner route

Budget about 75 to 90 minutes with the owner present. Most of that time is the required 65-minute
idle interval. Use Terminal.app or another ordinary shell terminal, not a terminal pane inside
Claude Code. The owner performs the live provider actions; an agent may prepare or review commands
but must not start Claude Code, type a prompt, inspect a raw report, or receive private output.

Follow this exact route for M11:

1. Read sections 3 and 4, close screen sharing and terminal recording, choose a private worksheet,
   and close every Claude Code process.
2. Choose one reviewed commit. Confirm that `git rev-parse HEAD` equals it and that
   `git status --short` prints nothing.
3. Run the offline test in section 5. Stop if it does not pass.
4. Run the Claude Code-only preparation in section 6.1. Record only the printed public macOS,
   Node.js, and Claude Code versions; never record the disposable path.
5. Open exactly three ordinary terminals and perform sections 9.1 through 9.5 in order. Submit
   exactly four ordinary, non-sensitive turns: A twice and B twice. Send no fifth turn.
6. Exit both Claude Code sessions and stop Observer exactly as section 9.6 says.
7. Run the Claude Code verifier in section 10. Copy only its redacted JSON summary into the
   private worksheet and make the explicit `60 minutes confirmed` or `60 minutes rejected`
   decision.
8. Close every Claude Code process and run the exact Claude Code cleanup in section 11. Do not
   edit repository evidence until cleanup reports success.
9. Give the agent only the sanitized handoff listed in section 12. The agent records the evidence,
   applies a confirmed or rejected decision, runs the post-run gate, and closes M11 only if every
   required criterion passed.

Sections 7 and 8 are Codex-only and do not apply to M11. A failed or deferred required M11 check
is still useful evidence, but it does not complete M11 and must never be relabeled as a pass.

The spike files are:

| File | Responsibility |
|---|---|
| [`codex-calibration.mjs`](../../../spikes/provider-source-calibration/codex-calibration.mjs) | Bounded JSON-RPC client, sanitized Codex shape/timing report, default-bucket proof, polling, notification refetch, and clean shutdown check |
| [`claude-recorder.mjs`](../../../spikes/provider-source-calibration/claude-recorder.mjs) | Bounded status-line decoder and per-session activity classification with no raw-value persistence |
| [`prepare.zsh`](../../../spikes/provider-source-calibration/prepare.zsh) | Exact-revision and clean-worktree gate, hidden `codex-profile` selection, isolated per-profile launchers and reports, mode-specific disposable state, and cleanup baselines |
| [`preflight-codex.zsh`](../../../spikes/provider-source-calibration/preflight-codex.zsh) | Per-profile installed-version Codex schema validation and harness syntax checks without reading account usage |
| [`verify-reports.mjs`](../../../spikes/provider-source-calibration/verify-reports.mjs) | Mode-specific technical pass/fail checks and a redacted summary |
| [`cleanup.zsh`](../../../spikes/provider-source-calibration/cleanup.zsh) | Revision/repository non-modification checks, exact mode-specific cleanup, and disposable-directory removal |
| [`test.zsh`](../../../spikes/provider-source-calibration/test.zsh) | Offline synthetic tests; it never starts real Codex or Claude Code |

## 2. What the procedure does and does not prove

The Codex half, once for every profile the owner explicitly selects:

1. Generates protocol schemas from the exact installed Codex executable.
2. Starts `codex-profile cli PROFILE app-server --listen stdio://` from the disposable directory, with analytics disabled and a minimal environment. `codex-profile` validates the named profile and supplies its `CODEX_HOME`; the harness never uses an ambient profile or workspace binding.
3. Initializes JSON-RPC, calls structured `account/read` with `refreshToken: false` and retains
   only the approved sign-in discriminators, then calls `account/rateLimits/read` and retains only
   account-identifier presence/type through the signed-in first-party process.
4. Performs one initial read and six five-minute polls over 30 minutes.
5. Observes `account/rateLimits/updated` during one owner-initiated Codex turn and refetches no more than once per minute.
6. Measures only frame size, structural limits, latency, field presence/types, and the structural correspondence of the compatibility bucket.

The Claude Code half cannot actively query usage. It temporarily overrides `statusLine` only for
two command-line processes, then observes the status-line payload after owner-submitted turns. The
temporary settings use Claude Code's documented `refreshInterval` with a 30-second cadence so
idle observations do not depend on an undocumented terminal-resize trigger. It validates whether
`cost.total_api_duration_ms` increases after a response and stays unchanged on timer-driven idle
reruns. It never generates a turn itself.

This validates the installed versions and the proposed source rules. M10 requires both approved
Codex profiles because the first version tracks up to two accounts concurrently. The procedure
does not prove compatibility with a future release, the production adapter implementation,
source installation/restore behavior, relay publication, mobile ingestion, or UI behavior.

## 3. Privacy boundary and stop conditions

Close screen sharing and terminal recording. Do not enable shell tracing (`set -x`). Do not copy provider output into a worksheet, issue, commit, message, or screenshot.

The live harness may hold one raw source message in memory while classifying it. Its reports may contain only:

- UTC event time and elapsed milliseconds;
- message byte counts, latency, maximum decoded key/string UTF-8 bytes, nesting depth,
  multi-bucket entry count, and decoded candidate-window count;
- field names, JSON value types, presence, validity, account-identifier presence/type (never its
  value), approved account-kind/authentication discriminators, and timestamp plausibility classes;
- `unique`, `compatibility-only`, `not-found`, or `ambiguous` as the Codex default-bucket result;
- `300`, `10080`, `other`, `absent`, or `invalid` as the coarse duration class of each decoded Codex window (an exact value outside the two standard durations is never recorded);
- `absent`, `first-observed`, `increased`, `unchanged`, `decreased`, or `invalid` as the Claude activity result;
- the public Claude Code window kinds and the owner's accept/reject decision for each freshness candidate.

The reports and project evidence must not retain an actual percentage, reset instant, duration reported by a rate-limit window, bucket key, limit ID/name, plan, balance, account/session identifier, `codex-profile` name or home, prompt, response content, credential, provider-reported path, or raw message. The spike adds profile names only to process memory and the private disposable launchers until cleanup; it does not alter `codex-profile`'s own existing configuration.

The disposable per-label Claude state file temporarily stores only the prior numeric `total_api_duration_ms` counter, invocation count, and whether a normal rate-limit window was previously present. The recorder needs that counter to classify the next invocation as increased, unchanged, or decreased. It is never printed or copied into evidence and section 11 permanently removes it.

The preparation script assigns explicit disposable Claude session UUIDs and separate empty working directories. Cleanup restores the pre-run `~/.claude/history.jsonl` prefix byte-for-byte, deletes UUID-matching entries only from Claude Code's `~/.claude/projects`, `~/.claude/session-env`, and `~/.claude/tasks` session stores, scans all of `~/.claude` for remaining UUID references, verifies the real Claude settings checksum, and verifies that the repository status did not change during the live run.

Stop and record a failure or deferral if:

- the checkout is not the exact owner-approved revision or the worktree is dirty;
- `codex-profile` is unavailable, a requested profile is uninitialized, a profile is selected twice, or any owner-intended profile is omitted;
- synthetic tests or installed-schema preflight fail;
- any command would require copying a credential or raw provider response;
- a legitimate Codex frame exceeds 1 MiB, a decoded key/string exceeds 4 KiB of UTF-8, nesting
  exceeds 32 levels, more than 128 multi-bucket entries appear, or more than 128 candidate
  windows are decoded;
- `account/read` is absent or does not prove a supported ChatGPT account with a boolean
  `requiresOpenaiAuth`, or the rate-limit response lacks a nonempty string account identifier;
- a multi-bucket Codex response cannot map the compatibility bucket to exactly one peer;
- a normal Codex read exceeds the 10-second timeout or the app-server does not exit within five seconds of stdin closing;
- Claude Code does not show the temporary Reset Radar status line before the first turn;
- Claude activity is absent after a response, decreases, fails to increase after an observed response, or increases during an idle rerun;
- a workspace-trust prompt or unexpected hook, plugin, tool, or command appears;
- another Claude Code process was open during preparation or cleanup;
- the Claude history prefix, real settings checksum, or repository-status checksum changed unexpectedly;
- the owner does not want to spend the normal allowance for the manual Codex and Claude Code turns.

Never respond to a failure by reading credentials, calling a private usage endpoint, dumping raw JSON, increasing a safety bound, fabricating an observation, or choosing a replacement freshness threshold. Return those decisions to the owner.

## 4. Private worksheet

Keep a private worksheet outside the repository. Record only:

| Area | Permitted record |
|---|---|
| Attendance | UTC date and `owner-present` |
| Environment | macOS, Node.js, installed Codex version, installed Claude Code version |
| Codex | Number of explicitly selected profiles; for each private ordinal only, schema preflight, account-identifier presence/type, approved sign-in shape, read count, latency range, frame/string-byte/depth/bucket-entry/candidate-window maxima, default-bucket result/basis, notification/refetch observed or deferred, child shutdown, and 15-minute decision |
| Claude Code | Public field/window shape; counts of first/increased/unchanged classifications; two-session isolation; 60-minute observation; 60-minute decision |
| Privacy | Settings unchanged; repository unchanged; history restored; UUID scan clear; disposable directory removed |
| Result | Pass, fail, or deferred for each provider, with the failed criterion but no raw value |

Do not put the disposable path, executable path, two session UUIDs, prompts, responses, usage values, resets, or raw reports in the worksheet.

## 5. Run offline tests first

From the repository root:

```zsh
set +x
zsh spikes/provider-source-calibration/test.zsh
```

This syntax-checks every script, exercises the Codex and Claude recorders only with generated synthetic messages, and uses a fake two-profile `codex-profile` command to prove ordinal isolation without reading either real profile. It must pass before any signed-in tool runs.

## 6. Prepare the live run

Save and commit the reviewed implementation first. Preparation refuses a dirty worktree, a commit
other than the approved revision, or a running Claude Code process.

### 6.1 Claude Code-only preparation for P1-M11

From the repository root, keep the approved commit hash in memory and run:

```zsh
approved_revision="$(git rev-parse HEAD)"
test -z "$(git status --short)" || exit 1
zsh spikes/provider-source-calibration/prepare.zsh \
  --mode claude \
  --expected-revision "$approved_revision"
```

The script prompts for nothing. It prints public macOS, Node.js, and Claude Code versions, then a
private disposable directory and a quoted `source` command. Record only the three public versions
and approved commit in the private worksheet. Do not record or send the directory or `source`
command. Paste the printed `source` command into the current terminal, then confirm the attached
state without printing identifiers:

```zsh
case "$source_calibration_root" in
  /private/tmp/reset-radar-source-calibration.*) ;;
  *) printf 'Unexpected calibration root. Stop.\n' >&2; exit 1 ;;
esac
test -f "$source_calibration_root/session.zsh"
test "$source_calibration_mode" = claude
printf 'Claude calibration session attached.\n'
```

The last line must be `Claude calibration session attached.` Keep this terminal available until
the three dedicated terminals in section 9 are attached. The temporary settings files are passed
only to the two calibration processes; preparation does not edit the owner's real Claude Code
settings. Each temporary `statusLine` object contains only the recorder command and
`refreshInterval: 30`. Claude Code documents that timer as an additional status-line update
trigger for idle periods; terminal resize is not one of its documented event triggers.

### 6.2 Codex preparation for P1-M10

Keep Codex closed until section 8 asks for one separate owner-controlled turn per profile. Count
the initialized, signed-in `codex-profile` profiles that Reset Radar must validate; M10 permits at
most two. Run:

```zsh
approved_revision="$(git rev-parse HEAD)"
test -z "$(git status --short)" || exit 1
zsh spikes/provider-source-calibration/prepare.zsh \
  --mode codex \
  --codex-profile-count 2 \
  --expected-revision "$approved_revision"
```

The script privately prompts for each profile name with terminal echo disabled. Enter each name in a stable order that you keep only in memory; do not put profile names in the worksheet. It validates each profile through `codex-profile`, then prints tool versions by private ordinal, one `/private/tmp/reset-radar-source-calibration.XXXXXX` directory, and a quoted `source` command. Record only the versions and profile count in the private worksheet. Copy the printed `source` command into the current terminal and every additional terminal used below.

Confirm the reattached state without printing identifiers:

```zsh
case "$source_calibration_root" in
  /private/tmp/reset-radar-source-calibration.*) ;;
  *) printf 'Unexpected calibration root. Stop.\n' >&2; exit 1 ;;
esac
test -f "$source_calibration_root/session.zsh"
printf 'Disposable session attached.\n'
```

Codex-only preparation does not read or edit anything under `~/.claude`, locate `claude`, or
create Claude artifacts. It copies only the Codex harness and verifier into the disposable
directory. Any later revision or worktree change causes cleanup to refuse until the reviewed state
is restored.

## 7. Preflight the installed Codex protocol

This step generates protocol metadata but does not start app-server or read account usage:

```zsh
zsh spikes/provider-source-calibration/preflight-codex.zsh \
  "$source_calibration_root/session.zsh"
```

For two selected profiles, it must report:

```text
Installed Codex schemas for 2 explicitly selected profiles and disposable harness preflight: PASS
```

The preflight requires the installed schema to contain the initialization contract, `initialized`
notification, structured `account/read` request and response with the ChatGPT discriminator and
boolean `requiresOpenaiAuth`, and `account/rateLimits/read` with `accountId`, `rateLimits`, and
`rateLimitsByLimitId`. If a future installed Codex changes these contracts, stop rather than
editing the live request ad hoc.

## 8. Run the Codex observation

Open one Terminal window per selected profile, plus one observation window, and source the printed session command in each. Keep the same private ordinal-to-profile order used during preparation. Each profile window runs its own 30-minute monitor; the observation window shows only privacy-safe projections and starts one normal Codex turn per matching profile.

In profile window 1:

```zsh
codex_calibration_index=1
(
  cd "$source_calibration_root"
  "$source_calibration_node" "$source_calibration_root/harness/codex-calibration.mjs" \
    --codex "${source_calibration_codex_launchers[$codex_calibration_index]}" \
    --report "${source_calibration_codex_reports[$codex_calibration_index]}" \
    --duration-minutes 30
)
```

Repeat in the next profile window with `codex_calibration_index=2`, and so on. Start all monitors close together; each writes only its own ordinal report.

After reports appear, the observation window may show only the allowed projection for a chosen ordinal:

```zsh
codex_calibration_index=1
jq '{
  failures,
  events: [.events[] | {
    at,
    kind,
    reason,
    latencyMs,
    accountIdentifierClassification,
    accountKind,
    requiresOpenaiAuth,
    defaultBucket,
    bounds
  }],
  exitedAfterStdinClose
}' "${source_calibration_codex_reports[$codex_calibration_index]}"
```

After each profile's initial read succeeds, perform exactly one ordinary, non-sensitive Codex turn in a separate owner-controlled session launched with that same `codex-profile` profile. Launch the private picker from the empty disposable directory so the command line and shell history contain no profile name:

```zsh
(
  cd "$source_calibration_root"
  "$source_calibration_codex_profile" cli
)
```

Select the profile matching the monitor's private ordinal. Do not copy the profile name, prompt, or response. That profile's monitor should record `rate-limit-update-notification` and a full `update-notification` refetch. If no notification arrives during the 30-minute run, record that profile's observation as deferred; do not create repeated turns.

The monitor must finish by itself. Do not interrupt it merely because a value did not change.

### Codex decision

For every selected profile, the 15-minute current-data candidate is technically acceptable only if:

1. the report contains one initial and six scheduled reads;
2. every read completes within 10 seconds;
3. no scheduled successful-read gap exceeds 15 minutes;
4. every legitimate response fits the frame, decoded UTF-8 string/key, depth, bucket-entry, and
   candidate-window bounds;
5. every default-bucket result is `unique` or `compatibility-only`; and
6. the structured account read proves a supported ChatGPT account, a present string identifier,
   and a boolean `requiresOpenaiAuth` of either value; and
7. app-server exits within five seconds after the harness closes stdin.

The final verifier checks every ordinal report and fails the combined Codex result if any selected profile fails. The owner records `15 minutes confirmed` or `15 minutes rejected` for each private ordinal; the verifier cannot make the product-policy decision for the owner. A profile-specific rejection returns the production profile-selection behavior to the owner rather than silently dropping that profile.

### Codex duration-class re-check

The original 30-minute run recorded window counts but not durations. To prove that every selected
profile reports only distinct five-hour (`300`) or weekly (`10080`) default-bucket windows, and at
least one of them, run a
short owner-present check from a new clean, owner-approved revision that contains the duration-class
harness. Never reuse the earlier disposable session. Repeat sections 5, 6 and 7 (offline tests,
`prepare.zsh --mode codex`, preflight), then run each profile window with `--duration-minutes 0`,
which performs the initial read only:

```zsh
codex_calibration_index=1
(
  cd "$source_calibration_root"
  "$source_calibration_node" "$source_calibration_root/harness/codex-calibration.mjs" \
    --codex "${source_calibration_codex_launchers[$codex_calibration_index]}" \
    --report "${source_calibration_codex_reports[$codex_calibration_index]}" \
    --duration-minutes 0
)
```

Repeat with `codex_calibration_index=2`, then verify and clean up as in sections 10 and 11, adding
`--duration-class-check` to the verifier:

```zsh
"$source_calibration_node" "$source_calibration_root/harness/verify-reports.mjs" \
  --mode codex --root "$source_calibration_root" --duration-class-check
```

It fails unless every profile's initial read shows at least one default-bucket window, every
reported window is a distinct `300` or `10080`, and the existing frame, account, and default-bucket
checks pass. An account may legitimately report only the weekly window (no five-hour limit, or its
weekly limit reached), in which case the five-hour ring is unavailable. No turn is needed
and no notification is expected. Do not record a 15-minute decision again; append a short sanitized
result to the existing Codex entry in [spike-results.md](spike-results.md) after cleanup. A failure
returns the five-hour and weekly mapping to the owner rather than changing it.

## 9. Run the Claude Code observation

M10 Codex-only calibration skips this section. M11 reaches this section only after sections 1
through 5 and the Claude Code-only preparation in section 6.1. Do not run sections 6.2, 7, or 8,
and do not use `--mode combined`. Never reuse a Codex disposable session.

This part uses three Terminal windows at the same time. Keep every unrelated Claude Code process closed. Do not run the following commands in a terminal pane inside Claude Code.

Use this layout:

| Terminal | Purpose | What you type there |
|---|---|---|
| **Observer** | Shows sanitized events from both sessions | Shell commands only; never a prompt |
| **A** | First isolated Claude Code session | Two ordinary prompts, timer-driven idle observations, and the 65-minute check |
| **B** | Second isolated Claude Code session | Two ordinary prompts and a timer-driven idle observation |

The first command in each terminal is the exact randomized `source /private/tmp/.../session.zsh` command printed by section 6. It cannot be written literally in this runbook because every preparation creates a different private directory. The complete commands after that first pasted line are repeated below for each terminal.

### 9.1 Start the Observer terminal

In **Observer**, first paste and run the exact `source .../session.zsh` command printed by preparation. Then paste this whole block:

```zsh
if test -n "${source_calibration_root:-}" \
    && test -f "$source_calibration_root/session.zsh"; then
  printf 'Observer attached.\n'
else
  printf 'Observer is not attached; closing this dedicated shell.\n' >&2
  exit 1
fi

touch "$source_calibration_claude_report_a" "$source_calibration_claude_report_b"
chmod 600 "$source_calibration_claude_report_a" "$source_calibration_claude_report_b"
tail -q -f "$source_calibration_claude_report_a" "$source_calibration_claude_report_b" \
  | jq -c '{
      at,
      label,
      invocation,
      activity,
      rateLimitType,
      windows,
      advanceObservedAt,
      observedAtReason
    }'
```

The first line of output must be `Observer attached.` The final command then waits silently until A or B writes a status-line event. Leave it running. It deliberately shows structure and classifications, not usage values. `label` identifies A or B:

- `activity:"first-observed"` means that session produced its first usable activity counter;
- `activity:"increased"` means Claude Code reported more API activity after a response;
- `activity:"unchanged"` means a timer-driven idle status-line rerun did not report new API activity;
- `advanceObservedAt:true` is required after a genuine response;
- `advanceObservedAt:false` is required for an idle redraw.

Stop if Observer prints invalid JSON, `activity:"invalid"`, or `activity:"decreased"`. Do not open either raw report to investigate.

### 9.2 Start session A

In **A**, first paste and run the exact `source .../session.zsh` command printed by preparation. Then paste this whole block:

```zsh
if test -n "${source_calibration_root:-}" \
    && test -f "$source_calibration_root/session.zsh"; then
  printf 'Session A attached.\n'
else
  printf 'Session A is not attached; closing this dedicated shell.\n' >&2
  exit 1
fi

cd "$source_calibration_claude_work_a"
"$source_calibration_claude" \
  --setting-sources user \
  --settings "$source_calibration_root/claude-a-settings.json" \
  --session-id "$source_calibration_claude_session_a" \
  --tools "" \
  --no-chrome
```

The shell must first print `Session A attached.` Claude Code then opens interactively in that terminal. The directory is intentionally empty. Do not approve a workspace-trust request, tool, hook, plugin, or command. Before typing a prompt, look at Claude Code's status line at the bottom of **A**. It must say:

```text
Reset Radar calibration A: recorded
```

This visible line only confirms that the temporary recorder ran. The Observer terminal may also print an initial A event; that event is optional and is not one of the two required responses.

Stop if the status line is absent, still shows the owner's normal status line, shows `B`, or Claude Code asks to trust the directory.

### 9.3 Start session B

In **B**, first paste and run the exact `source .../session.zsh` command printed by preparation. Then paste this whole block:

```zsh
if test -n "${source_calibration_root:-}" \
    && test -f "$source_calibration_root/session.zsh"; then
  printf 'Session B attached.\n'
else
  printf 'Session B is not attached; closing this dedicated shell.\n' >&2
  exit 1
fi

cd "$source_calibration_claude_work_b"
"$source_calibration_claude" \
  --setting-sources user \
  --settings "$source_calibration_root/claude-b-settings.json" \
  --session-id "$source_calibration_claude_session_b" \
  --tools "" \
  --no-chrome
```

The shell must first print `Session B attached.` Before typing a prompt, the status line at the bottom of **B** must say:

```text
Reset Radar calibration B: recorded
```

The separate empty A and B directories prevent either session from reading the repository. Stop under the same conditions listed for A.

### 9.4 Perform the short observations

A “prompt” below means one short, ordinary, non-sensitive request typed manually into Claude Code. It must not mention Reset Radar, this repository, credentials, account details, private files, or personal content. Wait for the complete Claude Code response and the next matching Observer event before continuing. Do not paste the prompt or response anywhere else.

1. In **A**, submit the first prompt and wait for its response. In **Observer**, wait for an event with `label:"A"`. It must have `activity:"first-observed"` or `activity:"increased"`, and it must have `advanceObservedAt:true`.
2. Do not send another prompt or interact with A. Within 40 seconds, the 30-second temporary timer
   should produce a new A event with `activity:"unchanged"` and `advanceObservedAt:false`. If no
   event appears, record the early A idle check as deferred; do not manufacture activity.
3. In **A**, submit the second prompt and wait for its response. The next response-linked A event must have `activity:"increased"` and `advanceObservedAt:true`. Privately note that event's `at` time; it starts the 65-minute wait in section 9.5.
4. Leave **A** idle. In **B**, submit the first prompt and wait for its response. The next response-linked B event must have `activity:"first-observed"` or `activity:"increased"`, and `advanceObservedAt:true`.
5. Without sending anything or changing modes in A, wait up to 40 seconds after the response-linked
   B event. The next timer-driven A event must show `label:"A"`, `activity:"unchanged"`, and
   `advanceObservedAt:false`. This is the proof that B's activity did not make A fresh.
6. Without sending another prompt or changing modes in B, wait up to 40 seconds. The next
   timer-driven B event must show `label:"B"`, `activity:"unchanged"`, and
   `advanceObservedAt:false`.
7. In **B**, submit the second prompt and wait for its response. The next response-linked B event must have `activity:"increased"` and `advanceObservedAt:true`.

There are exactly four allowance-spending turns: A twice and B twice. Timer-driven reruns are not
turns. Multiple Observer events may appear during one response; judge the response by the first
matching event that shows the required activity transition. Stop if a response completes but no
matching event appears after ten seconds, or if any transition has the wrong label or
classification.

The early idle check after A's first response may be deferred because the later cross-session and
60-minute A checks can still supply A's required idle evidence. B must produce at least one idle
event. A response-linked event, B's required idle event, cross-session isolation, or the 60-minute
event cannot be deferred and still pass the verifier.

### 9.5 Perform the 65-minute A check

Keep A, B, and Observer open. Send no more prompts and do not change permission or Vim modes. Wait
until at least 65 minutes after the `at` time privately noted for A's second response in step 3.
The extra five minutes avoids failing the check because of clock or observation delay.

Within the next 40 seconds, the temporary timer must produce an A event with:

```text
activity:"unchanged"
advanceObservedAt:false
```

If no A event appears, record the 60-minute idle observation as deferred. Do not send a fifth
prompt or change an interface mode to provoke the status line. The verifier will not pass, M11
will remain active, and the deferral must be recorded honestly.

### 9.6 End the observation

1. In **A**, type `/exit` and wait until the normal shell prompt returns.
2. In **B**, type `/exit` and wait until the normal shell prompt returns.
3. In **Observer**, press Control-C once to stop `tail`.
4. Leave all three shell windows open for verification and cleanup in sections 10 and 11.

Each owner-submitted turn spends normal Claude Code allowance. The harness neither supplies nor stores the prompt. Claude Code may create its normal local first-party session/history records during the run; section 11 removes the exact two generated sessions and restores the original history prefix before evidence is written.

### 9.7 Make the Claude Code decision

The 60-minute candidate is technically acceptable only if:

1. four observed genuine responses across A and B cause response-linked observations;
2. each session has at least one genuine activity increase;
3. idle reruns in both sessions keep the earlier observation time;
4. B activity cannot make idle A data fresh;
5. an A idle event at least 60 minutes after its last increase remains unchanged; and
6. non-spend rate-limit windows have valid percentage and reset field shapes.

This does not promise that Claude Code obtains remote-account changes within 60 minutes. Its data remains “last reported by Claude Code.” The owner records `60 minutes confirmed` or `60 minutes rejected`.

## 10. Verify and privately capture the summary

Before editing any repository file, run the command for the active mode.

For P1-M11 Claude Code-only verification:

```zsh
"$source_calibration_node" "$source_calibration_root/harness/verify-reports.mjs" \
  --mode claude \
  --root "$source_calibration_root"
```

The command must exit successfully and print one redacted JSON object with `mode: "claude"`,
`privacyShapeChecks: "pass"`, aggregate event counts, public `windowKinds`,
`currentDataWindowMinutes: 60`, `currentDataWindowTechnicalChecks: "pass"`, and
`crossSessionIsolationChecks: "pass"`. It also writes that same sanitized object inside the
disposable directory. Copy only the printed redacted object into the private worksheet. Do not
open either `claude-*-report.jsonl` file.

The verifier proves the technical criteria but does not make the owner's policy decision. After
reviewing the redacted result, write exactly one of these in the private worksheet:

```text
60 minutes confirmed
60 minutes rejected
```

A verifier failure is not a rejection decision by itself. Record the named criterion as failed or
deferred, do not inspect a raw report, and continue to the exact cleanup after both Claude Code
sessions are closed.

For P1-M10 Codex verification:

```zsh
"$source_calibration_node" "$source_calibration_root/harness/verify-reports.mjs" \
  --mode codex \
  --root "$source_calibration_root"
```

The Codex-mode verifier fails unless every selected Codex profile has all required technical
observations. It neither opens nor requires a Claude report. Its printed JSON is redacted and may
be transcribed into the private worksheet. Do not copy an underlying report.

`updateNotificationObserved: false` in any ordinal profile summary is an explicit Codex deferral, even if every other technical check passes. The owner still decides whether each current-data window is confirmed or rejected.

## 11. Clean up before editing evidence

Save the redacted verifier summary in the private worksheet, because cleanup permanently removes
the disposable reports. Codex-only cleanup does not inspect or delete Claude data.

For P1-M11, first exit A and B, stop Observer, and close every other Claude Code process. Keep an
ordinary shell with the session attached, then run:

```zsh
zsh spikes/provider-source-calibration/cleanup.zsh \
  --mode claude \
  --confirm-delete-calibration-sessions \
  "$source_calibration_root/session.zsh"
```

Cleanup proves the repository revision and worktree are unchanged, verifies the real settings
checksum, restores the exact pre-run history prefix, removes only the two generated session UUIDs
from the bounded Claude Code stores, scans `~/.claude` for either UUID, and removes the validated
disposable directory. Successful output is:

```text
claude calibration disposable files removed and repository unchanged: PASS
```

Only after this line appears may repository evidence be edited. The shell variables may still
name the removed path; do not reuse them or rerun cleanup.

For P1-M10, the following command removes only the validated Codex-mode
`/private/tmp/reset-radar-source-calibration.*` directory after proving the repository is still at
the recorded revision and status:

```zsh
zsh spikes/provider-source-calibration/cleanup.zsh \
  --mode codex \
  "$source_calibration_root/session.zsh"
```

If cleanup refuses, do not broaden its path, delete by age, truncate an unverified history file, or use a wildcard over `~/.claude`. Preserve the disposable directory and investigate privately.

Successful Codex output is:

```text
codex calibration disposable files removed and repository unchanged: PASS
```

## 12. Record project evidence

Only after successful cleanup, append one dated entry for the active mode to
[spike-results.md](spike-results.md).

For P1-M11, give the agent only:

- the UTC date and the public macOS, Node.js, and Claude Code versions;
- the exact reviewed public commit hash and whether the offline tests passed;
- the verifier's redacted aggregate JSON object;
- `60 minutes confirmed` or `60 minutes rejected`;
- whether cleanup printed its exact success line; and
- any failed or deferred criterion named without a raw value, path, identifier, prompt, or
  response.

Do not send the private `source` command, disposable path, session UUIDs, raw reports, terminal
screenshots, prompts, responses, usage values, reset times, activity-counter values, settings
content, or Claude Code history. The agent turns the permitted handoff into this project entry:

```markdown
### Claude Code source calibration — YYYY-MM-DD

- **Attendance:** Owner-present. No raw response, credential, account/session identifier, prompt, response content, percentage, reset timestamp, activity-counter value, or project path was retained in Reset Radar evidence.
- **Question:** Does the installed Claude Code status-line source satisfy the approved field shape, response-linked activity, two-session isolation, idle non-advancement, and 60-minute current-data assumptions?
- **Method and versions:** Public macOS, Node.js, and Claude Code versions; exact reviewed revision; passing offline synthetic tests; two isolated temporary-settings sessions with the documented 30-second refresh interval; exactly four owner-entered ordinary turns; and the 65-minute idle procedure.
- **Claude Code measurements:** Redacted aggregate event, advancing, increased, and idle counts; public window kinds and the presence of at least one non-spend kind; privacy-shape result; cross-session-isolation result; 60-minute technical result; and the owner's `60 minutes confirmed` or `60 minutes rejected` decision.
- **Privacy and cleanup:** Repository revision and status unchanged; real settings unchanged; original history prefix restored; both generated session UUIDs absent after the bounded scan; disposable directory removed.
- **Result:** Pass, fail, or deferred, with each blocker named. A rejected threshold, source-shape contradiction, required deferral, or cleanup failure leaves M11 active and returns that rule to the owner.
```

After a passing, confirmed result, the agent removes Claude Code's candidate wording from
`CurrentDataWindow` and affected active docs without changing Codex claims, updates the M11
checklist, phase plan, research evidence, and changelog, and delegates the focused and complete
gate to `test_runner`. M11 becomes `Done` only after that evidence exists and every remaining
required checklist item is satisfied.

For P1-M10, use this Codex entry:

```markdown
### Codex source calibration — YYYY-MM-DD

- **Attendance:** Owner-present. No raw response, credential, account/session identifier, prompt, response content, percentage, reset timestamp, or project path was retained in Reset Radar evidence.
- **Question:** Do both installed Codex profiles satisfy the approved source, identity, bounds, notification, and freshness assumptions?
- **Method and versions:** macOS, Node.js, `codex-profile`, installed Codex versions by anonymous ordinal, selected profile count, exact reviewed revision, synthetic-test result, and 30-minute observation duration.
- **Codex measurements:** For each anonymous ordinal, sanitized field shape; account-identifier presence/type and approved sign-in shape; initial plus six scheduled reads and latency range; frame/string-byte/depth/bucket-entry/candidate-window maxima; compatibility-only or unique default-bucket result and matching basis; notification/refetch observation or explicit deferral; clean child shutdown; 15-minute decision.
- **Privacy checks:** Repository revision and status unchanged during execution; no Claude state inspected or created; disposable files removed.
- **Result:** Pass, fail, or deferred, with each blocker named. A rejected threshold or response signal returns that rule to the owner.
```

Do not include raw frames, field values, usage percentages, reset times, bucket/limit IDs, `codex-profile` names or homes, session UUIDs, disposable or executable paths, prompts, responses, or screenshots. Maximum byte counts and latency measurements are permitted because they are required structural evidence and do not disclose source content.

The source-calibration milestone result stays unchecked until this dated evidence exists and both owner decisions are recorded. The runbook-delivery checklist item may be checked once the branch programs, offline tests, links, and documentation gate have passed.
