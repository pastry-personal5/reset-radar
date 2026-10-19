# Usage tracking

Status: Active

Research for automatically displaying how much allowance has been used in each reset window, such as “70% used · resets in 5h” and “20% used · resets this week.” This study defines product semantics and data-source boundaries; the code-level source selection is in [automatic-usage-acquisition.md](automatic-usage-acquisition.md).

Sources were checked on 2026-10-19. No account was accessed and no private endpoint or credential was tested.

## 1. Decision and recommendation

The owner requires automatic usage tracking for supported coding allowances. Reset Radar must support multiple concurrent allowance windows for a service and automatically display each sourced window's percentage used together with its reset time. Codex and Claude Code do not establish automatic coverage for every general ChatGPT or Claude web/mobile allowance.

Selected boundary:

- Collect provider-reported percentages on Mac through installed first-party CLI interfaces.
- Use Codex app-server for Codex and Claude Code status-line snapshots for Claude.
- Send only normalized, credential-free observations to the paired iPhone; the first-version watchOS app receives the same model through iPhone.
- Show source and freshness everywhere the percentage appears.
- Do not infer a consumer allowance percentage from elapsed time, token logs, API rate-limit headers, or another window.
- Do not automatically access a consumer account with a cookie, copied OAuth token, password, embedded browser session, or undocumented endpoint.
- When the Mac or CLI source is unavailable, show stale/unavailable state instead of switching source silently.

This makes automatic percentages feasible without weakening the credential boundary, but it makes the Mac collector a required acquisition component. The value remains a timestamped snapshot rather than a continuously authoritative counter.

## 2. Product semantics

### What the percentage means

For a provider-reported allowance, store and present its percentage-used orientation:

`displayed percent = clamp(provider used percent, 0...100)`

Preserve the source's precision internally and apply display rounding separately. Do not invert a rounded used value into percentage remaining.

Each displayed window needs:

- A stable local identifier.
- A user-facing label such as “5-hour” or “Weekly.”
- A reset instant or recurrence rule.
- Percentage used in the closed range 0 through 100.
- Observation time (“updated 12 min ago”).
- Source and confidence: provider-reported through Codex app-server or Claude Code status-line state; other source kinds remain representable for diagnostics.
- Availability state: current, stale, unavailable, or reset-awaiting-refresh.

The percentage is an allowance snapshot, not a clock. A window at 70% used does not rise merely because time passes. Conversely, 70% of elapsed window time does not imply 70% of allowance used.

### Terms that must stay separate

| Term | Meaning | Can it drive the requested percentage? |
|---|---|---|
| Consumer included allowance | Account-specific Claude/ChatGPT capacity inside a five-hour, weekly, model, or feature window. | Yes, when the vendor UI, first-party local tool, or user provides it. |
| API throughput limit | Requests or tokens permitted in a short replenishing API rate-limit period. | Only for an explicitly separate API mode. It is not consumer subscription usage. |
| API spend or credits | Currency/credit balance and monthly controls. | No; show separately if ever supported. |
| Local token activity | Tokens observed in local logs or sessions. | No authoritative percentage; it misses other devices and vendor-specific weighting. |
| Context-window usage | Tokens occupying the current conversation context. | No; it is not plan allowance. |
| Window elapsed time | Time since the allowance window began. | Useful for pace, never as allowance usage. |

### Reset behavior and staleness

- When a predicted reset time arrives without a fresh observation, mark the old percentage “reset expected — refresh usage.” Do not silently display 0%.
- A fresh source value after reset starts a new observation series.
- If one window is missing, show it as unavailable. Never derive the five-hour value from the weekly value or reuse a previous cycle's value.
- Always retain the last observation time and source. Widgets must not omit the staleness indicator merely to save space.
- If threshold alerts are ever approved, they should fire only when a fresh observation crosses a configured used threshold, once per window cycle. A countdown reaching reset is a separate event.

## 3. Acquisition options

| Rank | Source | Consumer-plan accuracy | Credentials and terms | Recommendation |
|---|---|---|---|---|
| 1 | Mac collector reads structured state exposed by an installed first-party CLI/app | Carries provider-reported percentages and reset timestamps when the first-party tool exposes them. | Vendor credentials remain inside the first-party tool; Reset Radar imports only derived snapshots. Version and availability still vary. | Selected automatic path. |
| 2 | User enters the percentage shown by the vendor | Exact to the vendor's displayed rounding at that moment. | No credential or automated vendor access. | Diagnostic/emergency correction only, not the primary product path. |
| 3 | Official API response headers | Accurate for API request/token throughput limits. | Requires an API key and applies only to API traffic. | Future API-only mode, visibly separate from subscriptions. |
| 4 | Local logs and token counters | Useful activity signal, but incomplete and not equivalent to vendor weighting or account-wide usage. | Local and comparatively low risk. | Optional estimate only; never label it provider-reported allowance usage. |
| 5 | Consumer OAuth/cookie usage endpoint | Often exposes rich percentages and reset timestamps. | Existing tools describe these endpoints as undocumented, deprecated, throttled, or session-bound. Current consumer terms reject the proposed automated extraction absent permission. | Reject by default. |
| 6 | Embedded browser/DOM scraping | Reads the same display the user sees. | Requires broad session access and is fragile under UI/security changes. | Reject. |

