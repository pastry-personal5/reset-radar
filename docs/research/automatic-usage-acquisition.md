# Automatic usage acquisition

Status: Active

Code-level audit of recent GitHub projects that automatically obtain Claude Code and Codex allowance percentages. It selects a credential-minimizing source for each provider and defines the boundary between a future non-notarized macOS collector and the iPhone/watchOS presentation apps.

Repositories, code, and metadata were checked on 2026-10-19. No project was installed or given account access.

The two first-party repositories are pinned and analyzed separately in [upstream-automatic-usage-sources.md](upstream-automatic-usage-sources.md). That audit is authoritative when an upstream schema detail differs from older prior art.

## 1. Decision

Supported coding-allowance percentages and reset instants must update automatically. Manual percentage entry and manual reset rules are excluded. The selected sources do not cover every general ChatGPT or Claude web/mobile allowance.

The recommended acquisition architecture is a Mac collector with provider-specific adapters:

- **Codex:** launch the user's installed `codex app-server`, complete its local initialization handshake, and call `account/rateLimits/read`. Codex owns sign-in and token refresh; Reset Radar never reads `~/.codex/auth.json` or Keychain credentials.
- **Claude Code:** install or generate a minimal Claude Code status-line adapter that atomically writes the `rate_limits` fields Claude Code supplies after a response. Reset Radar reads only that derived snapshot; it does not read Claude Code's Keychain item or call `/api/oauth/usage`.
- **iPhone:** receive normalized, credential-free snapshots from the paired Mac, cache them locally, and drive widgets, notifications, and App Intents from the cache.
- **watchOS:** receive the same normalized model through the iPhone companion in the first version, without provider credentials or direct provider networking.

This makes automatic tracking dependent on a signed-in first-party CLI and a Mac for consumer-plan percentages. If the Mac or CLI is unavailable, show stale/unavailable state; do not silently fall back to private endpoints or fabricated estimates.

## 2. Search and selection method

The existing [GitHub prior-art study](github-prior-art.md) was rechecked for repositories with recent activity and an explicit percentage source. Targeted GitHub code/web searches included:

- `account/rateLimits/read usedPercent usage tracker`
- `rate_limits five_hour percentUsed Claude Code usage`
- `macOS Claude Codex usage monitor rate limits`
- `iOS Claude Codex usage tracker percentage`

Candidate source files were read when the README alone did not establish credential ownership, protocol behavior, or mobile transport. Repository push dates below come from the GitHub repository API on 2026-10-19.

## 3. Recent implementation audit

