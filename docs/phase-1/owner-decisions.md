# Phase 1 owner decisions

Status: Active

This record captures the owner's decisions after reviewing the P1-M1 research results, subsequent
architecture choices, the 2026-10-24 P1-M10 account-model revision, and the 2026-10-26 through
2026-10-27 M15 scheduling reviews. These decisions constrain Phase 1 work; validation gates listed here remain
mandatory and are not implied to have passed.

## Product and security boundaries

| Research question | Owner decision | Consequence for P1-M2 |
|---|---|---|
| Q2: consumer credentials | Permanently exclude vendor passwords, browser session cookies, and consumer OAuth tokens. Reopening this boundary requires a new owner decision and written authorization from the relevant vendor. | Reset Radar must not request, read, copy, store, transmit, refresh, or log those credentials. It may store its own pairing, relay, and encryption secrets. |
| Q3: API-key mode | Do not include API-key support or reserve architecture for it. | API organization/project rate-limit headers are outside the product and source model. |
| Q5: manual reset rules | Remove manual percentage and reset-rule entry entirely. This supersedes the earlier blank-manual-ChatGPT decision. | The model stores only provider-reported observations and absolute reset instants; no recurrence editor, rule migration, or manual fallback exists. |
| Q6: identity | Keep the **Reset Radar** name and use a neutral original icon. Use service names only as descriptive interface text, without vendor logos, copied visual styling, or implied affiliation. | Bundle identity and assets must remain vendor-neutral. |
| Automatic coverage | Limit the product to coding allowances reported by Codex app-server and Claude Code. | The Mac adapters and product copy must distinguish coding allowances from general ChatGPT or Claude web/mobile usage. |

On 2026-10-20 the owner requested an optional independent iPhone/iPad source, preferably using vendor-supported device login. This is a conditional research direction, not authorization to copy a Mac session or use an undocumented provider endpoint. The [official mobile access review](../research/official-mobile-usage-access.md) found no currently documented, permitted native client path to the required personal subscription percentages and reset instants for either provider. The Mac collector remains the first-version source until a provider-specific entry gate and owner decision are complete.

## First-version behavior

- The Mac collector and pairing flow must ship with the first usable version. A reset-only iOS increment does not count as the first release.
- Include Live Activities for eligible short windows such as a five-hour window. Weekly windows remain app and widget content. Activation, update, expiration, and stale-state behavior require an ActivityKit spike before implementation is frozen.
- Include an Apple Watch app in the first version. It receives the normalized, credential-free model through its paired iPhone, shows reset times, latest usage, source, and freshness, and does not connect directly to provider services or hold provider credentials.
- For P1-M16, validate initial free-signed Watch installation and WatchConnectivity on the reference iPhone and paired Watch. The owner placed the full seven-day Sideloadly refresh observation after M16 closure, as a Phase 1 exit criterion; it still must prove preservation before Phase 1 is marked done. This 2026-10-26 scheduling choice does not approve another distribution method or make an early re-sign equivalent to a full cycle.
- Use an account-scoped Home model. iPhone has a vertically scrolling Account List with one compact
  row and two standard Allowance Rings per account. iPad and Mac use split Account List/Account
  Details layouts. Watch uses an N-by-two ring matrix with aliases available in accessibility and
  details rather than visibly on Watch Home. Stable pastel Account Palettes use lavender for
  Account #1, mint for Account #2, and peach for Account #3, with appearance-aware,
  contrast-compliant foregrounds. They distinguish Watch rows without encoding usage or source
  state. This supersedes the fixed two-by-two Allowance Grid.
- Display provider-reported percentage used, from 0% toward 100%; do not invert it into percentage remaining.
- Do not include percentage threshold alerts, percentage history, pace labels, or exhaustion forecasts. Retain only the latest valid observation and its source, observation time, and freshness or availability state.
- Always display reset dates and times using the OS's current local time zone.
- Make reset notifications per-account-window opt-in. Make eligible five-hour Live Activities
  user-started from Account Details.

## Time-zone and scheduling semantics

- Store provider-reported resets as absolute instants.
- When the OS time zone changes, re-render reset dates locally without changing the stored instant.
- Maintain at most one pending reset notification for each configured account window. Replace or
  cancel it when the provider reset changes, disappears, expires, or the account is removed.

