# Claude Code Mod usage acquisition

Status: Active

Research on whether a Claude Code Mod can supply Reset Radar with account allowance usage and reset times. Checked 2026-10-25 against Anthropic's current Mods documentation, published type declarations, and the locally installed Claude Code 2.1.310; this is a public-source feasibility finding, not a signed-in Mod calibration.

## Verdict

**Yes, conditionally.** A Mod can observe Claude Code's account-level `rateLimits` and hand a privacy-minimized record to a local Mac helper. The published `session.measure` event carries window kind, percentage used, and optional reset time; `$.session.usage()` exposes the same cached reading. The Mods API supports local file writes and, in the CLI, direct process invocation. This closes the export-path uncertainty in [the upstream audit](upstream-automatic-usage-sources.md#claude-code).

**It does not provide an independent usage query.** The windows come from the session's last API response. They are empty before a reading or where the host has no subscription rate-limit data. A Mod cannot make an idle session's account reading current merely by calling `$.session.usage()` or running a timer. Reset Radar would still need to show the time of the last reported reading, expire old windows, and wait for Claude Code to receive new provider state.

The project should keep its [approved status-line source](../../architecture/provider-adapters.md#claude-code-status-line) for the current implementation. A Mod is a viable future alternative if a narrow local export passes an offline and owner-present spike and the owner approves changing the acquisition mechanism. This research does not approve a source migration or a second production source.

## Evidence and data shape

| Finding | Evidence | Consequence |
|---|---|---|
| A Mod is a plugin with a function-hooks module. Mods load by default in terminal Claude Code 2.1.287+, subject to settings and organization policy. | [Mods overview](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off). Local `claude --version` reported 2.1.310 on 2026-10-25. | The owner's installed CLI meets the documented version floor, but load and policy still need a real-session check. |
| `session.measure` fires after a turn and when a plan-limit percentage changes. Its `rateLimits` entries have `kind`, `percentUsed`, and optional `resetsAt`; `changed` identifies which usage unit moved. | [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference), [published `SessionMeasureInput` and `SessionRateLimit` types](https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts). | A hook can capture five-hour and seven-day percentage-used windows without parsing a full status-line payload. Unknown kinds should remain unknown; gateway `spend_limit` is outside the product gauge. |
| `$.session.usage()` returns the same account windows from the last API response. The type says an empty list means no reading; the event may appear before a usable rate limit exists. | [Published `SessionUsage` type](https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts), [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference). | A `session.start` read may find an already available value, but it cannot establish that the provider just refreshed it. No zero or reset should be inferred from absence. |
| `$.fs.write` accepts an absolute path but is explicitly non-atomic. `$.process.run` accepts an argument vector and standard-input text in the CLI. `$.store` is shared across sessions but lives in Claude Code's configuration directory. | [Mods reference, API methods](https://code.claude.com/docs/en/plugins/mods/reference#mods-api-methods), [published filesystem and process types](https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts). | A Mod can export locally. Directly writing a collector-readable shared file risks a partial read; invoking a dedicated helper with minimal JSON is the better candidate for the existing atomic, per-session record boundary. Do not make the Mac collector depend on reading Claude Code's private plugin store. |
| Mods can read files, start processes, access network and session content, and act with the user's permissions. Anthropic labels the generated function-hook API early access. | [Mods trust guidance](https://code.claude.com/docs/en/plugins/mods/overview#decide-whether-to-trust-a-mod), [Anthropic Mods source README](https://github.com/anthropics/claude-code/blob/main/mods/README.md). | Keep any candidate Mod project-owned, minimal, auditable, and version-gated. Do not import a third-party usage Mod into the collector merely because it displays the same percentages. |

The Mod's `resetsAt` is an ISO 8601 string, whereas the selected classic status line uses `resets_at` as Unix seconds. Either path must normalize to the same internal window model and retain the actual source version. The `session.measure` event reports a changed unit after turns and whole-point limit changes; it is not a guaranteed per-response export of every fractional change or a provider refresh feed while idle.

## Candidate local bridge

If the owner later chooses to prototype a Mod, the narrow path is:

1. Register only `session.measure` and optionally `session.start`. Read `rateLimits`, the Claude Code version, the session ID, and a local receipt time. Do not inspect prompts, responses, settings, credentials, context content, or cost.
2. Allow only non-spend windows with finite 0–100 `percentUsed`; carry `kind` and optional valid `resetsAt` through a small, versioned record. Treat an empty collection as unavailable, not 0%.
3. In the local CLI, call a fixed Reset Radar helper directly with `$.process.run([...], { stdin: ... })`. Let the helper enforce byte and schema bounds, hash the session ID for its filename, and perform the existing owner-only atomic record write. A direct `$.fs.write` would need a separate safe read protocol because Anthropic says the write is non-atomic.
4. Keep the collector's existing per-session merge, freshness, dropped-window, and reset-expiry rules. Reject a source-version or schema mismatch visibly. Never issue a model request to get a new reading.

This is an **inferred design**, not a proven integration. In particular, the published API does not promise that a Mod's receipt time is the provider response time, that every session surface can run a local Mac helper, or that `session.measure` will fire after an idle reset. A CLI-only prototype should establish the actual sequence and transport behavior before a design change. Mods also run in desktop, editor, headless, and some cloud sessions; the helper path must fail harmlessly wherever it is unavailable.

## Compared with the selected status line

| Criterion | Current status-line helper | Candidate Mod |
|---|---|---|
| Provider data | First-party `rate_limits` supplied to the command. | First-party `rateLimits` from Claude Code's last response. Same basic freshness limit. |
| Owner configuration | Exact preview and confirmation edit the user `statusLine`; existing commands must pass the narrow composition checks. | Install and enable a plugin; need a separate owner-facing setup, policy/load detection, removal, and version check. Does not consume the status-line slot. |
| Local export | Helper already receives stdin and atomically writes bounded per-session records. | Possible through `$.process.run` into a helper; `$.fs.write` alone is not atomic. No prototype has yet proved the helper call. |
| Scope of code run inside Claude Code | External helper processes the status-line input. | Mod code runs with broad user permissions and must be reviewed as trusted code. |
| Project state | Implemented and calibrated on Claude Code 2.1.310. | Public API feasibility only; no installed Mod, offline test, or signed-in comparison in this research. |

The likely benefit is removing the status-line composition constraint, especially for owners with an existing command that Reset Radar cannot safely compose. The cost is a new plugin lifecycle and a broader code trust boundary. Neither path makes Claude Code usage independently queryable by Reset Radar.

## Verification needed before any migration

- Offline, use `claude plugin validate` to confirm the candidate hooks and calls, and `claude plugin test` with synthetic rate-limit changes, empty readings, duplicate sessions, malformed values, resets, and helper failure. Anthropic documents both commands as usable without a signed-in session.
- With the owner present, compare sanitized Mod and status-line observations from the same Claude Code 2.1.310 session: first reading, post-response percentage and reset, idle period, window reset, two concurrent sessions, and helper unavailability. Record shapes and timings only, following the [source-calibration privacy boundary](source-calibration-spike-runbook.md).
- Check safe-mode, `disableAllHooks`, organization policy, plugin reload, and CLI update behavior. A missing or disabled Mod must surface as source unavailable, never as 0% used.
- If the spike supports replacement, request the owner's source choice before changing the binding ProviderAdapters architecture, source setup flow, or dependencies.

## Sources

- [Anthropic Mods overview](https://code.claude.com/docs/en/plugins/mods/overview): definition, version floor, installation, runtime locations, and trust model.
- [Anthropic Mods reference](https://code.claude.com/docs/en/plugins/mods/reference): `session.measure`, `$.session.usage()`, file/process operations, non-atomic writes, and limits.
- [Anthropic Create a mod](https://code.claude.com/docs/en/plugins/mods/create): plugin layout, validation, and offline testing.
- [Anthropic published function-hook declarations](https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts): exact rate-limit, event, filesystem, and process types. The repository copy checked on 2026-10-25 says it was generated by Claude Code 2.1.277; a production Mod must regenerate types from the installed CLI.
- [Anthropic Mods source README](https://github.com/anthropics/claude-code/blob/main/mods/README.md): built-in Mod structure and early-access compatibility warning.
