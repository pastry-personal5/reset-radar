# P1-M2: Software architecture overview

Status: Active

Define and validate the architecture for Reset Radar's iPhone, Apple Watch, and Mac components. This milestone turns the approved P1-M1 boundaries into implementation-ready module, data, security, synchronization, scheduling, and lifecycle decisions without creating the production Xcode project.

## Goal

Produce an architecture that P1-M3 can scaffold without inventing product behavior or crossing the approved credential, privacy, cost, signing, and freshness boundaries.

## In scope

- Apple-platform target and package structure.
- The normalized window, observation, provenance, freshness, and availability model.
- Codex app-server and Claude Code adapter boundaries on Mac.
- Pairing, key storage, encrypted envelopes, relay protocol, and iPhone-to-watch transfer.
- Local persistence, conflict authority, reset calculation, notification scheduling, widgets, Live Activities, and App Intent boundaries.
- Binding iPhone, Mac, and Watch navigation, layout, settings, and lifecycle behavior.
- Validation spikes required by [owner-decisions.md](owner-decisions.md), using synthetic relay data and the owner-authorized, owner-present, read-only signed-in source smoke tests.
- Failure, migration, installation, update, and removal behavior needed to scaffold safely.

## Out of scope

- Production app implementation or the production Xcode project; those belong to P1-M3 and later implementation milestones.
- New product scope, provider credentials, private consumer endpoints, API-key mode, APNs, multiple publishing Macs, analytics, or paid services.
- Manual percentage entry, manual reset rules, recurrence calculation, and general ChatGPT or Claude consumer-usage tracking.
- Visual styling and branding assets beyond architecture-affecting interface structure.
- Real usage data in the Cloudflare relay before its synthetic-data gate passes.

## Deliverables

- [Software architecture](../architecture.md) and the module designs under `docs/architecture/`, promoted from `Proposal` to `Active` after owner review.
- [Mac Keychain access](../research/phase-1/mac-keychain-access.md) research and its validation spike.
- [Official mobile usage access](../research/phase-1/official-mobile-usage-access.md) feasibility review for the owner-requested optional independent-phone mode.
- [Spike results](../research/phase-1/spike-results.md): one dated entry per spike with the question, method, versions, measured values, and pass/fail. Harness code stays on a throwaway branch and is not merged.
- Updated owner decisions, product behavior, UX documents, and contribution instructions where the accepted architecture affects them.

## Completion checklist

