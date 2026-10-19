# GitHub prior art for AI usage reset tracking

Status: Active

GitHub-focused survey of open-source tools that display Claude, ChatGPT, or Codex usage windows and reset times. It records how repositories obtain reset data, what credentials they reuse, the platforms and licenses involved, and the failure patterns visible in public documentation and issues.

All repository metadata and linked material were checked on 2026-10-19. Stars, issue counts, and activity dates are a point-in-time snapshot, not quality scores.

## 1. Method

The GitHub repository search API was queried with the following strings, ordered by stars. The first 20 results of each query were screened and duplicate repositories were collapsed.

| Query | Results reported by GitHub | Search complete |
|---|---:|---|
| `claude usage tracker` | 1,910 | Yes |
| `codex usage tracker` | 729 | Yes |
| `chatgpt usage tracker` | 174 | Yes |
| `"usage limits" claude codex` | 497 | Yes |

A repository entered the direct-prior-art inventory when its current description or README explicitly covered at least one of these:

- Consumer or coding-agent quota windows.
- A percentage used or remaining.
- A reset timestamp or countdown.
- An alert tied to a quota or reset.

Token-cost ledgers, prompt counters, session analytics, account rotators, and proxy dashboards were screened but placed in the adjacent-tools list when reset tracking was not their primary promise.

For each direct repository, the default-branch README and any linked provider documentation were read. Recent public issues were sampled for repositories with issue activity. No repository was installed, executed, or given credentials.

Evidence labels:

- `[repository]` — stated by the repository README, provider documentation, license, or GitHub metadata.
- `[issue]` — reported in a public GitHub issue; it was not independently reproduced.
- `[inferred — confidence: …]` — synthesis from the repository evidence.

## 2. Direct prior art inventory

The “activity” column reports stars and the most recent repository push returned by GitHub on the check date. It is a maintenance signal only; issue comments and metadata changes do not necessarily update the push date.

