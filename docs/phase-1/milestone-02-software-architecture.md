# Software architecture

Status: Proposal

Implementation architecture for the Reset Radar iPhone, Apple Watch, and Mac system. This document becomes binding after its validation evidence and owner review are complete.

## Approved constraints

The architecture must implement [product-behavior.md](../product-behavior.md) within the binding boundaries in [owner-decisions.md](owner-decisions.md). In particular, provider credentials stay owned by first-party tools, Cloudflare receives only ciphertext and minimal protocol metadata, one Mac is authoritative, percentages are coding-allowance observations rather than inferred values, and stale or unavailable state is explicit.

## Architecture sections to complete

1. System context and trust boundaries.
2. Xcode targets, Swift packages, modules, and dependency direction.
3. Window, reset rule, observation, provenance, freshness, and availability model.
4. Persistence, serialization, schema versioning, and migration.
5. Codex and Claude Code Mac adapters.
6. Pairing, keys, encrypted envelope, relay protocol, replay defense, and deletion.
7. iPhone ingestion, cache authority, background opportunities, and failure behavior.
8. WatchConnectivity transfer and watch offline behavior.
9. Notification calculation and rescheduling.
10. Widgets, Live Activities, and App Intent data access and lifecycle.
11. Mac launch, signing, update, diagnostics, and uninstall behavior.
12. Test architecture, fixtures, validation spikes, and scaffolding map.

## Open architecture review

The research questions are resolved. Before this proposal is filled in, the owner must resolve any mismatch between the repository's binding UX references and their current `TBD` contents; architecture must not invent navigation, containment, or interaction behavior that those documents claim to define.