- [x] The 2026-10-20 architecture review resolves the owner-selected Mac-assisted manual refresh path with a bounded relay protocol, reader and Mac rate limits, acknowledgement tied to an actual Codex read, offline timeout behavior, capacity calculation, and specified synthetic security/latency tests. Cross-document contracts for pairing, Watch replies, removed Home windows, and safe Claude Code status-line setup agree; affected product and decision docs are updated. Evidence: [architecture](../architecture.md), [relay protocol](../architecture/relay.md#protocol), [ProviderAdapters](../architecture/provider-adapters.md#claude-code-status-line), and the [static review](../research/phase-1/spike-results.md#static-architecture-review--2026-10-20). The spike tests themselves remain unchecked below.
- [x] An architecture review checks the end-to-end refresh, pairing, relay response, local commit, Watch delivery, and source-observation paths against their module designs. Confirmed design gaps and verification cases are recorded in [Application](../architecture/application.md), [Storage](../architecture/storage.md), [Transport](../architecture/transport.md), [Relay](../architecture/relay.md), [ProviderAdapters](../architecture/provider-adapters.md), [Scheduling](../architecture/scheduling.md), and the composition-root designs. Proposed changes to the provider-credential boundary remain an owner decision.
- [x] The owner's optional independent-phone acquisition request has an evidence-backed feasibility result for Codex and Claude Code, including vendor-supported device login, subscription-window API availability, and credential policy. Any unsupported path stays out of the build contract. Evidence: [official mobile usage access](../research/phase-1/official-mobile-usage-access.md), reviewed against current vendor documents on 2026-10-20.
- [x] The owner resolves every architecture-affecting product or process question discovered during review. The 2026-10-19 choices and the 2026-10-20 Mac-assisted refresh, missing-window, Claude Code command, and after-save pairing activation choices are recorded in [owner decisions](owner-decisions.md), [UX GUI](../ux-gui.md), [UX information architecture](../ux-information-architecture.md), and the [changelog](changelog.md).
- [x] Target/module ownership and dependency direction are documented for the iPhone app, widgets, Live Activity, watch app, Mac collector, shared model, and relay. Evidence: “Layers and modules” in [software architecture](../architecture.md) and the module designs it links.
- [x] Each major module and composition root has a clean-architecture design with an internal architecture diagram, linked from the architecture. Evidence: “Layers and modules” in [software architecture](../architecture.md) and the twelve documents under `docs/architecture/`.
- [x] The window and latest-observation model defines identities, reset semantics, source provenance, freshness, unavailability, validation, serialization, and migrations without assuming exactly two windows. Evidence: [Domain](../architecture/domain.md) and [Storage](../architecture/storage.md).
- [x] Mac provider adapters define process lifecycle, compatibility negotiation, timeouts, backoff, schema fixtures, privacy-safe logging, and stale transitions. Evidence: [ProviderAdapters](../architecture/provider-adapters.md), plus “Diagnostics and privacy” and “Verification” in [software architecture](../architecture.md).
- [x] Pairing, key storage, envelope encryption, replay protection, authority, deletion, recovery, and device-loss behavior are documented. Evidence: [Transport](../architecture/transport.md), [Relay](../architecture/relay.md), and “Pairing, revocation, and loss” in [software architecture](../architecture.md).
- [x] The sync and refresh model defines triggers, cadences, coalescing, cross-process coordination, Watch-initiated refresh, the complication budget, and relay capacity. Evidence: “Sync and refresh model” in [software architecture](../architecture.md) and “Policies” in [Application](../architecture/application.md#policies).
- [x] Reference devices, minimum OS versions, and simulator destinations are recorded. Evidence: “Platform targets” in [software architecture](../architecture.md#platform-targets).
- [ ] The Cloudflare synthetic-data spike passes every criterion in the approved research and the “Relay conformance” list in [software architecture](../architecture.md), including three-reader add/revoke/cap and manual-refresh request, acknowledgement, latency, and Free-tier capacity, or the failed condition and resulting owner decision are recorded. No real provider data is used. Evidence: spike-results entry.
- [ ] A WatchConnectivity spike with a paired physical watch records application-context and complication user-info delivery, a Watch-initiated refresh that wakes the iPhone app and replies before the message times out, the Watch App Group read by the complication, offline cache, complication reload, and stale display. It also proves Forget Mac while the Watch is offline, durable pending erasure, a queued receipt after reconnection, and eventual complication reload. The seven-day Sideloadly install and refresh results for iPhone and iPad are recorded, including whether the app and widget still read their Keychain items after the re-sign, or explicitly deferred to P1-M3 with the blocker named.
- [ ] Source calibration records, for Codex and Claude Code separately, installed version, field shape, timing, and the confirmed or rejected current-data window, plus the Codex default-bucket identity, legitimate Codex frame size against the proposed bound, and the Claude Code new-response signal. Evidence: spike-results entry with no raw responses or identifiers.
- [x] A detailed owner-run source-calibration runbook provides fail-closed, command-line procedures for the signed-in Codex and Claude Code smoke tests without retaining raw responses, identifiers, prompts, response content, credentials, or project paths. Evidence: [source-calibration spike runbook](../research/phase-1/source-calibration-spike-runbook.md); four offline synthetic tests, JavaScript and Zsh syntax checks, relative-link validation, whitespace validation, preparation smoke test, and installed Codex schema preflight passed on 2026-10-22 without reading live usage.
- [ ] The source-calibration harness explicitly selects every owner-designated `codex-profile` profile, isolates its app-server process and sanitized report, verifies each selected profile, and never relies on an ambient `CODEX_HOME` or retains a profile name in project evidence. Evidence: source-calibration synthetic tests and owner-run preflight.
  - 2026-10-22 partial checkpoint: all four Node synthetic tests, the two-profile preparation-isolation test, JavaScript and Zsh syntax checks, `git diff --check`, and `swift-format` passed without a live signed-in usage read. The per-profile installed-schema preflight and live observations remain owner-run work, so this item stays unchecked.
- [x] Absolute provider resets and notification scheduling cover OS-local display, time-zone changes, per-window opt-in, replacement, cancellation, expiry, and clock changes. Evidence: “Reset notifications” in [Application](../architecture/application.md#reset-notifications-ios-and-macos) and [Scheduling](../architecture/scheduling.md).
- [x] Widget, Live Activity, and App Intent ownership and lifecycle behavior are documented. Evidence: [Application](../architecture/application.md), [iOS app](../architecture/ios-app.md), and [Scheduling](../architecture/scheduling.md).
- [ ] Synthetic spikes record WidgetKit timeline degradation at threshold crossings, Live Activity start/update/stale/end including `staleDate` and the eight-hour limit, App Group sharing and widgets on iPhone and iPad, widget-reload ingest under the cross-process lock (including suspension or background-task expiry mid-commit), widget-only reset-notification replacement/cancellation and expiry fallback, and Keychain access after first unlock from the app and the widget extension. Evidence: spike-results entries.
- [ ] The [Mac Keychain validation spike](../research/phase-1/mac-keychain-access.md#5-validation-spike) passes: no dialog across a rebuild, at login launch, or eight days after signing; an ad-hoc build fails with an error instead of a dialog; a prelaunch lock blocks a fresh read; and a later lock leaves the already running cache usable until process exit. A failure returns the storage decision to the owner. Evidence: spike-results entry.
- [x] A synthetic-only, owner-run Mac Keychain validation runbook prepares an isolated signed harness, records the exact non-interactive candidates, and gives reversible setup, observation, and cleanup commands. It deliberately leaves the production project untouched and supplies no provider or relay secret. Evidence: [Mac Keychain validation spike runbook](../research/phase-1/mac-keychain-validation-spike-runbook.md), reviewed for command syntax and source type checking on 2026-10-22.
- [ ] Refresh-timing spikes on the reference devices record Mac timer drift with the main window closed over 24 hours and iOS background-task run intervals over 24 hours. Evidence: spike-results entries.
- [x] The binding iPhone Main Toolbar, Mac sidebar/menu-bar lifecycle, Watch grid/details, Settings routes, widgets, complication, and bitmap-icon contract are reflected in the UX documents and architecture. Evidence: [UX terms](../ux-terms.md), [UX information architecture](../ux-information-architecture.md), [UX GUI](../ux-gui.md), and the scene sections of the [iOS app](../architecture/ios-app.md), [Mac app](../architecture/mac-app.md), and [Watch app](../architecture/watch-app.md) designs.
- [x] The project entry points are concise and non-duplicative, and the UX glossary defines consistent visible terms for recurring components, states, and actions without changing approved behavior. Evidence: [README](../../README.md), [agent instructions](../../AGENTS.md), and [UX terms](../ux-terms.md); changed-file links and whitespace validated on 2026-10-20.
- [x] Local development signing, launch at login, CLI child-process access, safe update, uninstall cleanup, and owner-readable recovery instructions are specified for the Mac collector. Evidence: [Mac app](../architecture/mac-app.md) and [ProviderAdapters](../architecture/provider-adapters.md).
- [ ] A security review table, appended to spike-results, walks every row of “Failure behavior” and each trust boundary in the architecture and finds no path that copies provider credentials, exposes plaintext to Cloudflare, fabricates usage, or silently upgrades a free service. The [2026-10-20 static review](../research/phase-1/spike-results.md#static-architecture-review--2026-10-20) covers the design; runtime proof remains open.
- [x] Proposed mitigations for the five [follow-up security findings](../research/phase-1/spike-results.md#follow-up-security-review--2026-10-20) are specified across the affected module designs, system failure behavior, and UX. Evidence: the [architecture response](../research/phase-1/spike-results.md#proposed-architecture-response). This checks documentation only, not owner acceptance or runtime proof.
- [x] The owner explicitly accepts the five follow-up security findings, including the residual Universal Clipboard and offline-Watch risks, before targeted verification and approves promotion of the architecture to Active. Targeted verification remains required before real usage reaches the relay. Evidence: [changelog](changelog.md).
- [x] Derived freshness, the multi-reader token model, the status-line helper target and install path, Mac sandbox posture, and sequence durability are specified. Evidence: “Availability” in [Domain](../architecture/domain.md#availability), “Key material” in [Transport](../architecture/transport.md#key-material), “Claude Code status line” in [ProviderAdapters](../architecture/provider-adapters.md#claude-code-status-line), “Process posture” in [Mac app](../architecture/mac-app.md#process-posture), and `FilePublisherStore` in [Storage](../architecture/storage.md#stores).
- [x] The gate definition covers iPhone, iPad, Mac, Watch, and relay checks on the recorded simulator destinations; P1-M3 installs matching simulator runtimes and a qualifying Xcode. Evidence: [contribution guide](../contribution-guide.md).
- [x] A P1-M3 scaffolding map lists targets, packages, entitlements, build configurations, test bundles, fixtures, and the first complete-gate command sequence. Evidence: “Layers and modules,” “Platform targets,” and “Build and project contract” in [software architecture](../architecture.md), plus each composition root's configuration table.
- [x] The approved TypeScript/Wrangler relay toolchain and Workers test/deployment boundaries are documented. Evidence: [Relay](../architecture/relay.md) and “Relay conformance” in [software architecture](../architecture.md).
- [x] The owner reviews the architecture and the approval is recorded in [changelog.md](changelog.md).
- [ ] Every applicable gate check passes; commands structurally inapplicable before P1-M3 are attempted, recorded, and explicitly deferred under the pre-scaffolding exception. For documentation-only changes, record that `swift-format` and `swiftlint` have no Swift sources and that the `xcodebuild` and `npm` commands have no project or package yet, naming P1-M3 as the target.
  - 2026-10-20: `swift-format lint --strict --recursive .` passed with no Swift files.
  - 2026-10-20: `swiftlint --strict` failed with “No lintable files found”; defer the Swift-source check to P1-M3.
  - 2026-10-20: `xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'`, the same scheme on `iPad Air 11-inch (M2)`, `ResetRadarMac` on `platform=macOS`, and `ResetRadarWatch` on `Apple Watch Series 11 (42mm)` each failed because no Xcode project, workspace, or package exists; simulator service was also unavailable in this run. Defer all four to P1-M3.
  - 2026-10-20: `npm --prefix relay test` and `npm --prefix relay run typecheck` failed because `relay/package.json` does not exist; defer both to P1-M3.

## Validation work and order

Spikes use isolated synthetic harnesses on a throwaway branch; reusable domain code and fixtures may be promoted only after review. Order matters because some measurements need 24 hours and one needs eight days.

0. **Prepare the toolchain.** Done on 2026-10-19: Xcode 27.1 is selected and its license accepted. Its iOS 27.1, watchOS 27.0, and macOS 27.0 SDKs meet [Platform targets](../architecture.md#platform-targets). Still to do:
   - install the iOS and watchOS simulator runtimes; and
   - create the Personal Team Apple Development identity. On 2026-10-19 this Mac still had none.
1. **Start the long-running measurements first:**
   - **Relay.** Verify Workers Free and no paid add-on before and after deployment. Deploy to `workers.dev` with logs, traces, and Logpush off. Start the 24-hour measurement at the worst-case cadence, including accepted manual requests and their follow-up reads: requests, CPU, Durable Object duration, rows, storage, p50/p95 latency, and cellular data.
   - **Mac Keychain.** Sign the Keychain harness on day one so the eight-day check can run (steps 1–2 of the [Mac Keychain validation spike](../research/phase-1/mac-keychain-access.md#5-validation-spike)).
   - **Timers.** Start the Mac timer-drift and iOS background-interval measurements.
2. **While those run:**
   - owner-present, read-only source calibration against signed-in Codex and Claude Code;
   - the remaining Mac Keychain spike steps; and
   - platform spikes for App Group (iPhone, iPad, and Watch), iOS Keychain from the app and widget, widget-reload ingest, WidgetKit, Live Activity, notification reconciliation, WatchConnectivity (including the Watch-initiated refresh), complication reload, and `SMAppService.mainApp`.
3. **After 24 hours:** publish ciphertext on Wi-Fi, disconnect the Mac, and retrieve and decrypt on iPhone cellular; run quota, rate-limit, clock-skew, malformed-ciphertext, wrong-key, replay, incompatible-version, promotion, and rollback cases. Exercise a manual request with the Mac awake, asleep, offline, and after reader revocation; measure completion and timeout, then tear down and confirm billing remains US$0.
4. Write the runtime security review table and confirm that results remain within the owner's accepted residual-risk boundary. Architecture approval does not authorize real usage data on the relay.

If any source calibration rejects a candidate current-data window, stop and return the threshold to the owner.
