# Provider source-calibration spike runbook

Status: Active

This owner-run procedure validates the installed, signed-in Codex app-server and Claude Code status-line sources without creating the production project. It uses reviewed programs on the disposable `spike/provider-source-calibration` branch and retains only privacy-safe structural and timing evidence.

## 1. Authority, scope, and branch

Run this procedure only on the owner's Mac, with the owner present. It uses the owner's existing first-party sign-ins but never reads a provider authentication file or Keychain item directly. It does not connect to the Reset Radar relay, modify a real provider setting, install a dependency, or send provider data to Reset Radar infrastructure.

The executable spike lives only on the disposable branch:

```zsh
git branch --show-current
```

The output must be exactly:

```text
spike/provider-source-calibration
```

Do not merge the `spikes/provider-source-calibration/` directory into the production branch. After the spike is decided, copy only reviewed reusable code through P1-M3 implementation and retain only redacted evidence and maintained documentation.

The spike files are:

| File | Responsibility |
|---|---|
| [`codex-calibration.mjs`](../../../spikes/provider-source-calibration/codex-calibration.mjs) | Bounded JSON-RPC client, sanitized Codex shape/timing report, default-bucket proof, polling, notification refetch, and clean shutdown check |
| [`claude-recorder.mjs`](../../../spikes/provider-source-calibration/claude-recorder.mjs) | Bounded status-line decoder and per-session activity classification with no raw-value persistence |
| [`prepare.zsh`](../../../spikes/provider-source-calibration/prepare.zsh) | Hidden `codex-profile` selection, isolated per-profile launchers and reports, fail-closed environment capture, disposable directory, exact Claude session IDs, settings wrappers, and cleanup baselines |
| [`preflight-codex.zsh`](../../../spikes/provider-source-calibration/preflight-codex.zsh) | Per-profile installed-version Codex schema validation and harness syntax checks without reading account usage |
| [`verify-reports.mjs`](../../../spikes/provider-source-calibration/verify-reports.mjs) | Technical pass/fail checks and a redacted summary after both live observations |
| [`cleanup.zsh`](../../../spikes/provider-source-calibration/cleanup.zsh) | Exact Claude history/session cleanup, settings/repository non-modification checks, and disposable-directory removal |
| [`test.zsh`](../../../spikes/provider-source-calibration/test.zsh) | Offline synthetic tests; it never starts real Codex or Claude Code |

## 2. What the procedure does and does not prove

The Codex half, once for every profile the owner explicitly selects:

1. Generates protocol schemas from the exact installed Codex executable.
2. Starts `codex-profile cli PROFILE app-server --listen stdio://` from the disposable directory, with analytics disabled and a minimal environment. `codex-profile` validates the named profile and supplies its `CODEX_HOME`; the harness never uses an ambient profile or workspace binding.
3. Initializes JSON-RPC and calls `account/rateLimits/read` through the signed-in first-party process.
4. Performs one initial read and six five-minute polls over 30 minutes.
5. Observes `account/rateLimits/updated` during one owner-initiated Codex turn and refetches no more than once per minute.
6. Measures only frame size, structural limits, latency, field presence/types, and the structural correspondence of the compatibility bucket.

The Claude Code half cannot actively query usage. It temporarily overrides `statusLine` only for two command-line processes, then observes the status-line payload after owner-submitted turns. It validates whether `cost.total_api_duration_ms` increases after a response and stays unchanged on idle UI reruns. It never generates a turn itself.

This validates the installed versions and the proposed source rules. Selecting multiple profiles for calibration does not decide that the first version tracks several Codex accounts simultaneously; it prevents the spike from silently testing the wrong profile and records whether the source assumptions hold for each owner-designated profile. The procedure does not prove compatibility with a future release, the production adapter implementation, source installation/restore behavior, relay publication, mobile ingestion, or UI behavior.

## 3. Privacy boundary and stop conditions

Close screen sharing and terminal recording. Do not enable shell tracing (`set -x`). Do not copy provider output into a worksheet, issue, commit, message, or screenshot.

The live harness may hold one raw source message in memory while classifying it. Its reports may contain only:

- UTC event time and elapsed milliseconds;
- message byte counts, latency, maximum string length, nesting depth, and decoded-window count;
- field names, JSON value types, presence, validity, and timestamp plausibility classes;
- `unique`, `compatibility-only`, `not-found`, or `ambiguous` as the Codex default-bucket result;
- `absent`, `first-observed`, `increased`, `unchanged`, `decreased`, or `invalid` as the Claude activity result;
- the public Claude Code window kinds and the owner's accept/reject decision for each freshness candidate.

