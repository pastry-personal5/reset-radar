# Phase 1 changelog

Status: Active

Decisions and plan changes for Phase 1 that are not clear from commits.

## Entries

- 2026-10-22 — Owner/Codex — Made the source-calibration spike explicitly `codex-profile` aware for the owner's two-profile setup. Preparation now prompts privately for every selected profile, creates isolated ordinal launchers and reports, ignores ambient `CODEX_HOME` selection, and verifies every selected profile without retaining profile names or homes in project evidence. This calibration support does not decide simultaneous multi-account product behavior.
- 2026-10-22 — Owner — Chose XcodeGen with its specification as the source of truth and generated `ResetRadar.xcodeproj` output left untracked. Set bundle prefix `com.unidentifiedstealthstartup`, main-app identifier `com.unidentifiedstealthstartup.ResetRadar`, and App Group `group.com.unidentifiedstealthstartup.ResetRadar`. Retained the approved iPhone 17 Pro Max and iPad Air 11-inch (M2) simulator destinations and will install a compatible iOS 26.x runtime. Accepted the XcodeGen-based repository layout and promoted it from `Proposal` to `Active`.
- 2026-10-22 — Codex — Added a synthetic-only, owner-run Mac Keychain validation runbook. It creates an isolated signed harness with no production target, relay integration, or provider data; specifies non-interactive, rebuild, login-launch, locked-Keychain, lifetime, renewal, and profile observations; and includes cleanup and redacted evidence instructions. The validation result remains open.
- 2026-10-20 — Owner — Approved the system architecture and all module designs for promotion from `Proposal` to `Active`. Explicitly accepted the five follow-up security findings, including the residual Universal Clipboard and offline-Watch risks, before targeted verification. This approval freezes the design for scaffolding; it does not waive runtime, synthetic, physical-device, cost, or signing gates, and no real usage data may reach the relay until its required gate passes.
- 2026-10-20 — Codex — Responded to the follow-up architecture security review with a durable Watch-erasure receipt and local erase hold, explicit manual-pairing clipboard handling, bounded Codex and relay input, a fixed HTTPS relay origin with redirects rejected, and one documented running-process Keychain-lock behavior. At that point these remained proposed designs; the approval entry above supersedes their review status, while physical and synthetic validation remain open. See the [review response](../research/phase-1/spike-results.md#proposed-architecture-response).
- 2026-10-20 — Owner/Codex — Changed relay pairing activation to an explicit authenticated confirmation after the reader saves its Keychain and local state. The preflight read alone no longer activates a reader. Added a relay-assigned five-minute pending expiry, idempotent retry, staging recovery, and tests for local-save failure and expired registration.
- 2026-10-20 — Owner/Codex — Selected Mac-assisted manual refresh for iPhone and iPad in the first version, using short-lived authenticated relay requests and an encrypted result tied to the request. Also decided that a Home window absent from a provider report becomes unavailable after its last known reset passes, and that an existing Claude Code status-line command with possible inline secrets must be left untouched. Added protocol, capacity, latency, failure, and source-state verification requirements.
- 2026-10-20 — Owner/Codex — Requested an optional iPhone/iPad mode that fetches provider usage independently when selected, preferably through vendor-supported device login. The [official mobile access review](../research/phase-1/official-mobile-usage-access.md) found no documented, permitted native iOS path to the required personal subscription windows for either provider, so the Mac collector remains the first-version source. Reviewed architecture contracts for local-versus-relay sequence ownership, conditional reads after cache loss, in-flight fetch completion, Watch message ordering after re-pairing, Claude Code observation timing, widget-only notification updates, and the Mac instance lock; added focused verification cases.
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