| Repository | Recent activity | What it actually does | Lesson for Reset Radar |
|---|---|---|---|
| [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) | Pushed 2026-10-18; Apache-2.0 | A modular macOS provider system. Claude can use `/usage`-style CLI acquisition or OAuth usage access; Codex can use app-server/status paths or token-backed fallback paths. | Provider adapters and partial-capability states are useful; do not inherit broad fallback behavior that crosses the credential boundary. |
| [shanggqm/codexU](https://github.com/shanggqm/codexU) | Pushed 2026-10-16; MIT | Starts Codex app-server and calls `account/rateLimits/read`; classifies windows by duration. Claude active quota can be imported from a status-line snapshot, with old snapshots marked stale. | Closest match to the selected two-provider source strategy. |
| [cliq/claude-monitor](https://github.com/cliq/claude-monitor) | Pushed 2026-10-04; MIT | Codex uses a short-lived app-server process and never reads Codex credentials. Claude reads and refreshes Claude Code OAuth credentials, then calls the undocumented usage endpoint. Its iOS target discovers the Mac through Bonjour and polls JSON over a LAN HTTP bridge. | Reuse the Codex and derived-snapshot concepts, but reject direct Claude credential mutation and unauthenticated LAN HTTP. |
| [LAwLi3tCoding/CodexMeter](https://github.com/LAwLi3tCoding/CodexMeter) | Pushed 2026-08-26; MIT | Runs isolated long-lived Codex app-server helpers; reads `account/rateLimits/read`, `account/rateLimits/updated`, and separate usage history. Converts `usedPercent` to clamped remaining percentage. | Strongest code-level Codex reference: narrow decoding, provider-owned auth, independent failures, and explicit missing-field handling. |
| [hulryung/claude-rate-monitor](https://github.com/hulryung/claude-rate-monitor) | Pushed 2026-08-11; license not identified by GitHub API | A Claude Code status-line command writes five-hour/seven-day percentages and reset timestamps to a file. The app rejects malformed/future snapshots and treats data older than one hour as absent. A legacy Keychain/OAuth path is off by default. | Strongest credential-free Claude reference. Copy the source strategy, not code, until licensing is confirmed. |

### Closest end-to-end precedent

`cliq/claude-monitor` already contains macOS, iOS, iOS-widget, and Mac-widget targets. Its Mac advertises `_claudemonitor._tcp` over Bonjour, exposes cached snapshots from `/panel` or `/usage`, and its iOS app polls every 30 seconds while preserving the Mac's original observation timestamp.

That validates the product shape but not the security design. The examined bridge listens on all interfaces and returns snapshot JSON over plain HTTP without an authentication check. Reset Radar must require explicit pairing, authenticate every message, and provide confidentiality and replay protection before it exposes behavioral data on a LAN.

## 4. Provider algorithms

### Codex

1. Locate a compatible installed Codex executable.
2. Launch `codex app-server --listen stdio://` as a child process with the user's existing Codex environment.
3. Send `initialize`, including a stable Reset Radar client name/version and the required capabilities; then send `initialized`.
4. Call `account/rateLimits/read` on a bounded interval and after relevant update notifications.
5. Decode both the backward-compatible `rateLimits` bucket and `rateLimitsByLimitId` when present.
6. For each non-null window, retain `limitId`, `limitName`, `usedPercent`, `windowDurationMins`, `resetsAt`, plan/reached state, and observation time.
7. Accept `usedPercent` only in `0...100` and retain it without clamping or changing its orientation.
8. Classify 300-minute and 10,080-minute windows by duration, never by `primary`/`secondary` position. Preserve unknown durations as additional windows.
9. Treat `ordinaryUsageAllowed` and reached/spend states separately from the percentage.
10. On timeout, process exit, incompatible method, missing window, or sign-out, retain the last observation only as stale and show an actionable status.

Do not read, copy, log, refresh, or synchronize Codex credentials. Do not call the private ChatGPT usage endpoint directly when app-server is unavailable.

### Claude Code

1. Configure a minimal status-line adapter without replacing unrelated user status-line behavior.
2. Decode the classic snake-case `rate_limits` status-line payload for the installed Claude Code version. Normalize its five-hour and seven-day windows to the current typed semantics: `kind`, `percentUsed`, and optional `resetsAt`.
3. Write a versioned snapshot atomically with used percentage, reset timestamp, observation time, Claude Code version, and account/source identity when available.
4. Have the Mac collector watch or periodically read that snapshot.
5. Clamp percentage used after validation and publish it as provider-reported, last-response state.
6. Mark it stale 60 minutes after the last response-linked observation, as confirmed by the
   2026-10-25 owner-present source calibration. Reject timestamps materially in the future.
7. Treat absent windows as unavailable. Do not substitute local token estimates into the same gauge.

This source reflects Claude Code's last-response account state. The current early-access function-hook surface confirms that measurements are pushed after main-thread turns and whole-point rate-limit changes, but it is not the selected export path because it is unstable and has no direct Node/filesystem API. Usage from other devices may not appear until Claude Code next receives provider state.

Do not make the legacy Keychain plus `/api/oauth/usage` path a fallback. Recent projects document OAuth throttling, token-refresh races, Keychain ACL prompts, required impersonating user agents, and endpoint instability.

## 5. Desktop-to-mobile transport boundary

The normalized snapshot contains no provider credential but still reveals account usage patterns. The canonical transport comparison is in [mobile-network-synchronization.md](mobile-network-synchronization.md); the leading Worker plus Durable Object protocol, pairing, threat model, and required validation are in [cloudflare-synchronization.md](cloudflare-synchronization.md).

Provider acquisition and mobile transport remain separate trust boundaries. No transport may contain a provider token, CLI path, account email, prompt, response, project path, or raw local log content. Plain unauthenticated HTTP is not acceptable, including on a LAN or personal VPN.

## 6. Polling, storage, and presentation

- Use one Mac collector per provider installation and fan out cached snapshots to local surfaces. Do not let every widget/device poll a provider interface independently.
- Codex app-server polling should be bounded, coalesced, backed off on failure, and refreshed immediately on foreground/user request.
- Claude status-line data should be event-driven from existing Claude Code responses; Reset Radar must not create model turns merely to refresh usage.
- Store the current observation, not credentials, raw provider responses, or first-version percentage history.
- Preserve percentage precision internally; round only for presentation.
- Show “updated on Mac … ago,” provider/source, and stale/offline state on iPhone and watchOS.
- A predicted reset invalidates an old sample; it does not synthesize 0% used.

## 7. Architecture consequences

- Automatic consumer usage makes a macOS collector part of the required product architecture, not merely an optional display companion.
- The macOS app may remain non-notarized as previously directed, but code signing, Gatekeeper installation instructions, CLI process permissions, launch-at-login, and update safety still require explicit planning.
- The iOS app cannot fulfill the automatic-percentage promise when no paired Mac/first-party CLI source is available; it must present reset-only or stale/unavailable state honestly.
- The first-version watchOS app receives snapshots from iPhone and does not connect to the Mac or providers independently.
- The architecture must define provider adapters, the normalized snapshot, pairing and transport, staleness, and multi-device ownership boundaries before implementation.

## 8. Decisions and validation

- The Mac collector and pairing flow are required for the first usable release.
- The owner conditionally approved the Cloudflare transport threat model; complete its synthetic-data spike before final adoption or real usage.
- One Mac is authoritative in the first version.
- Choose refresh and stale thresholds separately for Codex polling and Claude last-response snapshots from P1-M2 test evidence.
- Validate current CLI versions and schema generation before implementation without accessing real credentials in tests; use fixtures for automated tests and an owner-approved live smoke test.

See [Phase 1 owner decisions](../phase-1/owner-decisions.md) for the binding scope.

## Sources

Checked 2026-10-19:

- [OpenAI Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs): rate-limit window and multi-bucket response types.
- [Claude Code repository](https://github.com/anthropics/claude-code): typed last-response rate-limit state exposed to session/status-line consumers.
- [Pinned upstream source audit](upstream-automatic-usage-sources.md): exact inspected revisions, schemas, update behavior, and compatibility rules for both first-party tools.
- [ClaudeBar](https://github.com/tddworks/ClaudeBar): recent modular multi-provider implementation.
- [codexU research](https://github.com/shanggqm/codexU/blob/main/RESEARCH.md): app-server classification and Claude status-line snapshot integration.
- [Claude Monitor Codex client](https://github.com/cliq/claude-monitor/blob/main/App/Core/Usage/CodexAppServerClient.swift): short-lived provider-owned-auth app-server query.
- [Claude Monitor Claude fetcher](https://github.com/cliq/claude-monitor/blob/main/App/Core/Usage/ClaudeUsageFetcher.swift): direct OAuth/private-endpoint approach rejected here.
- [Claude Monitor LAN bridge](https://github.com/cliq/claude-monitor/blob/main/App/Core/Usage/UsageBridgeServer.swift): Bonjour/HTTP mobile bridge and its security limitations.
- [CodexMeter quota research](https://github.com/LAwLi3tCoding/CodexMeter/blob/main/docs/research/codex-quota-data-source.md): narrow Codex source selection and credential boundary.
- [Claude Rate Monitor](https://github.com/hulryung/claude-rate-monitor): status-line snapshot, staleness, and legacy Keychain path comparison.
- [Mobile-network synchronization](mobile-network-synchronization.md): canonical transport requirements, cost comparison, and validation plan.