The reports and project evidence must not retain an actual percentage, reset instant, duration reported by a rate-limit window, bucket key, limit ID/name, plan, balance, account/session identifier, `codex-profile` name or home, prompt, response content, credential, provider-reported path, or raw message. The spike adds profile names only to process memory and the private disposable launchers until cleanup; it does not alter `codex-profile`'s own existing configuration.

The disposable per-label Claude state file temporarily stores only the prior numeric `total_api_duration_ms` counter, invocation count, and whether a normal rate-limit window was previously present. The recorder needs that counter to classify the next invocation as increased, unchanged, or decreased. It is never printed or copied into evidence and section 11 permanently removes it.

The preparation script assigns explicit disposable Claude session UUIDs and separate empty working directories. Cleanup restores the pre-run `~/.claude/history.jsonl` prefix byte-for-byte, deletes UUID-matching entries only from Claude Code's `~/.claude/projects`, `~/.claude/session-env`, and `~/.claude/tasks` session stores, scans all of `~/.claude` for remaining UUID references, verifies the real Claude settings checksum, and verifies that the repository status did not change during the live run.

Stop and record a failure or deferral if:

- the active branch is not `spike/provider-source-calibration`;
- `codex-profile` is unavailable, a requested profile is uninitialized, a profile is selected twice, or any owner-intended profile is omitted;
- synthetic tests or installed-schema preflight fail;
- any command would require copying a credential or raw provider response;
- a legitimate Codex frame exceeds 1 MiB, a string exceeds 4 KiB, nesting exceeds 32 levels, or more than 128 windows are decoded;
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
| Codex | Number of explicitly selected profiles; for each private ordinal only, schema preflight, read count, latency range, structural maxima, default-bucket result/basis, notification/refetch observed or deferred, child shutdown, and 15-minute decision |
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

Save all work and close every Claude Code process. Keep Codex closed until the Codex instruction below asks for one separate owner-controlled turn per profile. Count the initialized, signed-in `codex-profile` profiles that Reset Radar must validate; the owner has two at the time this runbook was written.

Run:

```zsh
zsh spikes/provider-source-calibration/prepare.zsh --codex-profile-count 2
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

Preparation does not edit `~/.claude/settings.json`. It copies the reviewed harness programs into the disposable directory so the live run has an immutable per-run copy even if the branch changes later.

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

The preflight requires the installed schema to contain the initialization contract, `initialized` notification, `account/rateLimits/read`, `rateLimits`, and `rateLimitsByLimitId`. If a future installed Codex changes these contracts, stop rather than editing the live request ad hoc.

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
4. every legitimate response fits all four safety bounds;
5. every default-bucket result is `unique` or `compatibility-only`; and
6. app-server exits within five seconds after the harness closes stdin.

The final verifier checks every ordinal report and fails the combined Codex result if any selected profile fails. The owner records `15 minutes confirmed` or `15 minutes rejected` for each private ordinal; the verifier cannot make the product-policy decision for the owner. A profile-specific rejection returns the production profile-selection behavior to the owner rather than silently dropping that profile.

## 9. Run the Claude Code observation

This part uses three Terminal windows at the same time. Keep every unrelated Claude Code process closed. Do not run the following commands in a terminal pane inside Claude Code.

Use this layout:

| Terminal | Purpose | What you type there |
|---|---|---|
| **Observer** | Shows sanitized events from both sessions | Shell commands only; never a prompt |
| **A** | First isolated Claude Code session | Two ordinary prompts, idle resizes, and the 65-minute check |
| **B** | Second isolated Claude Code session | Two ordinary prompts and one idle resize |

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
- `activity:"unchanged"` means an idle status-line redraw did not report new API activity;
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
2. Do not send another prompt. Resize terminal **A** horizontally a few times, then wait up to ten seconds. Observer must show a new A event with `activity:"unchanged"` and `advanceObservedAt:false`. If no event appears, record the A idle-redraw check as deferred; do not manufacture activity.
3. In **A**, submit the second prompt and wait for its response. The next response-linked A event must have `activity:"increased"` and `advanceObservedAt:true`. Privately note that event's `at` time; it starts the 65-minute wait in section 9.5.
4. Leave **A** idle. In **B**, submit the first prompt and wait for its response. The next response-linked B event must have `activity:"first-observed"` or `activity:"increased"`, and `advanceObservedAt:true`.
5. Without sending anything in A, resize terminal **A** and wait up to ten seconds. Observer must show `label:"A"`, `activity:"unchanged"`, and `advanceObservedAt:false`. This is the proof that B's activity did not make A fresh.
6. Without sending another prompt in B, resize terminal **B** and wait up to ten seconds. Observer must show `label:"B"`, `activity:"unchanged"`, and `advanceObservedAt:false`.
7. In **B**, submit the second prompt and wait for its response. The next response-linked B event must have `activity:"increased"` and `advanceObservedAt:true`.

There are exactly four allowance-spending turns: A twice and B twice. Resizing a terminal is not a turn. Multiple Observer events may appear during one response; judge the response by the first matching event that shows the required activity transition. Stop if a response completes but no matching event appears after ten seconds, or if any transition has the wrong label or classification.

### 9.5 Perform the 65-minute A check

Keep A, B, and Observer open. Send no more prompts. Wait until at least 65 minutes after the `at` time privately noted for A's second response in step 3. The extra five minutes avoids failing the check because of clock or observation delay.

Then resize terminal **A** without submitting a prompt. Within ten seconds, Observer must print an A event with:

```text
activity:"unchanged"
advanceObservedAt:false
```

If no A event appears after several resizes, record the 60-minute idle observation as deferred. Do not send a fifth prompt to provoke the status line.

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

Before editing any repository file, run:

```zsh
"$source_calibration_node" "$source_calibration_root/harness/verify-reports.mjs" \
  --root "$source_calibration_root"