On 2026-10-26 the owner confirmed that per-window reset notifications on iPhone, iPad, and Mac
cover every valid provider-reported window, including additional Account Details limits. Small
Home Screen and Lock Screen widgets and the read-only App Intent likewise allow any valid window;
the Lock Screen widget uses only the rectangular accessory family, and the medium Home Screen
widget keeps the two standard windows for one account. A saved choice for
an additional window follows its exact `WindowID`: if it disappears, its notification is canceled
and its widget and App Intent result are unavailable; if the same ID returns, the choice resumes.
A changed ID never inherits the choice. A five-hour Live Activity whose reading becomes stale
before its known reset keeps showing the stale state until that reset unless the owner removes it
or its observation becomes invalid for another reason. It ends when the app next executes at or
after the reset; ActivityKit's eight-hour active-lifetime limit is the fallback when the app
does not run. Background execution is not guaranteed. These choices resolve the M15 all-window
and stale-lifecycle questions without changing the standard Home rings, medium widget, Watch
complication, or Live Activity eligibility.

On 2026-10-27 the owner chose the default notification sound and foreground banners for reset
notifications on iPhone, iPad, and Mac. A provisional authorization remains quiet; the app does
not override the system's provisional-delivery behavior.

On 2026-10-27 the owner chose a 30-minute routine WidgetKit reload request interval. Timelines
still contain known stale, reset, and invalidation transitions; the interval is an earliest
request only, and the system may delay or omit execution.

On 2026-10-27 the owner required a fresh observation to start a Reset Live Activity. A reset more
than eight hours after start is ineligible; if an update moves a running activity's reset beyond
its `startedAt + 8 hours` horizon, the app ends it immediately. When several activities run, the
soonest reset receives highest Dynamic Island relevance, with stable global account number as the
tie-breaker. The owner also approved linking the existing local `ResetRadarScheduling` product
into the Mac target and adding direct `ResetRadarDomain` and `ResetRadarApplication` dependencies
to `ResetRadarSchedulingTests`; no external dependency is approved.

## Synchronization and freshness

- Conditionally approve an owner-deployed Cloudflare Worker plus SQLite-backed Durable Object on `workers.dev` as the primary cellular transport.
- Cloudflare may hold only application-encrypted snapshots and minimal protocol metadata; it must never receive provider credentials, plaintext usage data, or the content key. The owner accepts that Cloudflare can observe transport metadata such as IP address, request time, route, size, and status.
- Limit the first version to one authoritative publishing Mac. Allow up to three paired iPhones or iPads, each with its own revocable read token and the shared content key; there is no in-place key rotation, and suspected compromise means destroy and re-pair.
- Use foreground and manual refresh plus opportunistic background refresh. Do not reserve an APNs or dependable push-update architecture in the first version. Widgets and Live Activities must show stale state honestly when updates are delayed.
- Choose separate Codex and Claude refresh and stale thresholds from P1-M2 source-specific tests. Always show observation time, and invalidate an observation after its reported reset instead of fabricating a replenished percentage.
- Store iPhone relay secrets as non-synchronizing `AfterFirstUnlockThisDeviceOnly` Keychain items so opportunistic background decryption can work after the first post-boot unlock.

On 2026-10-25 the owner removed the synthetic-data gate as a precondition for real usage: real usage data and provider adapters may connect to the relay without waiting for the P1-M9 close-out. The spike in [cloudflare-synchronization.md](../research/cloudflare-synchronization.md) remains useful validation and should prove the security boundary, deletion and recovery behavior, quota failure, repeatable deployment and teardown, and US$0 billing with no paid subscription or add-on. The owner waived the separate physical cellular-path observation below; that waiver is risk acceptance, not evidence that the path works.

On 2026-10-24, the owner approved the P1-M9 release and execution details. The otherwise-empty Workers Free account has no paid add-on or existing Worker. Because Durable Object Workers have no Version URL, the isolated synthetic candidate is promoted to 100%, privately verified, immediately smoke-tested, and rolled back on failure and during the planned rollback exercise; no observability or metadata binding is added. Required per-Worker metrics are checked immediately after the first synthetic deployment, with immediate teardown if any is unavailable while logs, traces, and Logpush remain disabled. The owner replaced the planned 24-hour soak with one uninterrupted 30-minute run, accepting that it provides weaker stability and daily-quota evidence; the checked-in 24-hour workload calculation remains required. The owner will run authentication and remote commands, can keep the Mac awake for the run, has an iPhone for the cellular check and private storage for six synthetic secrets, and authorizes final deletion of the Worker, secrets, and synthetic state.

The owner also approved installing Scriptable temporarily on the iPhone solely for the M9 synthetic cellular check, then deleting the test script and app. The reviewed script may use an isolated Scriptable WebView for WebCrypto after an embedded public-vector self-test, but it must accept secrets only through secure fields, keep the authenticated synthetic cache only in memory, clear the pasteboard, expose only pass/fail and byte counts, and never persist or log a token, content key, envelope, plaintext, or identifier. This approval does not add Scriptable or a hosted page to the product architecture. Later on 2026-10-24, before cellular preparation or installation, the owner explicitly waived the physical M9 cellular check and accepted the missing evidence. The tooling remains available for an optional future run, but M9 does not claim a cellular fetch, decryption, or commit pass.

