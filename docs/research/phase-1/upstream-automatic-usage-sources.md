# Upstream automatic usage sources

Status: Active

Inspection of the current `openai/codex` and `anthropics/claude-code` repositories for automatic allowance percentages and reset instants. The result pins what each first-party tool actually exposes, how fresh it can be, and how Reset Radar must normalize it without reading provider credentials.

Sources were checked on 2026-10-19. The inspected revisions were OpenAI Codex [`70b3bb6`](https://github.com/openai/codex/tree/70b3bb6d8814ab3f2045238b4ae14c43da99783b) and Claude Code [`ef7bfdc`](https://github.com/anthropics/claude-code/tree/ef7bfdca55d906929fe6b782025b93758c325074).

## 1. Result

Both repositories contain first-party, machine-readable usage percentages and reset timestamps, but they are not equivalent sources.

| Property | OpenAI Codex | Claude Code |
|---|---|---|
| Acquisition | Query `codex app-server` with `account/rateLimits/read`; also observe sparse `account/rateLimits/updated` notifications. | Receive `rate_limits` in a configured status-line command after Claude Code has provider state. The current early-access function-hook API exposes the same last-response state as `SessionUsage.rateLimits`. |
| Used percentage | Integer `usedPercent` after the app-server rounds the core value. | Classic status line: `used_percentage`; current function-hook type: `percentUsed`, with at most one decimal. |
| Reset | Optional Unix-seconds `resetsAt`. | Optional ISO 8601 `resetsAt` in the current typed interface; the classic status-line field is `resets_at`. |
| Windows | Optional primary and secondary windows in one or more limit-ID buckets; duration is explicit when available. | Account-level `five_hour`, `seven_day`, and possibly gateway `spend_limit`; an empty collection means no reading. |
| Freshness model | Active read plus turn-derived push updates. | Cached from the last API response; automatic and event-driven, but not independently queryable by Reset Radar. |
| Credential ownership | The running first-party app-server owns the existing Codex sign-in. | The running first-party Claude Code process owns the existing sign-in. A status-line adapter receives only derived data. |

Keep the provider's clamped used value as the stored and presented fact. Do not invert it for presentation. A reset timestamp ending an old window invalidates that observation; it does not prove that the new window is at 0% used.

## 2. OpenAI Codex

### Protocol

The app-server registers [`account/rateLimits/read`](https://github.com/openai/codex/blob/70b3bb6d8814ab3f2045238b4ae14c43da99783b/codex-rs/app-server-protocol/src/protocol/common.rs#L1341) as a request returning `GetAccountRateLimitsResponse`. The response contains:

- `rateLimits`, the backward-compatible single-bucket snapshot;
- optional `rateLimitsByLimitId`, keyed by a metered limit ID such as `codex`;
- optional `ordinaryUsageAllowed`, which the source explicitly says must not be inferred from percentages or reset times;
- optional account ID, reset-credit summary, and upsell data.

Each [`RateLimitSnapshot`](https://github.com/openai/codex/blob/70b3bb6d8814ab3f2045238b4ae14c43da99783b/codex-rs/app-server-protocol/src/protocol/v2/account.rs#L664) may have `primary` and `secondary` windows plus limit identity, plan, credit, spend-control, and reached-state metadata. A [`RateLimitWindow`](https://github.com/openai/codex/blob/70b3bb6d8814ab3f2045238b4ae14c43da99783b/codex-rs/app-server-protocol/src/protocol/v2/account.rs#L752) carries:

- required integer `usedPercent`;
- optional `windowDurationMins`;
- optional Unix-seconds `resetsAt`.

The wire format is camel case. The app-server rounds the core floating-point used percentage to an integer, so Reset Radar must not present false decimal precision.

### Updates and reset behavior

The app-server registers [`account/rateLimits/updated`](https://github.com/openai/codex/blob/70b3bb6d8814ab3f2045238b4ae14c43da99783b/codex-rs/app-server-protocol/src/protocol/common.rs#L2020). Its payload is intentionally sparse: source comments say clients should merge available values into the most recent read or refetch. The server emits it when a token-count event contains rate-limit state, so it is a useful acceleration path after Codex activity, not a replacement for reads.

Reset Radar should therefore:

1. perform the required app-server initialization handshake;
2. read once on connection and on explicit refresh;
3. retain all limit-ID buckets and classify known clocks by duration, not by primary/secondary position;
4. refetch after a rate-limit update notification rather than treating its sparse payload as a complete account snapshot;
5. use bounded polling with coalescing and backoff while the Mac collector is active;
6. expire a window at `resetsAt` and request a fresh read instead of synthesizing a replenished percentage.

Missing duration or reset means unknown, not a default five-hour or weekly clock. `ordinaryUsageAllowed`, reached state, and spend-control state remain separate from the gauge.

## 3. Claude Code

### Two related interfaces

Claude Code 2.1.80 added `rate_limits` to classic status-line command input with five-hour and seven-day `used_percentage` and `resets_at` fields. The current changelog still names that snake-case surface and records later fixes, including clearing pre-reset values after a window reset while a session is idle. This is the practical credential-free export path because a status-line command is an external program that can atomically write a small snapshot for the Mac collector.

The current repository also publishes an early-access function-hook type surface. [`SessionUsage`](https://github.com/anthropics/claude-code/blob/ef7bfdca55d906929fe6b782025b93758c325074/mods/types/claude-code.d.ts#L9421) contains `rateLimits: SessionRateLimit[]`. Each [`SessionRateLimit`](https://github.com/anthropics/claude-code/blob/ef7bfdca55d906929fe6b782025b93758c325074/mods/types/claude-code.d.ts#L9207) has:

- `kind`, documented as `five_hour`, `seven_day`, or gateway `spend_limit`;
- `percentUsed`, from 0 to 100 with at most one decimal for normal windows;
- optional ISO 8601 `resetsAt`.

The typed array is the current semantic model; it does not mean the classic status-line JSON changed from its documented snake-case `rate_limits` object. A versioned adapter must decode its actual input version and normalize both to one internal representation.

### Freshness and update triggers

The source documentation is explicit that `SessionUsage.rateLimits` contains windows from the **last API response** and is empty off a subscription or before the first reading. It is account-level state, not evidence of per-model windows.

The classic [status-line documentation](https://code.claude.com/docs/en/statusline#when-the-status-line-updates)
lists session start, a new assistant message, compaction, permission-mode and Vim-mode changes,
command changes, optional `refreshInterval`, and reported reset/cache-expiry times as update
triggers. It does not list terminal resize. Calibration may add a bounded timer to its isolated
temporary settings to observe unchanged idle input; production still never creates a Claude turn
or treats a timer rerun as a fresh provider observation.

The early-access [`session.measure`](https://github.com/anthropics/claude-code/blob/ef7bfdca55d906929fe6b782025b93758c325074/mods/types/claude-code.d.ts#L9132) event fires after main-thread turns and when a rate-limit window moves a whole percentage point. Its `changed` list marks a window moving a whole point, appearing, leaving, or changing account-limit status. This confirms Claude Code maintains a push-oriented measurement cache.

That function-hook API is not the selected export mechanism yet. Its generated declaration labels it early access, says it may change without notice, and runs hooks without Node, DOM, or direct filesystem APIs. Prototype it only if an approved engine operation can export the snapshot without broadening permissions. Until then, the classic status-line command remains the narrower external bridge.

Reset Radar should therefore:

1. preserve any existing user status-line behavior and install only with explicit consent;
2. accept known `rate_limits` windows, preserve unknown kinds, and record the Claude Code version and observation time;
3. treat an empty or missing set as unavailable rather than zero used;
4. mark the snapshot stale independently of the reset countdown;
5. invalidate an old observation at its reset instant and wait for a fresh first-party observation;
6. never generate a Claude turn just to refresh usage;
7. never fall back to Claude Code credentials or a private consumer usage endpoint.

Usage on another device can remain invisible until this Claude Code process receives new provider state. The UI must say “last reported by Claude Code,” not “live account usage.”

## 4. Normalized snapshot

The upstream findings require a versioned, open-ended model rather than fixed five-hour and weekly properties:

| Field | Rule |
|---|---|
| `provider` | `codex` or `claude-code`. |
| `sourceKind` | `codex-app-server` or `claude-status-line`. |
| `sourceVersion` | Installed CLI/app-server version used to decode the payload. |
| `accountScope` | Opaque local discriminator when first-party output supplies one; never an email or credential. |
| `limitID` | Codex limit ID or Claude window kind; preserve unknown values. |
| `usedPercent` | Provider-reported numeric value after validation. |
| `durationMinutes` | Optional; never infer from array position. |
| `resetsAt` | Optional absolute instant parsed from Unix seconds or ISO 8601. |
| `observedAt` | Time the first-party source supplied or Reset Radar received the observation, kept distinct from device receive time. |
| `availability` | Fresh, stale, expired, unavailable, signed out, incompatible, or source offline. |
| `permissionState` | Separate optional state such as Codex `ordinaryUsageAllowed`; never derived from percentage. |

Deduplicate by provider, account scope, and limit ID. Preserve multiple buckets and unknown windows so upstream additions do not overwrite existing clocks.

## 5. Fixture and compatibility requirements

Compatibility tests should pin representative fixtures without real accounts:

- Codex single-bucket response, multi-bucket response, sparse update, missing reset, missing duration, signed-out/error response, and `ordinaryUsageAllowed: false` with a non-100 percentage.
- Claude classic status-line five-hour/seven-day object, missing `resets_at`, empty `rate_limits`, unknown window, malformed percentage, and a legacy/current schema discriminator.
- Boundary values below zero, above 100, fractional Claude percentages, expired resets, and clocks far in the future.
- CLI upgrade tests that reject incompatible payloads while retaining the last valid snapshot as stale.

Live smoke tests require owner approval because they exercise real signed-in first-party tools. They must verify source versions and field shapes without logging raw account data.

## 6. Consequences for Reset Radar

- Automatic percentage support is feasible for the coding allowances these tools expose; it is not proof of coverage for every ChatGPT or Claude web/mobile feature.
- Codex can be actively refreshed by the collector. Claude is last-response data and must be presented with stricter freshness language.
- The Mac collector remains required. The first-version iPhone and watchOS clients receive normalized, credential-free snapshots only, with watchOS receiving them through its paired iPhone.
- Provider schema changes are expected. Decoder compatibility and visible source status are product features, not internal details.
- No upstream repository evidence justifies reading authentication files, copying OAuth tokens, or calling private consumer endpoints.

## Sources

- [OpenAI Codex app-server account protocol](https://github.com/openai/codex/blob/70b3bb6d8814ab3f2045238b4ae14c43da99783b/codex-rs/app-server-protocol/src/protocol/v2/account.rs)
- [OpenAI Codex method and notification registry](https://github.com/openai/codex/blob/70b3bb6d8814ab3f2045238b4ae14c43da99783b/codex-rs/app-server-protocol/src/protocol/common.rs)
- [OpenAI Codex rate-limit notification emission](https://github.com/openai/codex/blob/70b3bb6d8814ab3f2045238b4ae14c43da99783b/codex-rs/app-server/src/bespoke_event_handling.rs#L1597)
- [Claude Code generated function-hook types](https://github.com/anthropics/claude-code/blob/ef7bfdca55d906929fe6b782025b93758c325074/mods/types/claude-code.d.ts)
- [Claude Code mods documentation](https://github.com/anthropics/claude-code/blob/ef7bfdca55d906929fe6b782025b93758c325074/mods/README.md)
- [Claude Code changelog](https://github.com/anthropics/claude-code/blob/ef7bfdca55d906929fe6b782025b93758c325074/CHANGELOG.md): status-line `rate_limits` introduction in 2.1.80 and subsequent reset/freshness fixes.
