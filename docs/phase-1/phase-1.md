# Phase 1: Foundation

Status: Planned

Goal: Settle what Reset Radar must do and how it is built, stand up a project that builds and passes the gate, then build the first usable version: a Mac collector that publishes encrypted readings through the relay to the iPhone, iPad, and Apple Watch.

This file is the overall plan. Each milestone gets its own overview file when it starts, per the [development process](../development-process.md).

## Exit criteria

- Research findings are written down and the product scope in [product-behavior.md](../product-behavior.md) is filled in from them.
- The software architecture is documented and every related "Undecided" item in [AGENTS.md](../../AGENTS.md) is resolved or consciously deferred.
- An Xcode project targeting iOS, iPadOS, and watchOS 27.0+, and macOS 26.7.1+ builds with the `ResetRadar`, `ResetRadarMac`, and `ResetRadarWatch` schemes, and the full gate passes with empty-but-real app, watch app, and test targets.
- The Mac collector, relay, and both provider adapters work end to end on synthetic and real data; the iOS, iPad, and Watch apps, widgets, and Live Activities display it. Open work in [P1-M2 open work](../archive/p1-m2-open-work.md) is verified by its owning milestones.
- The owner records one full seven-day Sideloadly refresh cycle after the initial free-signed iPhone and Watch installation, including preservation of the Watch app, complication configuration, and Watch cache. This elapsed-time check may finish after P1-M16 is `Done`; Phase 1 remains open until it is recorded.

## Approach

- **Bottom-up, Mac first.** Milestones follow the `ResetRadarKit` dependency rule (Domain ← Application ← adapters and UI ← composition roots) from [software architecture](../architecture.md). The Mac collector is the only real data source, so it and its UI come before the iOS and Watch apps.
- **Fixtures first.** Adapters and the Mac collector are built and tested locally against fixtures. P1-M9 no longer gates real usage.
- **Tests travel with code.** Each milestone adds its tests and carries the [P1-M2 open work](../archive/p1-m2-open-work.md) rows for its modules, as ordinary tests or owner-run runbooks.
- **Gate scope.** The Mac, iPhone, iPad, Watch, lint, import, and relay checks run in the complete gate. The device suites returned with P1-M14 and P1-M16 as recorded in the [changelog](changelog.md).
- **Stop on contradiction.** A result that contradicts an accepted decision goes back to the owner; behavior is not adjusted to fit (see [owner decisions](owner-decisions.md)).

## Order and dependencies

| Milestone | Depends on | Module(s) | Owner-run work |
|---|---|---|---|
| P1-M4 Domain model | scaffold | Domain | none |
| P1-M5 Application use cases | M4 | Application, TestSupport | none |
| P1-M6 Storage | M4, M5 | Storage | none |
| P1-M7 Transport crypto and protocol | M4, M5 | Transport | none |
| P1-M8 Relay implementation | M7 fixtures | `relay/` | none |
| P1-M9 Relay synthetic-data gate | M7, M8 | Relay, Transport | Cloudflare deployment, 30-minute measurement, billing check |
| P1-M10 Codex adapter | M5, M7, M8 | ProviderAdapters, account contracts, refresh v2 | signed-in schema smoke test, profile selection |
| P1-M11 Claude Code adapter | M5, M10 Checkpoint A | ProviderAdapters | signed-in status-line calibration |
| P1-M12 Mac collector app | M6, M7, M10 and M11 code-complete | Mac root | Keychain checks, eight-day re-read, timer drift |
| P1-M13 Mac UI | M12 | UI, Mac root | none |
| P1-M14 iOS core app | M6, M7, M13 | iOS root | initial free-signed iPhone/iPad install; begin seven-day refresh observation |
| P1-M15 Scheduling | M14 | Scheduling, widgets | widget, Live Activity, and background-timing checks on device |
| P1-M16 Watch | M14, M15 | WatchSync, Watch root | initial free-signed install and WatchConnectivity on reference paired devices; seven-day refresh at Phase 1 exit |
| P1-M17 experience, pairing, and synchronization polish | M14, M15, M16 implementation handoff | Application, Transport, UI, iOS root, Mac root, Watch root | focused contract tests plus visual inspection at reference simulator destinations |

M6, M7 and M8 can proceed in parallel after M5. The expanded M10 account-refresh scope starts
after M7 and M8 and can run in parallel with M9. M11 preparation may proceed independently, but
its production work waits for M10 Checkpoint A's shared account and configuration contracts. Real
data first flows end to end when the Mac publisher and reader app are ready; M9's separate
synthetic-data gate does not block real relay use under the 2026-10-25 owner decision.

## Time-gated work