```

The verifier fails unless all required technical Codex and Claude observations are present. Its printed JSON is redacted and may be transcribed into the private worksheet. Do not copy either underlying report.

`updateNotificationObserved: false` in any ordinal profile summary is an explicit Codex deferral, even if every other technical check passes. The owner still decides whether each current-data window is confirmed or rejected.

## 11. Clean up before editing evidence

Close every Claude Code process. Save the redacted verifier summary in the private worksheet, because cleanup permanently removes the disposable reports.

The following command permanently deletes only UUID-matching entries for the two explicitly identified calibration sessions from Claude Code's `projects`, `session-env`, and `tasks` stores, removes their appended global-history entries after proving the original prefix is unchanged, and removes the validated `/private/tmp/reset-radar-source-calibration.*` directory:

```zsh
zsh spikes/provider-source-calibration/cleanup.zsh \
  --confirm-delete-calibration-sessions \
  "$source_calibration_root/session.zsh"
```

The cleanup script refuses to proceed if another Claude Code process is running, either session UUID is malformed, the original history prefix changed, the real settings checksum changed, the repository status changed, or the target directory is outside the expected `/private/tmp` prefix.

If cleanup refuses, do not broaden its path, delete by age, truncate an unverified history file, or use a wildcard over `~/.claude`. Preserve the disposable directory and investigate privately.

Successful output is:

```text
Calibration session data, history additions, and disposable files removed: PASS
```

## 12. Record project evidence

Only after successful cleanup, append one dated entry to [spike-results.md](spike-results.md):

```markdown
### Provider source calibration — YYYY-MM-DD

- **Attendance:** Owner-present. No raw response, credential, account/session identifier, prompt, response content, percentage, reset timestamp, or project path was retained in Reset Radar evidence.
- **Question:** Do the installed Codex and Claude Code versions satisfy the approved source, bounds, response-signal, and freshness assumptions?
- **Method and versions:** macOS, Node.js, `codex-profile`, installed Codex versions by anonymous ordinal, selected profile count, installed Claude Code, disposable-branch revision, synthetic-test result, and observation durations.
- **Codex measurements:** For each anonymous ordinal, sanitized field shape; read count and latency range; frame/string/depth/window maxima; compatibility-only or unique default-bucket result and matching basis; notification/refetch observation; clean child shutdown; 15-minute decision.
- **Claude Code measurements:** Sanitized field shape and public window kinds; response-linked, increased, and unchanged event counts; two-session isolation; 60-minute observation; 60-minute decision.
- **Privacy checks:** Real settings unchanged; repository unchanged during execution; original history restored; calibration UUID scan clear; disposable files removed.
- **Result:** Pass, fail, or deferred, with each blocker named. A rejected threshold or response signal returns that rule to the owner.
```

Do not include raw frames, field values, usage percentages, reset times, bucket/limit IDs, `codex-profile` names or homes, session UUIDs, disposable or executable paths, prompts, responses, or screenshots. Maximum byte counts and latency measurements are permitted because they are required structural evidence and do not disclose source content.

The source-calibration milestone result stays unchecked until this dated evidence exists and both owner decisions are recorded. The runbook-delivery checklist item may be checked once the branch programs, offline tests, links, and documentation gate have passed.
