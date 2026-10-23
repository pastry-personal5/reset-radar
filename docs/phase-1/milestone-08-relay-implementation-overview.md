# P1-M8: Relay implementation overview

Status: Planned

Implement the ciphertext-only Cloudflare Worker and SQLite-backed Durable Object in `relay/` against the [relay protocol](../architecture/relay.md) and the shared P1-M7 [Transport fixtures](milestone-07-transport-overview.md). The [sequence](milestone-08-relay-implementation-sequence.md) orders the work and identifies the tests and handoff to P1-M9.

## Goal

All ten relay operations enforce their approved authority, wire, state, and response contracts in local Workers Vitest tests. The Worker stores only the latest outer envelope and minimal protocol metadata, with at most three registered readers and three live refresh requests. The complete [contribution-guide gate](../contribution-guide.md#required-validation) passes with synthetic data; no live Cloudflare deployment or provider reading occurs in this milestone.

## Entry criteria

- [ ] The P1-M7 checkpoint A outer-envelope, request, response, error, and ETag fixtures are frozen and read directly by both language suites. Record the fixture revision and any cross-module review that changes it. Evidence: [M7 sequence](milestone-07-transport-sequence.md#task-1-shared-wire-fixtures-and-generator) and fixture tests.
- [ ] Record the starting commit and worktree state. Use an isolated baseline so unrelated Storage or Transport follow-up work is not attributed to M8. Evidence: `git status --short` and commit ID recorded below when implementation begins.
- [ ] The complete gate passes at the baseline before relay implementation. Evidence: command results recorded below; the `test_runner` performs command execution and first-pass failure analysis.
- [x] Plan review confirms the existing relay scaffold, ten protocol operations, v1 body profile, and M9 deployment boundary. Evidence: `relay/src/index.ts`, `relay/test/index.spec.ts`, `relay/wrangler.jsonc`, [relay design](../architecture/relay.md), and [phase plan](phase-1.md), reviewed 2026-10-23.

## In scope

- Strict TypeScript domain validation for canonical v1 JSON, exact outer-envelope metadata, safe-integer sequence bounds, route-specific request sizes, and stable response shapes and error codes. The Worker does not decrypt or validate plaintext.
- Worker routing, bounded-body handling, write and administration bearer-token checks against Worker-secret SHA-256 digests, constant-time comparison, generic errors, and one fixed-name Durable Object.
- SQLite state for one snapshot, up to three reader registrations, and the short-lived per-reader refresh-request mailbox. Mutations that bind a publisher, compare a sequence, enforce a cap or rate limit, revoke, acknowledge, or destroy are atomic.
- Reader preflight without activation, relay-assigned five-minute pending expiry, idempotent activation after local save, revocation, and the three-reader cap.
- Authenticated refresh requests with 128-bit opaque IDs, one pending request per reader, 60-second expiry and per-reader acceptance limit, non-consuming Mac reads, idempotent acknowledgement, and completed-ID replay rejection.
- Strong ETags over exact stored envelope bytes, authenticated conditional reads, operation-specific versioned bodies, and the approved response-size and cache-control rules.
- Local Workers Vitest coverage that consumes M7 fixtures, exercises the real Worker and Durable Object with synthetic tokens and ciphertext, and checks privacy and authority boundaries. Remove the scaffold-only `501` behavior and test.
- Existing npm typecheck, test, and deployment dry-run scripts; a safe local secret-provisioning procedure or script that accepts digests on standard input without echoing or persisting them in the repository. Any deployment command remains reserved for M9.

## Out of scope

- Owner-present Cloudflare deployment, Free-plan and billing checks, live quota response capture, 24-hour capacity and latency measurement, cellular path, promotion and rollback, and teardown evidence (P1-M9).
- Any real provider data, provider credentials, content key, plaintext snapshot, Mac or iOS composition-root wiring, push service, paid Cloudflare service, new dependency, or new build tool.
- Changing the approved v1 wire contract to make an implementation convenient. A required contract change goes through the M7 cross-module review and owner decision process before implementation.

## Completion checklist

- [ ] Entry criteria hold, including a recorded M7 fixture revision and clean baseline gate.
- [ ] The scaffold is replaced by the layered Worker and SQLite Durable Object described in the [relay design](../architecture/relay.md#internal-architecture); all ten routes work, and no unsupported route is mistaken for an empty first snapshot.
- [ ] Every operation enforces the approved role, bearer encoding, authentication-before-parse order, exact v1 request shape, route size limit, and generic bounded errors. Token-role crossover, missing secrets, malformed tokens, and direct invalid read tokens are rejected without leaking state.
- [ ] Snapshot tests prove first-publish binding, later publisher and sequence conflicts, both sides of the `2^53 - 1` boundary, exact 64 KiB limit, byte-preserving retrieval, strong ETag, authenticated `304`, and no snapshot state change on rejected requests.
- [ ] Reader tests prove pending preflight, save-then-activate, activation retry after a lost response or displayed expiry, pending expiry, activated-reader persistence, list ordering, revocation, and the three-reader cap with expired rows removed first.
- [ ] Refresh tests prove activation requirement, one live request per reader, same-ID retry, last-completed-ID replay, a different ID inside 60 seconds, expiry, sorted non-consuming Mac polling, idempotent acknowledgement, revocation cleanup, and at most three live requests.
- [ ] Destruction tests prove atomic state removal and repeatable `204`; successful responses, error rows, media types, no-store headers, body ceilings, and no intentional redirect match the shared fixtures and [relay response contract](../architecture/relay.md#v1-http-body-profile).
- [ ] Tests confirm the Durable Object has no plaintext usage, content key, provider credential, token bytes, or product history in persisted state or diagnostic output. Worker secrets are outside source, configuration, logs, and command arguments.
- [ ] The complete gate passes with `test_runner` evidence. The overview records results, affected docs and fixture notes are updated, and [phase-1.md](phase-1.md) moves to `Done` only after all acceptance evidence exists.

## Checkpoints

- **A: Wire and snapshot.** Freeze the M7 fixture revision; implement strict validation, routing and authentication, SQLite schema, snapshot binding, ordering, ETags, and exact responses. Run focused relay tests and the complete gate.
- **B: Readers and mailbox.** Implement reader lifecycle, refresh-request state and destruction with atomic transitions. Run concurrency, expiry, authority, and fixture-parity tests plus the complete gate.
- **C: Close-out.** Remove scaffold behavior, verify secret handling and all ten routes, run the complete gate from a clean checkout, record evidence, and hand M9 its deployed-conformance work.

## Implementation evidence

Record the baseline commit and worktree, M7 fixture revision, checkpoint commands/results, final gate results, and any approved protocol changes here when work starts. Planning and the scaffold smoke test do not count as implementation evidence.

## Plan validation

On 2026-10-23, the `test_runner` ran the complete contribution-guide gate for the current planning worktree. Project generation, Swift formatting lint, strict SwiftLint, import checks, Mac `xcodebuild test` (83 tests in 15 suites plus the Mac smoke test), relay `npm ci`, Workers Vitest (2 scaffold tests), typecheck, and Wrangler dry run passed. The first Apple-side attempts hit sandbox cache and CoreSimulator restrictions; the runner reran those commands with approved host cache access and they passed. This validates the plan edit against the current scaffold, not M8's future isolated baseline or implementation.

## Risks

- **Fixture timing.** M7 is still `Planned` and `Fixtures/Protocol/` contains only a scaffold marker. M8 implementation waits for its frozen checkpoint A fixtures; plan writing does not waive that dependency.
- **Atomicity.** Separate reads and writes could admit duplicate sequences, a fourth reader, or an extra manual request. Put each decision and its state change in one Durable Object storage transaction and test competing requests.
- **Privacy and cost.** Worker diagnostics or a provisioning command could expose tokens; deployed limits and US$0 billing cannot be proven locally. M8 checks local secret handling and passes the synthetic-only implementation to M9 for the owner-run Cloudflare gate.