### Claude consumer plans

Anthropic documents Settings > Usage as the place to inspect paid-plan usage and documents five-hour and weekly limits. Public first-party documentation does not provide a supported third-party consumer-usage API.

Claude Code has exposed `rate_limits` snapshots containing five-hour and seven-day `used_percentage` and `resets_at` values to status-line commands since 2.1.80. Its current early-access function-hook types normalize the same last-response state as `SessionRateLimit[]` with `kind`, `percentUsed`, and optional `resetsAt`. This is account-level cached state, not an independently queryable usage API. Public issues show that it can be absent after a release, stale across concurrent terminals, or limited to standard windows. The separate OAuth usage endpoint used by community tools is reported as throttled and is described by prior art as deprecated or undocumented. Therefore:

- The Mac source must prefer first-party structured CLI output over reading Keychain tokens or calling the OAuth endpoint itself.
- Every imported snapshot needs the originating Claude Code version and observation time.
- Missing output means unavailable, not zero usage.
- Preserve unknown window kinds, but do not promise per-model windows: the inspected current type documents account-level five-hour, seven-day, and gateway spend-limit kinds only.

### ChatGPT and Codex consumer plans

OpenAI's Codex repository defines structured rate-limit snapshots with `usedPercent`, `windowDurationMins`, and `resetsAt`, and its app-server protocol supports account rate-limit reads. The protocol can return multiple buckets keyed by limit ID, while individual windows may be absent. Public issues also document disagreements between usage surfaces and enforcement.

Therefore the Mac source should:

- Invoke the installed first-party Codex app-server instead of reading or copying its authentication files.
- Classify windows by their explicit duration and limit ID, never by “primary” or “secondary” position.
- Import, validate, clamp, and retain `usedPercent` without changing its orientation.
- Treat the backend's permission/reached state as distinct from the percentage; a value below 100% used is not proof that a new turn is allowed.
- Coalesce refreshes, apply backoff, and show stale data rather than poll aggressively.

This path applies to Codex/Work allowances exposed by Codex tooling. It is not evidence that every ChatGPT model or feature allowance is available through the same interface.

### Official APIs

OpenAI API responses can include request and token limits, remaining counts, and reset durations. Anthropic API responses can include request, combined-token, input-token, output-token, and reset headers; Anthropic rounds token remaining values to the nearest thousand and reports the most restrictive active token limit in the combined headers.

These values are rate-limit capacity for API organizations/projects, not consumer-plan percentage. If an API mode is later approved, normalize each independent dimension separately:

`remaining percent = remaining / limit * 100`

Never combine request and token dimensions into an average. The binding limit may change per request, model, workspace, or project.

## 4. Prior-art findings

The detailed repository inventory remains in [github-prior-art.md](github-prior-art.md). Usage-focused findings are:

- Mature trackers show five-hour and weekly values independently and classify windows by duration.
- Several explicitly calculate remaining as `100 - usedPercent`, clamp it, and show `N/A` when a source omits a window.
- Pace compares allowance consumed against time elapsed; it does not redefine the measured percentage.
- Useful history stores timestamped percentage observations and reset markers. It does not pretend that sparse samples form exact consumption accounting.
- Public issues report stale terminal snapshots, missing windows, endpoint throttling, false 100% readings, and contradictions between dashboard and enforcement.
- Polling each open terminal independently amplifies throttling. A future desktop collector needs one shared, bounded refresh loop.
- Whole-number provider percentages are rounded observations. Forecasts must state uncertainty and must not claim token-level precision.

## 5. Data-model consequences

Model a reset window separately from its usage observations:

- `LimitWindow`: identity, service, label, duration/recurrence, reset state, and source configuration.
- `UsageObservation`: window ID, used value, unit (`percent` initially), observed-at instant, source, confidence, and optional source metadata.
- `Availability`: current, stale, unavailable, reset-awaiting-refresh.
- `WindowCycle`: optional start/reset bounds used to prevent threshold alerts and observations from leaking into the next cycle.