Start these as early as their milestone allows so elapsed time does not block the end of the phase:

- Relay 30-minute latency and capacity sample, begun in P1-M9, with checked-in 24-hour Free-limit accounting.
- Mac Keychain re-read eight days after signing, begun at the first signed build in P1-M12.
- Mac timer drift and iOS background-task intervals over 24 hours, begun in P1-M12 and P1-M15.
- Sideloadly seven-day refresh, begun for iOS at the first installable build in P1-M14 and for the paired Watch at its first free-signed install in P1-M16. The full Watch preservation observation is a Phase 1 exit item after M16 may close.

## Risks

| Risk | Response |
|---|---|
| The relay fails a synthetic-data criterion or exceeds Workers Free. | Record the failure and return the synchronization decision to the owner. M14 through M16 may proceed under the owner's M9-gate waiver without claiming the failed criterion passed. |
| Provider output shape changes or a current-data window is rejected. | Treat the source as unavailable, not as a guessed value; return to the owner. |
| The Mac Keychain prompts after a rebuild or a lock. | Return the storage decision to the owner. |
| Free-account signing limits (seven-day expiry, 10 App IDs per week). | Keep bundle identifiers stable; use Sideloadly refresh and record each re-sign. |
| iOS or Watch regresses. | The complete gate runs the reference iPhone, iPad, and Watch simulator destinations before M16 can close. |

## Closing the phase

P1 is done when every milestone is `Done` or `Dropped`, the exit criteria hold, the [roadmap](../roadmap.md) is updated, and the runtime security review table from the P1-M2 open work is closed.

## Milestones

### P1-M1: Initial research
Status: Done
Goal: Produce sourced feasibility studies on allowance-usage tracking, reset times, available data, iOS capabilities, distribution, and prior art.
Plan: [overview](milestone-01-research-overview.md)

### P1-M2: Software architecture
Status: Done
Goal: Choose and document the Apple-platform structure, window/observation model, Mac provider adapters, iPhone-to-watch data flow, authenticated synchronization, reset scheduling, and notification approach based on the P1-M1 findings.
Plan: [overview](milestone-02-software-architecture-overview.md), [architecture](../architecture.md)
Notes: Open validation work is archived in [P1-M2 open work](../archive/p1-m2-open-work.md) and carried by the owning modules.

### P1-M3: Scaffolding
Status: Done
Goal: Create the Xcode project, all composition-root and test targets, the `ResetRadarKit` package, the relay package, SwiftLint and swift-format config, and a complete gate that passes with no deferrals and matches the P1-M2 architecture.
Plan: [overview](milestone-03-scaffolding-overview.md), [sequencing](milestone-03-scaffolding-sequence.md), [repository layout](../architecture/repository-layout.md)

Milestones receive overview files when they start. The Mac was built before iOS. P1-M14 restored the iPhone and iPad runs, and P1-M16 restored the Watch run to the complete gate.

### P1-M4: Domain model
Status: Done
Goal: Allowance windows, used-percent values, reset rules, freshness and availability state, with pure tests.
Plan: [overview](milestone-04-domain-model-overview.md), [sequencing](milestone-04-domain-model-sequence.md), [Domain](../architecture/domain.md)

### P1-M5: Application use cases
Status: Done
Goal: Ports, refresh and reset policies, snapshot reduction, and the error taxonomy against fakes.
Plan: [overview](milestone-05-application-use-cases-overview.md), [sequencing](milestone-05-application-use-cases-sequence.md), [Application](../architecture/application.md)

### P1-M6: Storage
Status: Done
Goal: App Group persistence, the cross-process lock, and the persisted sequence counter.
Plan: [overview](milestone-06-storage-overview.md), [sequencing](milestone-06-storage-sequence.md), [Storage](../architecture/storage.md)

### P1-M7: Transport crypto and protocol
Status: Done
Goal: Envelope encryption, HMAC account scope, pairing payloads, non-interactive secret storage, the HTTPS relay client, and shared Swift/relay fixtures.
Plan: [overview](milestone-07-transport-overview.md), [sequencing](milestone-07-transport-sequence.md), [Transport](../architecture/transport.md)

### P1-M8: Relay implementation
Status: Done
Goal: Worker and SQLite Durable Object with ciphertext-only storage, reader tokens with the three-reader cap, and the refresh-request mailbox.
Plan: [overview](milestone-08-relay-implementation-overview.md), [sequencing](milestone-08-relay-implementation-sequence.md), [relay](../architecture/relay.md)

### P1-M9: Relay synthetic-data gate
Status: Active
Goal: Owner-run Cloudflare spike on synthetic data covering the conformance criteria and a US$0 billing check. It no longer gates real usage on the relay.
Plan: [overview](milestone-09-relay-synthetic-gate-overview.md), [sequencing](milestone-09-relay-synthetic-gate-sequence.md), [relay](../architecture/relay.md)

