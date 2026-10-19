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
- Validation spikes required by [owner-decisions.md](owner-decisions.md), using synthetic data unless the owner separately authorizes a signed-in smoke test.
- Failure, migration, installation, update, and removal behavior needed to scaffold safely.

## Out of scope

- Production app implementation or the production Xcode project; those belong to P1-M3 and later implementation milestones.
- New product scope, provider credentials, private consumer endpoints, API-key mode, APNs, multiple publishing Macs, analytics, or paid services.
- Visual styling and branding assets beyond architecture-affecting interface structure.
- Real usage data in the Cloudflare relay before its synthetic-data gate passes.

## Deliverables

- [Software architecture](milestone-02-software-architecture.md), promoted from `Proposal` to `Active` after owner review.
- Bounded spike results and reproducible evidence for every conditional architecture choice.
- Updated owner decisions, product behavior, UX documents, and contribution instructions where the accepted architecture affects them.

## Completion checklist

- [ ] The owner resolves every architecture-affecting product or process question discovered during review.
- [ ] Target/module ownership and dependency direction are documented for the iPhone app, widgets, Live Activity, watch app, Mac collector, shared model, and relay.
- [ ] The window and latest-observation model defines identities, reset semantics, source provenance, freshness, unavailability, validation, serialization, and migrations without assuming exactly two windows.
- [ ] Mac provider adapters define process lifecycle, compatibility negotiation, timeouts, backoff, schema fixtures, privacy-safe logging, and stale transitions.
- [ ] Pairing, key storage, envelope encryption, replay protection, authority, deletion, recovery, and device-loss behavior are documented.
- [ ] The Cloudflare synthetic-data spike passes every criterion in the approved research, or the failed condition and resulting owner decision are recorded. No real provider data is used.
- [ ] iPhone-to-watch transfer, offline cache, complication/app presentation boundary, stale state, and seven-day refresh preservation are documented and validated as far as possible before scaffolding.
- [ ] Reset calculation and notification scheduling cover selected-zone recurrence, OS-local display, DST, time-zone changes, pending-request management, and clock changes.
- [ ] Widget, Live Activity, and App Intent ownership and lifecycle behavior are documented; required synthetic lifecycle spikes are recorded.
- [ ] Local development signing, launch at login, CLI child-process access, safe update, uninstall cleanup, and owner-readable recovery instructions are specified for the Mac collector.
- [ ] Security, privacy, and failure-mode review finds no path that copies provider credentials, exposes plaintext to Cloudflare, fabricates usage, or silently upgrades a free service.
- [ ] A P1-M3 scaffolding map lists targets, packages, entitlements, build configurations, test bundles, fixtures, and the first complete-gate command sequence.
- [ ] The owner reviews the architecture and the approval is recorded in [changelog.md](changelog.md).
- [ ] Every applicable gate check passes; commands structurally inapplicable before P1-M3 are attempted, recorded, and explicitly deferred under the pre-scaffolding exception.

