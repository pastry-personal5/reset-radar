# Phase 1: Foundation

Status: Active

Goal: Settle what Reset Radar must do and how it is built, then stand up a project that builds and passes the gate.

## Exit criteria

- Research findings are written down and the product scope in [product-behavior.md](../product-behavior.md) is filled in from them.
- The software architecture is documented and every related "Undecided" item in [AGENTS.md](../../AGENTS.md) is resolved or consciously deferred.
- An Xcode project targeting iOS and iPadOS 26.6.2+, watchOS 26.6+, and macOS 26.7.1+ builds with the `ResetRadar`, `ResetRadarMac`, and `ResetRadarWatch` schemes, and the full gate passes on the simulator destinations in [Platform targets](../architecture.md#platform-targets) with empty-but-real app, watch app, and test targets.

## Milestones

### P1-M1: Initial research
Status: Done
Goal: Produce sourced feasibility studies on allowance-usage tracking, reset times, available data, iOS capabilities, distribution, and prior art.
Plan: [overview](milestone-01-research-overview.md)

### P1-M2: Software architecture
Status: Active
Goal: Choose and document the Apple-platform structure, window/observation model, Mac provider adapters, iPhone-to-watch data flow, authenticated synchronization, reset scheduling, and notification approach based on the P1-M1 findings.
Plan: [overview](milestone-02-software-architecture-overview.md), [architecture](../architecture.md)

### P1-M3: Scaffolding
Status: Planned
Goal: Create the Xcode project, all composition-root and test targets, the `ResetRadarKit` package, the relay package, SwiftLint and swift-format config, and a complete gate that passes with no deferrals and matches the P1-M2 architecture.
Plan: [overview](milestone-03-scaffolding-overview.md), [sequencing](milestone-03-scaffolding-architecture.md), [repository layout](../architecture/repository-layout.md)