### P1-M10: Codex adapter
Status: Active
Goal: Two-account Codex app-server client, account-aware shared contracts, schema validation,
current-data window, explicit profile isolation, and source calibration.
Plan: [overview](milestone-10-codex-adapter-overview.md), [sequencing](milestone-10-codex-adapter-sequence.md), [ProviderAdapters](../architecture/provider-adapters.md)

### P1-M11: Claude Code adapter
Status: Done
Goal: Claude Code status-line parser and guided installer that never replaces an unsafe or unprovable command, with source calibration.
Plan: [overview](milestone-11-claude-code-adapter-overview.md), [sequencing](milestone-11-claude-code-adapter-sequence.md), [ProviderAdapters](../architecture/provider-adapters.md)

### P1-M12: Mac collector app
Status: Done
Goal: Mac composition root, lifecycle and runtime drivers, Keychain secret store, publish loop, every owner flow (source setup, relay setup, pairing, paired devices, Keychain recovery) on functional unstyled screens, launch-at-login opt-in, and Release signing check. Normal launches use configured live sources; `--synthetic` selects fixtures. The owner accepted the Mac Keychain and timer-drift runtime-validation risk on 2026-10-25.
Plan: [overview](milestone-12-mac-collector-overview.md), [sequencing](milestone-12-mac-collector-sequence.md), [Mac app](../architecture/mac-app.md)
Notes: Mac reset notifications move to P1-M15.

### P1-M13: Mac UI
Status: Done
Goal: Polish the functional M12 screens without changing behavior: Account List and Account
Details layout, rings, sidebar, per-account menu-bar status, alias editing, and Settings styling.
Plan: [overview](milestone-13-mac-ui-overview.md), [implementation plan](milestone-13-mac-ui-architecture.md)

### P1-M14: iOS core app
Status: Active
Goal: Pairing, relay reader, iPhone Account List, iPad split Account List and Account Details,
Setup Banner, and Main Toolbar screens; re-enables the iPhone and iPad test runs in the gate.
Plan: [overview](milestone-14-ios-core-app-overview.md), [sequence](milestone-14-ios-core-app-sequence.md)
Notes: The initial signed iPhone installation, first launch after trust, and physical QR pairing
succeeded on 2026-10-27. M14 remains Active pending its IPA target, remaining physical
App Group/Keychain and cache checks, deployed-relay manual-refresh evidence, seven-day renewal,
and closure documentation.

### P1-M15: Scheduling
Status: Active
Goal: Reset notifications (including the Mac `NotificationDriver` moved from P1-M12), background refresh, widgets, and Live Activities, with their shared-state validation.
Plan: [overview](milestone-15-scheduling-overview.md), [sequence](milestone-15-scheduling-sequence.md), [validation](milestone-15-scheduling-validation.md), [Scheduling](../architecture/scheduling.md)
Notes: M9 exit is not an M15 prerequisite under the owner's 2026-10-26 instruction; M14's app and widget handoff remains the implementation dependency. The owner's all-window, notification-presentation, widget-budget, Live Activity lifecycle/prioritization, and local-dependency choices are recorded in [owner decisions](owner-decisions.md#time-zone-and-scheduling-semantics) and summarized in the [M15 overview](milestone-15-scheduling-overview.md#resolved-owner-decisions).

### P1-M16: Watch
Status: Active
Goal: WatchSync, Watch app grid, complication, offline and stale display, and Forget Mac erasure; re-enables the Watch test run and closes Watch-owned runtime security rows.
Plan: [overview](milestone-16-watch-overview.md), [sequence](milestone-16-watch-sequence.md), [Watch app](../architecture/watch-app.md), [WatchSync](../architecture/watch-sync.md)
Notes: M14 and M15 remain implementation dependencies. M9 exit is not an M16 prerequisite under the owner's waiver; M9's open remote evidence remains separate. The full seven-day Sideloadly refresh observation remains a Phase 1 exit criterion after M16 closes.

### P1-M17: Experience, pairing, and synchronization polish
Status: Active
Goal: Polish the iPhone, Mac, and Watch presentation and repair the supporting alias-publication,
relay-lifecycle, reader-roster, and pairing-metadata seams needed for truthful management UI.
Plan: [overview](milestone-17-gui-polish-overview.md), [sequence](milestone-17-gui-polish-sequence.md)
Notes: This work follows the implemented M14–M16 seams. It does not close their outstanding device
or runtime evidence and does not change provider acquisition, pairing wire bytes, or allowance
semantics.