## Personal-use Mac distribution

Use local development signing for the Mac collector. The first version does not require Developer ID notarization or an automatic updater; P1-M2 must instead define and validate installation, Gatekeeper handling, launch at login, CLI child-process access, update safety, and uninstall cleanup for the owner's Mac.

The collector continues as a menu-bar companion after its main window closes. Launch at login is an explicit setup opt-in backed by `SMAppService.mainApp`. In Reset Radar Settings, Claude Code integration directly edits the default user `~/.claude/settings.json` after an exact preview and owner confirmation. It changes only `statusLine.command`, stores the prior status-line setting for restoration, and preserves a validated existing status-line command.

On 2026-10-20 the owner resolved the existing-command security case: if a current status-line command could contain an inline secret or cannot be proved safe for composition, Reset Radar leaves it untouched and reports that automatic composition is unavailable. The installer backs up only the prior status-line setting, never the whole Claude Code settings file.

On 2026-10-25 the owner allowed one narrow extension for an existing `bash $HOME/<script>`
command. Reset Radar may compose it when the suffix is a simple path, the resolved script is a
trusted executable in the owner's home with an exact `#!/bin/bash` shebang, and synthetic output
from the original Bash invocation matches direct script execution through the helper. The
original command remains in the status-line-only restore record. Other arguments, expansions,
shell syntax, and untrusted scripts remain blocked.

## Interface and tooling decisions

- iOS uses a five-item Main Toolbar: Home, Benefits, Community, Insight, and All. The latter four screens are intentionally empty; All has a Settings button.
- macOS uses the same five destinations in a native sidebar and opens Settings through the standard Settings scene.
- Toolbar icons are original, neutral, tintable bitmap assets using house, faceted-gem, three-person, lightbulb, and three-horizontal-bars metaphors.
- The relay uses strict TypeScript, npm, Wrangler, Workers Vitest support, and a SQLite-backed Durable Object. This build-tool addition is approved.
- Pairing uses a short-lived QR package with a manual copy/paste fallback.
- Paired iPhones and iPads own their displayed device name. During pairing the reader proposes
  `UIDevice.name`; if iOS provides only generic `iPhone` or `iPad`, the reader offers an editable
  fallback. M17 does not depend on Apple's restricted user-assigned-device-name entitlement.
  After unchanged activation, the reader reports its chosen name and device class through an
  optional, retryable, end-to-end encrypted `/v2` reader profile. The relay stores only opaque
  ciphertext, profile failure never fails pairing, and the Mac never invents or edits the name.
  Pairing & Sync exposes the reported name after pairing: a custom edit remains stable, while
  **Use Device Name** restores automatic updates from `UIDevice.name` on later app executions.
  It separately shows Available to Mac, Waiting to share, or Couldn't share — Retry; failure
  retains the local choice and pairing and supports automatic plus manual retry.
  Profile delivery uses its own monotonic revision and byte-identical retries so reordered network
  completion cannot overwrite a newer device-name choice; it never consumes snapshot sequence.
  New reader rows use the relay's activation timestamp as Paired; migrated rows lacking it keep
  their local observation time but label it First seen.
  Every roster row also shows `ID ` plus the final eight lowercase hexadecimal Reader ID
  characters in smaller monospaced secondary text. Status uses separate appearance-aware color,
  text, and a symbol; color is never the only cue.
- Small and Lock Screen widgets select one account window; the medium widget shows both standard
  windows for one selected account.
- Account aliases accept Unicode letters, marks, numbers, punctuation, symbols, and ASCII spaces,
  must contain at least one visible letter/number/punctuation/symbol, and reject every other scalar
  category, Unicode noncharacters, and exact effective-label duplicates. Accepted input is kept
  exact without Unicode normalization. This preserves letters from international scripts and
  emoji that need no zero-width joiner while excluding invisible controls, bidirectional
  overrides, explicit shaping controls, private-use text, and whitespace-only names.
- Claude Code Percentage Used is display-only floored to a whole percent on every surface:
  `96.9%` displays as `96%`. Raw observation precision remains unchanged, and Codex continues to
  use provider-reported precision.

## Architecture review decisions

The owner made these decisions on 2026-10-19 while reviewing the [software architecture](../architecture.md):

- The iOS app is universal. iPad runs it natively, with the system's adaptive tab bar or sidebar presentation of the Main Toolbar, and has no Live Activities or Watch transfer.
- iPhone, iPad, and Mac each offer per-window opt-in reset notifications from their own cache. The same reset may alert on more than one device.
- Each account row's Codex rings use the windows in that account's backward-compatible default
  bucket. Other valid Codex limits appear only in that account's Account Details.
