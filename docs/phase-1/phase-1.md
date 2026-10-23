# Phase 1: Foundation

Status: Active

Goal: Settle what Reset Radar must do and how it is built, stand up a project that builds and passes the gate, then build the first usable version: a Mac collector that publishes encrypted readings through the relay to the iPhone, iPad, and Apple Watch.

This file is the overall plan. Each milestone gets its own overview file when it starts, per the [development process](../development-process.md).

## Exit criteria

- Research findings are written down and the product scope in [product-behavior.md](../product-behavior.md) is filled in from them.
- The software architecture is documented and every related "Undecided" item in [AGENTS.md](../../AGENTS.md) is resolved or consciously deferred.
- An Xcode project targeting iOS and iPadOS 26.1+, watchOS 26.6+, and macOS 26.7.1+ builds with the `ResetRadar`, `ResetRadarMac`, and `ResetRadarWatch` schemes, and the full gate passes with empty-but-real app, watch app, and test targets.
- The Mac collector, relay, and both provider adapters work end to end on synthetic data and, after the relay's synthetic-data gate passes, on real data; the iOS, iPad, and Watch apps, widgets, and Live Activities display it. Open work in [P1-M2 open work](../archive/p1-m2-open-work.md) is verified by its owning milestones.

## Approach

- **Bottom-up, Mac first.** Milestones follow the `ResetRadarKit` dependency rule (Domain ← Application ← adapters and UI ← composition roots) from [software architecture](../architecture.md). The Mac collector is the only real data source, so it and its UI come before the iOS and Watch apps.
- **Synthetic before real.** No real usage reaches the relay until P1-M9 passes. Adapters and the Mac collector are built and tested locally against fixtures first; nothing live is published before then.
- **Tests travel with code.** Each milestone adds its tests and carries the [P1-M2 open work](../archive/p1-m2-open-work.md) rows for its modules, as ordinary tests or owner-run runbooks.
- **Gate scope.** The Mac, lint, import, and relay checks run in every milestone. The iPhone, iPad, and Watch test runs are suspended (see the [changelog](changelog.md)) and return with P1-M14 and P1-M16.
- **Stop on contradiction.** A result that contradicts an accepted decision goes back to the owner; behavior is not adjusted to fit (see [owner decisions](owner-decisions.md)).

## Order and dependencies

| Milestone | Depends on | Module(s) | Owner-run work |
|---|---|---|---|
| P1-M4 Domain model | scaffold | Domain | none |
| P1-M5 Application use cases | M4 | Application, TestSupport | none |
| P1-M6 Storage | M4, M5 | Storage | none |
| P1-M7 Transport crypto and protocol | M4, M5 | Transport | none |
| P1-M8 Relay implementation | M7 fixtures | `relay/` | none |
| P1-M9 Relay synthetic-data gate | M7, M8 | Relay, Transport | Cloudflare deployment, 24-hour measurement, billing check |
| P1-M10 Codex adapter | M5 | ProviderAdapters | signed-in schema smoke test, profile selection |
| P1-M11 Claude Code adapter | M5 | ProviderAdapters | signed-in status-line calibration |
| P1-M12 Mac collector app | M6, M7, M10, M11 | Mac root | Keychain checks, eight-day re-read, timer drift |
| P1-M13 Mac UI | M12 | UI, Mac root | none |
| P1-M14 iOS core app | M6, M7, M9, M13 | iOS root | Sideloadly seven-day re-sign |
| P1-M15 Scheduling | M14 | Scheduling, widgets | widget, Live Activity, and background-timing checks on device |
| P1-M16 Watch | M14, M15 | WatchSync, Watch root | WatchConnectivity on a paired watch |

M6, M7 and M8 can proceed in parallel after M5; M10 and M11 can run in parallel with M6 to M9. Real data first flows end to end when M9 and M12 have both passed.

## Time-gated work

Start these as early as their milestone allows so elapsed time does not block the end of the phase:

- Relay 24-hour latency and capacity measurement, begun in P1-M9.
- Mac Keychain re-read eight days after signing, begun at the first signed build in P1-M12.
- Mac timer drift and iOS background-task intervals over 24 hours, begun in P1-M12 and P1-M15.
- Sideloadly seven-day refresh, begun at the first installable iOS build in P1-M14.

## Risks

| Risk | Response |
|---|---|
| The relay fails a synthetic-data criterion or exceeds Workers Free. | Record the failure and return the synchronization decision to the owner; P1-M14 onward does not start. |
| Provider output shape changes or a current-data window is rejected. | Treat the source as unavailable, not as a guessed value; return to the owner. |
| The Mac Keychain prompts after a rebuild or a lock. | Return the storage decision to the owner. |
| Free-account signing limits (seven-day expiry, 10 App IDs per week). | Keep bundle identifiers stable; use Sideloadly refresh and record each re-sign. |
| iOS and Watch regress while their tests are suspended. | The project still generates with every target, but the suspended runs do not execute; P1-M14 and P1-M16 must pass the complete gate before closing. |

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

The remaining milestones are planned only; each gets an overview file when it starts. The Mac is built before iOS. The iOS, iPad, and Watch `xcodebuild test` runs are suspended in the gate until P1-M14 re-enables the iOS and iPad runs and P1-M16 the Watch run.

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
Status: Planned
Goal: Envelope encryption, HMAC account scope, pairing payloads, non-interactive secret storage, the HTTPS relay client, and shared Swift/relay fixtures.
Plan: [overview](milestone-07-transport-overview.md), [sequencing](milestone-07-transport-sequence.md), [Transport](../architecture/transport.md)

### P1-M8: Relay implementation
Status: Planned
Goal: Worker and SQLite Durable Object with ciphertext-only storage, reader tokens with the three-reader cap, and the refresh-request mailbox.
Plan: [overview](milestone-08-relay-implementation-overview.md), [sequencing](milestone-08-relay-implementation-sequence.md), [relay](../architecture/relay.md)

### P1-M9: Relay synthetic-data gate
Status: Planned
Goal: Owner-run Cloudflare spike on synthetic data covering the conformance criteria and a US$0 billing check; real usage stays blocked until it passes.

### P1-M10: Codex adapter
Status: Planned
Goal: Codex app-server client, schema validation, current-data window, and explicit profile isolation, with source calibration.

### P1-M11: Claude Code adapter
Status: Planned
Goal: Claude Code status-line parser and guided installer that never replaces an unsafe or unprovable command, with source calibration.

### P1-M12: Mac collector app
Status: Planned
Goal: Mac composition root, Keychain secret store, publish loop, launch-at-login opt-in, and Release signing check, with Mac Keychain validation and timer-drift measurement.

### P1-M13: Mac UI
Status: Planned
Goal: Allowance Grid and rings, sidebar, menu-bar companion, Usage Details, and Settings.

### P1-M14: iOS core app
Status: Planned
Goal: Pairing, relay reader, Allowance Grid, Usage Details, Setup Banner, and Main Toolbar screens; re-enables the iPhone and iPad test runs in the gate.

### P1-M15: Scheduling
Status: Planned
Goal: Reset notifications, background refresh, widgets, and Live Activities, with their shared-state validation.

### P1-M16: Watch
Status: Planned
Goal: WatchSync, Watch app grid, complication, offline and stale display, and Forget Mac erasure; re-enables the Watch test run and closes the runtime security review table.