Do not put `fiveHourUsed` and `weeklyUsed` fields directly on a service. Multiple weekly, per-model, monthly, and feature windows already exist, and sources can omit or add windows.

The owner excluded percentage history from the first version. Keep only the latest valid observation per window plus its source, observation time, and freshness or availability state. Percentages and timestamps are not account secrets, but they are still personal behavioral data and may move only through the conditionally approved transport after the validation in [mobile-network-synchronization.md](mobile-network-synchronization.md) passes.

## 6. Presentation requirements

Minimum window presentation:

- `70% used`
- `5-hour limit · resets in 2h 14m`
- `Updated on Mac 12 min ago · Codex`

For another simultaneous window:

- `20% used`
- `Weekly limit · resets Tue 09:00`

Use “used” consistently because that is the owner's selected mental model. Do not mix orientations between windows.

Color cannot carry state alone. Threshold color, text, symbols, and accessibility labels must agree. A widget should prioritize the highest-used fresh window, while still making other windows discoverable; stale or unavailable data must not appear as a healthy gauge.

## 7. Risks and experiments

Risks:

- Automatic snapshots can become stale when the Mac sleeps, a CLI is signed out, or a provider omits a window.
- Vendor percentages may be rounded or weighted by undisclosed model, cache, tool, or system factors.
- Multiple clients can show inconsistent snapshots during incidents or rollout changes.
- Automatic consumer access can violate terms and expand credential exposure.
- A percentage without a source and timestamp invites false precision.

Required experiments:

- Validate decoding, clamping, percentage orientation, staleness, missing-source, and reset-cycle transitions with deterministic fixtures.
- Define stale thresholds per source type without deleting the last known observation.
- Prototype compact two-window widget layouts using current, stale, missing, 0%, and 100% values.
- Verify that latest-observation replacement and reset invalidation cannot expose an old cycle as current data.

Required desktop-source experiments:

- Read Codex `account/rateLimits/read` through the installed app-server without opening authentication files.
- Capture Claude Code status-line `rate_limits` without calling its consumer OAuth endpoint.
- Confirm bounded refresh behavior, CLI version detection, source disappearance, multiple accounts, and offline recovery.
- Complete the transport validation checklist in [mobile-network-synchronization.md](mobile-network-synchronization.md).

## 8. Owner decisions

- Do not include threshold notifications in the first version.
- Retain only the latest valid percentage observation; do not include percentage history.
- Do not include pace labels or exhaustion forecasts.
- Ship the Mac collector and pairing flow with the first usable version; a reset-only iOS increment does not count as that release.
- Limit automatic coverage to Codex and Claude Code coding allowances.
- Conditionally approve the Cloudflare metadata boundary and one-authoritative-Mac design, subject to the required synthetic-data spike.
- Choose separate Codex and Claude stale thresholds from P1-M2 tests rather than assigning an arbitrary shared timeout.

The canonical rationale and constraints are in [Phase 1 owner decisions](../../phase-1/owner-decisions.md).

## Sources

Checked 2026-10-19:

- [Anthropic API rate limits](https://platform.claude.com/docs/en/api/rate-limits): API request/token limits, remaining values, and reset headers.
- [Claude paid-plan usage](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans): Settings > Usage and five-hour/weekly consumer windows.
- [Claude Code status-line freshness issue](https://github.com/anthropics/claude-code/issues/75408): observed `rate_limits` shape and stale concurrent-session snapshots.
- [Claude OAuth usage throttling issue](https://github.com/anthropics/claude-code/issues/30930): observed endpoint throttling and third-party dependence.
- [OpenAI API rate limits](https://developers.openai.com/api/docs/guides/rate-limits): API request/token limit, remaining, and reset headers.
- [OpenAI Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs): structured account rate-limit responses and multi-bucket state.
- [OpenAI Codex disagreement report](https://github.com/openai/codex/issues/23190): observed divergence between rate-limit reads and enforcement.
- [Codex Usage for Windows](https://github.com/VictorZakharov/codex-usage): remaining percentages, history, and forecast behavior.
- [Codex Usage Tray](https://github.com/Tooblippe/codex-usage): window classification, clamping, missing-data handling, and pace calculations.
- [Codex Usage and Resets](https://github.com/joelfarthing/codex-usage-and-resets): whole-percentage precision and conservative forecasting.
- [Automatic usage acquisition](automatic-usage-acquisition.md): recent repository code audit and selected provider/transport architecture.
- [Pinned upstream source audit](upstream-automatic-usage-sources.md): current Codex and Claude Code schemas, update triggers, and absence/freshness behavior.
- [Mobile-network synchronization](mobile-network-synchronization.md): cellular transport, privacy, cost, and background-delivery constraints.