- A reader's first authenticated snapshot read is only a preflight. The relay marks it activated on an explicit, idempotent read-token confirmation sent after the iPhone or iPad saves its Keychain secrets and local pairing state. The relay assigns a five-minute pending expiry; the Mac uses the administration-only reader list to close pairing after activation and revoke abandoned readers. This 2026-10-20 decision replaces first-read activation.
- Shared Swift modules live in one local Swift package, `ResetRadarKit`, with no third-party dependencies.
- **Layering.** The architecture follows the clean-architecture dependency rule. A `ResetRadarApplication` module holds use cases and ports; storage, transport, scheduling, Watch, provider, and UI modules are adapters that depend only inward. Each major module has its own design document.
- **Widgets.** Widgets may refresh the shared cache from the relay during a system reload, at most when the last successful refresh is over five minutes old.
- **Foreground refresh.** While the iOS app is in the foreground, it fetches from the relay every 60 seconds.
- **Manual Mac-assisted refresh.** On iPhone and iPad, Account Details targets one opaque Codex
  account and Home Refresh targets all configured Codex accounts through the authenticated relay.
  Successful per-account results survive a sibling failure. A Claude Code account Refresh reads
  the relay without forcing a provider response. The reader-global one-minute request limit stays
  in force. This path requires its own synthetic security, quota, and latency evidence before real
  data uses it.
- **Mac secrets.** The Mac stores relay secrets in the login keychain. Every Release build is signed with one Personal Team Apple Development identity, ad-hoc Release builds are rejected, and Keychain calls are non-interactive. See [Mac Keychain access](../research/mac-keychain-access.md).
- **Platform targets.**

  | Device | Model | Minimum OS |
  |---|---|---|
  | iPhone | iPhone 18 Pro Max | iOS 27.0 |
  | iPad | iPad Air 11-inch (M4) | iPadOS 27.0 |
  | Apple Watch | Apple Watch Series 11 (42mm) | watchOS 27.0 |
  | Mac | MacBook Pro, Apple M5 Max, 128 GB | macOS 26.7.1 |

  The same models are the simulator destinations. Every Mac target and configuration builds only
  `arm64`; `x86_64` slices and Intel Mac support are excluded. See
  [Platform targets](../architecture.md#platform-targets).
  The owner raised the iOS, iPadOS, and watchOS minimums to 27.0 on 2026-10-27; this supersedes
  the 26.x minimums recorded when scaffolding was completed. On 2026-10-28 the owner replaced
  the incompatible iOS simulator references with the iPhone 18 Pro Max and iPad Air 11-inch
  (M4), which are available in the installed iOS 27.0 runtime.

## P1-M14 decisions

The owner made these decisions on 2026-10-26 while P1-M14 was being completed:

- **M9 entry waiver.** P1-M14 may proceed and close without P1-M9 being `Done`. P1-M9 stays
  `Active` with its own open items. The waiver does not turn M9's cellular waiver into iOS
  cellular evidence, and it does not replace the owner-run manual-refresh evidence that this
  file requires.
- **Screen-model placement.** `ResetRadarUI` holds value-type presentation derivations and shared
  components. Each composition root holds its observable screen state. See
  [UI screen models](../architecture/ui.md#screen-models).
- **Development storage.** Unsigned Development builds without an App Group entitlement fall back
  to the app's own Application Support directory with the `Debug` flavor. Release still fails
  closed. See [iOS composition](../architecture/ios-app.md#composition).

## Evidence still required

The interview resolves the owner choices, but not these validation tasks:

- Cloudflare synthetic-data, cellular, quota, deletion, deployment, teardown, and billing spike;
- Mac-assisted manual-refresh spike: authenticated request and acknowledgement, revoked-reader denial, replay and rate limits, sleeping-Mac timeout, publication failure, latency, and worst-case Free-tier capacity;
- absolute-reset notification replacement/cancellation and OS-local time-zone presentation tests;
- Live Activity lifecycle and stale-state tests;
- signed-in Codex and Claude Code smoke tests that do not log raw responses or credentials;
- source-specific refresh and stale-threshold calibration;
- physical-device signing, WidgetKit/App Group behavior, and seven-day Sideloadly refresh without data loss, on iPhone and iPad;
- Apple Watch target signing, installation on the paired watch, iPhone-to-watch synchronization, stale/offline presentation, and data preservation across the seven-day refresh cycle; and
- Mac installation, login-item, update, and removal tests under local development signing.

The owner authorizes owner-present, read-only smoke tests against already signed-in Codex and Claude Code instances, provided no raw response, credential, account identifier, prompt, response content, or project path is retained. The owner also authorizes an owner-present, synthetic-only Cloudflare deployment on an existing Free account, with explicit authentication and billing verification during execution.
