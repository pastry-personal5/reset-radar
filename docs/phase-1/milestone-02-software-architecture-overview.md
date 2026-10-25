# P1-M2: Software architecture overview

Status: Done

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

## Deliverables

- [Software architecture](../architecture.md) and the module designs under `docs/architecture/`, promoted from `Proposal` to `Active` after owner review.
- [Mac Keychain access](../research/mac-keychain-access.md) research and its validation spike.
- [Official mobile usage access](../research/official-mobile-usage-access.md) feasibility review for the owner-requested optional independent-phone mode.
- [Spike results](../research/spike-results.md): one dated entry per spike with the question, method, versions, measured values, and pass/fail. Harness code stays on a throwaway branch and is not merged.
- Updated owner decisions, product behavior, UX documents, and contribution instructions where the accepted architecture affects them.

## Completion checklist

- [x] The 2026-10-20 architecture review resolves the owner-selected Mac-assisted manual refresh path with a bounded relay protocol, reader and Mac rate limits, acknowledgement tied to an actual Codex read, offline timeout behavior, capacity calculation, and specified synthetic security/latency tests. Cross-document contracts for pairing, Watch replies, removed Home windows, and safe Claude Code status-line setup agree; affected product and decision docs are updated. Evidence: [architecture](../architecture.md), [relay protocol](../architecture/relay.md#protocol), [ProviderAdapters](../architecture/provider-adapters.md#claude-code-status-line), and the [static review](../research/spike-results.md#static-architecture-review--2026-10-20). The spike tests themselves remain unchecked below.
- [x] An architecture review checks the end-to-end refresh, pairing, relay response, local commit, Watch delivery, and source-observation paths against their module designs. Confirmed design gaps and verification cases are recorded in [Application](../architecture/application.md), [Storage](../architecture/storage.md), [Transport](../architecture/transport.md), [Relay](../architecture/relay.md), [ProviderAdapters](../architecture/provider-adapters.md), [Scheduling](../architecture/scheduling.md), and the composition-root designs. Proposed changes to the provider-credential boundary remain an owner decision.
- [x] The owner's optional independent-phone acquisition request has an evidence-backed feasibility result for Codex and Claude Code, including vendor-supported device login, subscription-window API availability, and credential policy. Any unsupported path stays out of the build contract. Evidence: [official mobile usage access](../research/official-mobile-usage-access.md), reviewed against current vendor documents on 2026-10-20.
- [x] The owner resolves every architecture-affecting product or process question discovered during review. The 2026-10-19 choices and the 2026-10-20 Mac-assisted refresh, missing-window, Claude Code command, and after-save pairing activation choices are recorded in [owner decisions](owner-decisions.md), [UX GUI](../ux-gui.md), [UX information architecture](../ux-information-architecture.md), and the [changelog](changelog.md).
- [x] Target/module ownership and dependency direction are documented for the iPhone app, widgets, Live Activity, watch app, Mac collector, shared model, and relay. Evidence: “Layers and modules” in [software architecture](../architecture.md) and the module designs it links.
- [x] Each major module and composition root has a clean-architecture design with an internal architecture diagram, linked from the architecture. Evidence: “Layers and modules” in [software architecture](../architecture.md) and the twelve documents under `docs/architecture/`.
- [x] The window and latest-observation model defines identities, reset semantics, source provenance, freshness, unavailability, validation, serialization, and migrations without assuming exactly two windows. Evidence: [Domain](../architecture/domain.md) and [Storage](../architecture/storage.md).
- [x] Mac provider adapters define process lifecycle, compatibility negotiation, timeouts, backoff, schema fixtures, privacy-safe logging, and stale transitions. Evidence: [ProviderAdapters](../architecture/provider-adapters.md), plus “Diagnostics and privacy” and “Verification” in [software architecture](../architecture.md).
- [x] Pairing, key storage, envelope encryption, replay protection, authority, deletion, recovery, and device-loss behavior are documented. Evidence: [Transport](../architecture/transport.md), [Relay](../architecture/relay.md), and “Pairing, revocation, and loss” in [software architecture](../architecture.md).
- [x] The sync and refresh model defines triggers, cadences, coalescing, cross-process coordination, Watch-initiated refresh, the complication budget, and relay capacity. Evidence: “Sync and refresh model” in [software architecture](../architecture.md) and “Policies” in [Application](../architecture/application.md#policies).
- [x] Reference devices, minimum OS versions, and simulator destinations are recorded. Evidence: “Platform targets” in [software architecture](../architecture.md#platform-targets).
- [x] A detailed owner-run source-calibration runbook provides fail-closed, command-line procedures for the signed-in Codex and Claude Code smoke tests without retaining raw responses, identifiers, prompts, response content, credentials, or project paths. Evidence: [source-calibration spike runbook](../research/source-calibration-spike-runbook.md); four offline synthetic tests, JavaScript and Zsh syntax checks, relative-link validation, whitespace validation, preparation smoke test, and installed Codex schema preflight passed on 2026-10-22 without reading live usage.
- [x] Absolute provider resets and notification scheduling cover OS-local display, time-zone changes, per-window opt-in, replacement, cancellation, expiry, and clock changes. Evidence: “Reset notifications” in [Application](../architecture/application.md#reset-notifications-ios-and-macos) and [Scheduling](../architecture/scheduling.md).
- [x] Widget, Live Activity, and App Intent ownership and lifecycle behavior are documented. Evidence: [Application](../architecture/application.md), [iOS app](../architecture/ios-app.md), and [Scheduling](../architecture/scheduling.md).
- [x] A synthetic-only, owner-run Mac Keychain validation runbook prepares an isolated signed harness, records the exact non-interactive candidates, and gives reversible setup, observation, and cleanup commands. It deliberately leaves the production project untouched and supplies no provider or relay secret. Evidence: [Mac Keychain validation spike runbook](../research/mac-keychain-validation-spike-runbook.md), reviewed for command syntax and source type checking on 2026-10-22.
- [x] The binding iPhone Main Toolbar, Mac sidebar/menu-bar lifecycle, Watch grid/details, Settings routes, widgets, complication, and bitmap-icon contract are reflected in the UX documents and architecture. Evidence: [UX terms](../ux-terms.md), [UX information architecture](../ux-information-architecture.md), [UX GUI](../ux-gui.md), and the scene sections of the [iOS app](../architecture/ios-app.md), [Mac app](../architecture/mac-app.md), and [Watch app](../architecture/watch-app.md) designs.
- [x] The project entry points are concise and non-duplicative, and the UX glossary defines consistent visible terms for recurring components, states, and actions without changing approved behavior. Evidence: [README](../../README.md), [agent instructions](../../AGENTS.md), and [UX terms](../ux-terms.md); changed-file links and whitespace validated on 2026-10-20.
- [x] Local development signing, launch at login, CLI child-process access, safe update, uninstall cleanup, and owner-readable recovery instructions are specified for the Mac collector. Evidence: [Mac app](../architecture/mac-app.md) and [ProviderAdapters](../architecture/provider-adapters.md).
- [x] Proposed mitigations for the five [follow-up security findings](../research/spike-results.md#follow-up-security-review--2026-10-20) are specified across the affected module designs, system failure behavior, and UX. Evidence: the [architecture response](../research/spike-results.md#proposed-architecture-response). This checks documentation only, not owner acceptance or runtime proof.
- [x] The owner explicitly accepts the five follow-up security findings, including the residual Universal Clipboard and offline-Watch risks, before targeted verification and approves promotion of the architecture to Active. Targeted verification remains required before real usage reaches the relay. Evidence: [changelog](changelog.md).
- [x] Derived freshness, the multi-reader token model, the status-line helper target and install path, Mac sandbox posture, and sequence durability are specified. Evidence: “Availability” in [Domain](../architecture/domain.md#availability), “Key material” in [Transport](../architecture/transport.md#key-material), “Claude Code status line” in [ProviderAdapters](../architecture/provider-adapters.md#claude-code-status-line), “Process posture” in [Mac app](../architecture/mac-app.md#process-posture), and `FilePublisherStore` in [Storage](../architecture/storage.md#stores).
- [x] The gate definition covers iPhone, iPad, Mac, Watch, and relay checks on the recorded simulator destinations; P1-M3 installs matching simulator runtimes and a qualifying Xcode. Evidence: [contribution guide](../contribution-guide.md).
- [x] A P1-M3 scaffolding map lists targets, packages, entitlements, build configurations, test bundles, fixtures, and the first complete-gate command sequence. Evidence: “Layers and modules,” “Platform targets,” and “Build and project contract” in [software architecture](../architecture.md), plus each composition root's configuration table.
- [x] The approved TypeScript/Wrangler relay toolchain and Workers test/deployment boundaries are documented. Evidence: [Relay](../architecture/relay.md) and “Relay conformance” in [software architecture](../architecture.md).
- [x] The owner reviews the architecture and the approval is recorded in [changelog.md](changelog.md).

## Open work

The unfinished validation work was extracted on 2026-10-22 to [P1-M2 open work](../archive/p1-m2-open-work.md), where each item is assigned to the module that implements the related feature. It no longer gates this milestone.