| Repository | Platform and product shape | Reset-time source and credential model | License | Activity |
|---|---|---|---|---|
| [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) | `[repository]` Native macOS menu-bar app for Claude and Codex; shows five-hour, weekly, model-specific, extra-usage, cost, history, and notifications. | `[repository]` Reads Claude Code OAuth credentials, can extract or accept a Claude web `sessionKey`, and reads `~/.codex/auth.json`. Credentials are stored in Keychain; Claude and Codex usage endpoints supply reset timestamps. | MIT | 3,670 stars; pushed 2026-08-31. |
| [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude) | `[repository]` macOS menu-bar app for Claude and Codex; used/remaining display, pace graphs, threshold/reset notifications. | `[repository]` System-browser sign-in or manual Claude session key plus Codex sign-in token; calls undocumented usage endpoints and stores credentials in Keychain. The README explicitly says this prevents App Store distribution. | MIT | 409 stars; pushed 2026-09-29. |
| [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) | `[repository]` macOS menu-bar/notch app covering Claude, Codex, and many other coding services; multi-account and extension support. | `[repository]` Claude mode invokes `claude /usage` or uses the Claude login OAuth credential against the usage API. Codex mode invokes app-server/`/status` or reads OAuth tokens from `~/.codex/auth.json` and calls the ChatGPT usage endpoint. | Apache-2.0 | 1,546 stars; pushed 2026-10-18. |
| [vinzdg/codenotch](https://github.com/vinzdg/codenotch) | `[repository]` macOS edge/notch display with a Windows port and iOS/Android companion; many providers and multiple profiles. | `[repository]` Prefers provider apps, CLIs, local databases, or language-server RPC, then reuses local OAuth/session credentials against quota endpoints. The phone companion receives only derived display state from the desktop. | MIT | 2,857 stars; pushed 2026-10-14. |
| [AThevon/TokenEater](https://github.com/AThevon/TokenEater) | `[repository]` Native macOS app and widgets for Claude/Codex quota windows plus local session history. | `[repository]` Reads Claude Code's OAuth token from Keychain for `/api/oauth/usage`; reads Codex CLI auth for `chatgpt.com/backend-api/wham/usage`. Widgets consume credential-free local JSON snapshots. | MIT | 516 stars; pushed 2026-10-18. |
| [Iamshankhadeep/ccseva](https://github.com/Iamshankhadeep/ccseva) | `[repository]` Native macOS menu-bar app for Claude Code; server-truth gauges plus local token/cost history and estimates. | `[repository]` Parses `~/.claude` transcripts locally and reads the Claude Code OAuth usage endpoint for five-hour and weekly utilization, falling back to local estimation. | MIT | 806 stars; pushed 2026-08-03. |
| [CodeZeno/Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor) | `[repository]` Windows taskbar widget for Claude, Codex, Cursor, and other providers. | `[repository]` Detects CLI, desktop, WSL, credential-manager, and local auth-file sessions and sends read-only usage requests directly to provider services. It has no backend or telemetry. | MIT | 623 stars; pushed 2026-10-16. |
| [sysrootix/check-usage](https://github.com/sysrootix/check-usage) | `[repository]` Native macOS edge pill and menu-bar app for several AI coding services; reset countdown and pace card. | `[repository]` Reads Claude Code Keychain OAuth, Codex auth JSON/Keychain, and other providers' local sessions or API keys. It calls provider-specific quota endpoints and never refreshes Claude/Codex tokens itself. | MIT | 50 stars; pushed 2026-09-16. |
| [Artzainnn/CodexUsageBar](https://github.com/Artzainnn/CodexUsageBar) | `[repository]` Minimal signed macOS menu-bar app for Codex session/weekly/model windows, credits, notifications, and OpenAI status. | `[repository]` Reads the existing Codex CLI sign-in from `~/.codex/auth.json`; no browser cookie or API key is requested. It calls OpenAI endpoints every five minutes. | MIT | 11 stars; pushed 2026-10-12. |
| [shanggqm/codexU](https://github.com/shanggqm/codexU) | `[repository]` macOS menu-bar/desktop app with a smaller Windows port; combines Codex quota windows with local token, task, and project analytics. | `[repository]` Reads Codex app-server/runtime data and local `~/.codex` session records; optional Claude analytics read local `~/.claude` data. | MIT | 357 stars; pushed 2026-10-16. |
| [nanvon/cc-bar](https://github.com/nanvon/cc-bar) | `[repository]` Native macOS menu-bar app for Codex, Claude Code, Cursor, Antigravity, and other tools; includes offline usage and cost analysis. | `[repository]` Reads Codex auth JSON and may refresh/write Codex tokens; reads Claude credentials strictly read-only from file or Keychain; calls quota endpoints and parses local logs. | MIT | 144 stars; pushed 2026-10-17. |
| [DevxD98/sessionsense](https://github.com/DevxD98/sessionsense) | `[repository]` Native Android app with live rings, reset planner, notifications, history, widgets, and up to three Claude/Codex accounts. | `[repository]` Uses in-app browser sign-in and retains the session cookies/tokens needed for the same undocumented web usage endpoints as the official sites. Secrets are encrypted with Android Keystore. | MIT | 6 stars; pushed 2026-10-05. |
| [TiantianFlow/ai-limits](https://github.com/TiantianFlow/ai-limits) | `[repository]` Chrome side-panel extension for 21 providers with used/left normalization, reset timing, history, and pace. | `[repository]` ChatGPT, Claude, and several peers use the signed-in browser session and private usage services; API providers use stored user keys. Provider host permissions are requested individually. | MIT | 13 stars; pushed 2026-10-18. |
| [cupcakedev/ai-usage-extension](https://github.com/cupcakedev/ai-usage-extension) | `[repository]` Chrome extension with popup, badge, and Claude-page overlay for Claude, Codex, Cursor, and other services. | `[repository]` Reads quota data through existing authenticated browser sessions, stores normalized snapshots locally, and refreshes on a configurable schedule. | MIT | 8 stars; pushed 2026-10-05. |
| [AyalX/codex-reset-tracker](https://github.com/AyalX/codex-reset-tracker) | `[repository]` Standard-library Python CLI for macOS, Linux, and Windows; focuses on Codex windows and expiring reset credits. | `[repository]` Reads `~/.codex/auth.json`, calls the read-only Codex usage and `/wham/rate-limit-reset-credits` endpoints, and deliberately never calls the credit-consumption endpoint. | MIT | 10 stars; pushed 2026-06-27. |
| [ericjypark/codex-island](https://github.com/ericjypark/codex-island) | `[repository]` Native macOS notch overlay for Claude and Codex quota windows, reset credits, local session activity, and cost. | `[repository]` Reads Codex auth JSON and Claude Code environment/Keychain/file credentials, then calls undocumented quota endpoints. It never writes or refreshes the credentials itself. | MIT | 358 stars; pushed 2026-10-13. |

## 3. Public issue and support evidence

These are problem signals, not measured defect rates. Larger or older projects naturally accumulate more issues.

| Repository | Public evidence | What it reveals |
|---|---|---|
| Claude Usage Tracker | `[issue]` [#325](https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues/325) reports organization-wide extra usage shown instead of member usage; [#322](https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues/322) reports cache expiry before a slow refresh finishes; [#335](https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues/335) reports inactive profiles going stale. | Provider semantics, caching, and multi-account refresh are separate correctness problems. |
| Usage4Claude | `[issue]` [#87](https://github.com/f-is-h/Usage4Claude/issues/87) reports ChatGPT Advanced Security breaking access; [#90](https://github.com/f-is-h/Usage4Claude/issues/90) reports duplicate refreshes causing HTTP 429; [#84](https://github.com/f-is-h/Usage4Claude/issues/84) reports connection failure despite a valid token. | A valid credential is not sufficient: scopes, security modes, throttling, and endpoint behavior change independently. |
| ClaudeBar | `[repository]` Provider docs warn that Claude's usage endpoint is heavily throttled, `/usage` hooks can time out, Codex fallback can omit reset timestamps, and keychain-only Codex auth is incompatible with API mode. | Supporting multiple acquisition paths creates a matrix of partial capabilities and failure states. |
| Codenotch | `[issue]` [#473](https://github.com/vinzdg/codenotch/issues/473) reports a second Claude/Codex profile becoming stale because its sign-in is not renewed; [#475](https://github.com/vinzdg/codenotch/issues/475) reports an obsolete auth source winning over a live one. | Credential precedence and refresh ownership become user-visible bugs in multi-account designs. |
| TokenEater | `[issue]` [#225](https://github.com/AThevon/TokenEater/issues/225) reports repeated Keychain access prompts; [#268](https://github.com/AThevon/TokenEater/issues/268) requests a hard connection reset. README troubleshooting covers rate-limited OAuth tokens and stale credentials. | Native credential reuse still needs recovery UI and careful Keychain identity/signing behavior. |
| CCSeva | `[issue]` [#27](https://github.com/Iamshankhadeep/ccseva/issues/27) reports an incorrect usage percentage and [#23](https://github.com/Iamshankhadeep/ccseva/issues/23) reports a false 100% Pro reading. | Local estimation and server data need explicit provenance and must never be silently mixed. |
| Claude Code Usage Monitor | `[issue]` [#155](https://github.com/CodeZeno/Claude-Code-Usage-Monitor/issues/155) reports taskbar-placement assumptions; [#159](https://github.com/CodeZeno/Claude-Code-Usage-Monitor/issues/159) reports an unreliable hover tooltip; [#167](https://github.com/CodeZeno/Claude-Code-Usage-Monitor/issues/167) reports dashboard stutter. | Glanceable surfaces have platform-specific layout and performance failure modes beyond data acquisition. |
| codexU | `[issue]` [#21](https://github.com/shanggqm/codexU/issues/21) reports a missing menu-bar item after a macOS update; [#36](https://github.com/shanggqm/codexU/issues/36) asks for predictive reset display. | OS updates affect status surfaces, while users value forecast information beyond a raw countdown. |
| SessionSense | `[issue]` [#1](https://github.com/DevxD98/sessionsense/issues/1) reports confusing login completion and [#2](https://github.com/DevxD98/sessionsense/issues/2) reports widget sizing/empty space; README troubleshooting notes Android battery optimization can stop background work. | Mobile adds login-state clarity, widget layouts, and system background policy to the support burden. |
| AI Limits | `[issue]` [#9](https://github.com/TiantianFlow/ai-limits/issues/9) reports a provider request returning a 403 HTML security page after injected page logic failed. | Browser-session access remains vulnerable to security challenges even without DOM scraping. |
| CodexIsland | `[repository]` README support notes say Anthropic aggressively rate-limits the OAuth endpoint and both provider endpoints will probably break because they are undocumented. | Mature implementations explicitly budget for stale data and endpoint replacement. |

## 4. Adjacent repositories screened out of the direct inventory

| Repository | Why it is adjacent rather than direct prior art |
|---|---|
| [getagentseal/codeburn](https://github.com/getagentseal/codeburn) | Primarily local token and cost analytics across many coding tools, not a consumer reset-time product. |
| [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) | Terminal token accounting and leaderboard rather than quota-window acquisition. |
| [Javis603/token-monitor](https://github.com/Javis603/token-monitor) | Broad desktop token/cost/session monitor; quota limits are part of a much larger local analytics product. |
| [xiufengsun/TokenTracker](https://github.com/xiufengsun/TokenTracker) | Multi-tool local token and cost tracker whose primary promise is usage accounting rather than reset reminders. |
| [phuryn/claude-usage](https://github.com/phuryn/claude-usage) | Local Claude Code token/cost/session dashboard with a subscriber progress bar; useful for estimation patterns but not reset tracking alone. |
| [douglasmonsky/codex-usage-tracker](https://github.com/douglasmonsky/codex-usage-tracker) | MCP tools and dashboard for investigating Codex tokens, credits, costs, caching, and threads rather than a glanceable reset notifier. |
| [Soju06/codex-lb](https://github.com/Soju06/codex-lb) | Multi-account proxy/load balancer with tracking; account rotation materially differs from Reset Radar's product boundary. |
| [saaranshM/unsnooze](https://github.com/saaranshM/unsnooze) | Automation that resumes agent sessions after reset; it consumes reset timing but is not primarily a tracker. |

## 5. Architecture patterns

### Source pattern A: reuse CLI credentials and call a quota endpoint

- `[repository]` This is the dominant Claude Code and Codex pattern. Repositories read a Keychain item, `~/.claude/.credentials.json`, or `~/.codex/auth.json` and call the provider's internal usage endpoint.
- `[inferred — confidence: high]` It produces the richest and most accurate state while the endpoint and credential scope remain compatible.
- `[inferred — confidence: high]` It is unsuitable for Reset Radar's recommended first version because the endpoints are undocumented, the tokens are broad bearer credentials, and vendor consumer terms restrict automated access.

### Source pattern B: invoke the vendor CLI or its local RPC

- `[repository]` ClaudeBar and Codenotch can ask `claude /usage`, `codex app-server`, or `/status` rather than constructing every web request directly.
- `[inferred — confidence: high]` This reduces response-schema coupling but adds process launch cost, CLI-version coupling, timeouts, and incomplete fallbacks.
- `[inferred — confidence: high]` It is a desktop-only option and does not help a standalone iOS app.

### Source pattern C: use the signed-in browser session

- `[repository]` Browser extensions and SessionSense call provider web-session usage services through an already authenticated browser or embedded browser.
- `[inferred — confidence: high]` This makes onboarding approachable but expands host permissions, cookie/session handling, review risk, and bot/security-challenge exposure.

### Source pattern D: estimate from local logs

- `[repository]` CCSeva and several adjacent tools parse local Claude/Codex session logs for tokens, cost, or estimated windows.
- `[inferred — confidence: high]` Local logs preserve privacy and avoid provider calls, but cannot observe usage from other devices and can diverge from server enforcement.

### Source pattern E: mirror a desktop-derived snapshot to mobile

- `[repository]` Codenotch exposes a mobile companion that receives percentages, reset times, and session state without credentials.
- `[inferred — confidence: high]` This protects mobile from credentials but makes a desktop app, synchronization protocol, and stale-state model part of the product.

## 6. Product lessons for Reset Radar

- `[inferred — confidence: high]` The open-source market is heavily concentrated on macOS coding-agent users. In the screened direct set there was one Android app, two Chrome extensions, one cross-platform CLI, one Windows-first app, and no standalone native iOS repository.
- `[inferred — confidence: high]` No prominent direct repository in the screened results uses a purely manual, user-owned reset clock. That leaves room for a privacy-first iOS product whose accuracy boundary is explicit.
- `[inferred — confidence: high]` A reset record needs provenance and freshness: user-entered, computed from a rule, provider-reported, CLI-reported, or locally estimated. Prior art issues show that presenting mixed sources as one authoritative percentage causes confusion.
- `[inferred — confidence: high]` Multiple simultaneous windows are normal: five-hour, weekly, per-model, credits, extra usage, and promotional reset grants. The data model should not assume exactly two clocks.
- `[inferred — confidence: high]` Useful presentation patterns are used/remaining toggles, exact reset plus relative countdown, one notification per threshold/cycle, pace against elapsed time, stale/error badges, and compact widgets.
- `[inferred — confidence: high]` Credential recovery, token refresh ownership, provider throttling, and schema migration dominate automatic trackers' support cost. Avoiding those concerns is a material product advantage, not merely an implementation simplification.
- `[inferred — confidence: high]` Repository popularity does not validate App Store or vendor-terms compliance. Several projects explicitly distribute outside an app store or warn that their endpoints are unsupported.

### Usage-tracking addendum

The owner has now made percentage-used tracking a product requirement. The dedicated [usage-tracking study](usage-tracking.md) converts these prior-art observations into source, freshness, data-model, and presentation requirements.

- `[repository]` Codex Usage Tray classifies 300-minute and 10,080-minute windows by duration, calculates remaining as `100 - usedPercent`, clamps it to `0...100`, and shows `N/A` rather than substituting a stale missing window.
- `[repository]` Codex Usage and Resets treats whole-number percentages as bounded, rounded observations rather than exact consumption measurements.
- `[issue]` OpenAI Codex issue [#23190](https://github.com/openai/codex/issues/23190) records a structured rate-limit read disagreeing with actual enforcement; a displayed percentage cannot be the sole availability state.
- `[issue]` Claude Code issue [#75408](https://github.com/anthropics/claude-code/issues/75408) records different usage snapshots across concurrent terminals because values reflected different last-observation times.
- `[inferred — confidence: high]` Reset Radar must store observations independently from reset rules, preserve observation timestamps and sources, and represent stale, missing, and enforcement-blocked states without inventing values.

### Recent automatic-acquisition audit

After the owner required automatic percentages, the most recent relevant implementations were inspected at code level. Full findings and source links are in [automatic-usage-acquisition.md](automatic-usage-acquisition.md).

The first-party `openai/codex` and `anthropics/claude-code` repositories are treated as protocol evidence rather than community prior art. Their pinned schema and refresh findings are in [upstream-automatic-usage-sources.md](upstream-automatic-usage-sources.md).

| Repository | Pushed | Automatic percentage path | Decision |
|---|---|---|---|
| ClaudeBar | 2026-10-18 | Multiple adapters: Claude CLI/OAuth paths and Codex app-server/token-backed fallbacks. | Learn from its adapter architecture, but keep Reset Radar's source policy narrower. |
| codexU | 2026-10-16 | Codex app-server plus an optional Claude Code status-line snapshot, with stale handling. | Closest two-provider match to the selected sources. |
| Claude Monitor | 2026-10-04 | Codex app-server; direct Claude OAuth endpoint; Bonjour/plain-HTTP Mac-to-iOS bridge. | Keep the Mac/iOS shape and Codex source; reject token mutation, private Claude access, and unauthenticated transport. |
| CodexMeter | 2026-08-26 | Long-lived Codex app-server helpers using `account/rateLimits/read` and update notifications. | Primary Codex implementation reference. |
| Claude Rate Monitor | 2026-08-11 | Claude Code status-line JSON written to a local file and expired after a stale threshold. | Primary credential-free Claude implementation reference; no code reuse until its license is confirmed. |

`[inferred — confidence: high]` The recent code supports a Mac-collector architecture: let installed first-party tools own authentication, normalize only percentage/reset snapshots, and synchronize those derived values to mobile. No recent implementation justifies putting consumer credentials in the iOS app.

## 7. Recheck triggers

Repeat the targeted search before implementation freezes the provider sources or before store submission if any of these occur:

- A vendor publishes a supported consumer usage or delegated-authorization API.
- A native iOS open-source tracker becomes prominent.
- Apple changes App Review rules for third-party services or credential handling.
- A vendor changes the selected Codex app-server or Claude Code status-line source.
- A shortlisted implementation is considered for code reuse or dependency adoption; verify its complete license and dependency notices at that time.
