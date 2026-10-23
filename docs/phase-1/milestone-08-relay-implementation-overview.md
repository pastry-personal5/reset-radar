# P1-M8: Relay implementation overview

Status: Active

Implement the ciphertext-only Cloudflare Worker and SQLite-backed Durable Object in `relay/` against the [relay protocol](../architecture/relay.md) and the shared P1-M7 [Transport fixtures](milestone-07-transport-overview.md). The [sequence](milestone-08-relay-implementation-sequence.md) orders the work and identifies the tests and handoff to P1-M9.

## Goal

All ten relay operations enforce their approved authority, wire, state, and response contracts in local Workers Vitest tests. The Worker stores only the latest outer envelope and minimal protocol metadata, with at most three registered readers and three live refresh requests. The complete [contribution-guide gate](../contribution-guide.md#required-validation) passes with synthetic data; no live Cloudflare deployment or provider reading occurs in this milestone.

## Entry criteria

- [x] The P1-M7 checkpoint A outer-envelope, request, response, error, and ETag fixtures are frozen and read directly by both language suites. Fixture revision: `5d69907210abdf502a855136c6cd00900c0dde80314e7995886f40ce901d5c81`; see the [fixture README](../../Fixtures/Protocol/README.md) and M7 final evidence. Any change requires cross-module review.
- [ ] Record the starting commit and worktree state. Use an isolated baseline so unrelated Storage or Transport follow-up work is not attributed to M8. Evidence: `git status --short` and commit ID recorded below when implementation begins. The starting state is recorded; isolation remains open because of pre-existing worktree changes.
- [x] The complete gate passes at the baseline before relay implementation. Evidence: command results recorded below; the `test_runner` performs command execution and first-pass failure analysis.
- [x] Plan review confirms the scaffold, ten operations, v1 body profile, and M9 deployment boundary, and identifies the registration-retry and completed-ID state questions below. Evidence: `relay/src/index.ts`, `relay/test/index.spec.ts`, `relay/wrangler.jsonc`, [relay design](../architecture/relay.md), [Transport wire profile](../architecture/transport.md#v1-wire-profile), and [phase plan](phase-1.md), reviewed 2026-10-23.

## In scope

- Strict TypeScript domain validation for canonical v1 JSON, exact outer-envelope metadata, safe-integer sequence bounds, route-specific request sizes, and stable response shapes and error codes. The Worker does not decrypt or validate plaintext.
- Worker routing, bounded-body handling, write and administration bearer-token checks against Worker-secret SHA-256 digests, constant-time comparison, generic errors, and one fixed-name Durable Object.
- SQLite state for one snapshot, up to three reader registrations, and the short-lived per-reader refresh-request mailbox. Mutations that bind a publisher, compare a sequence, enforce a cap or rate limit, revoke, acknowledge, or destroy are atomic.
- Reader preflight without activation, relay-assigned five-minute pending expiry, idempotent activation after local save, revocation, and the three-reader cap.
- Authenticated refresh requests with 128-bit opaque IDs, one pending request per reader, 60-second expiry and per-reader acceptance limit, non-consuming Mac reads, idempotent acknowledgement, and completed-ID replay rejection.
- Fail-closed handling of registration collisions, duplicate token digests, and request-ID state across acceptance, acknowledgement, expiry, and later requests under the approved decisions below.
- Strong ETags over exact stored envelope bytes, authenticated conditional reads, operation-specific versioned bodies, and the approved response-size and cache-control rules.
- Local Workers Vitest coverage that consumes M7 fixtures, exercises the real Worker and Durable Object with synthetic tokens and ciphertext, and checks privacy and authority boundaries. Remove the scaffold-only `501` behavior and test.
- Existing npm typecheck, test, and deployment dry-run scripts; a safe local secret-provisioning procedure or script that accepts digests on standard input without echoing or persisting them in the repository. Any deployment command remains reserved for M9.

## Out of scope

- Owner-present Cloudflare deployment, Free-plan and billing checks, live quota response capture, 24-hour capacity and latency measurement, cellular path, promotion and rollback, and teardown evidence (P1-M9).
- Any real provider data, provider credentials, content key, plaintext snapshot, Mac or iOS composition-root wiring, push service, paid Cloudflare service, new dependency, or new build tool.
- Changing the approved v1 wire contract to make an implementation convenient. A required contract change goes through the M7 cross-module review and owner decision process before implementation.

## Completion checklist

- [ ] Entry criteria hold, including a recorded M7 fixture revision and clean baseline gate.
- [x] The two contract question groups below have owner-approved outcomes, recorded in the changelog and shared fixtures before their state machines are implemented. Evidence: the M7 fixture revision `5d69907210abdf502a855136c6cd00900c0dde80314e7995886f40ce901d5c81` includes all eight approved collision and replay scenarios.
- [ ] The scaffold is replaced by the layered Worker and SQLite Durable Object described in the [relay design](../architecture/relay.md#internal-architecture); all ten routes work, and no unsupported route is mistaken for an empty first snapshot.
- [ ] The SQLite state has an explicit schema version; an incompatible version fails closed without reading or changing relay state. Evidence: a Workers Vitest schema-version test.
- [ ] Every operation enforces the approved role, bearer encoding, authentication-before-parse order, exact v1 request shape, route size limit, and generic bounded errors. Token-role crossover, missing secrets, malformed tokens, and direct invalid read tokens are rejected without leaking state or mutating storage.
- [ ] Snapshot tests prove first-publish binding, later publisher and sequence conflicts, both sides of the `2^53 - 1` boundary, the 64 KiB byte-reader limit and largest valid envelope below it, byte-preserving retrieval, strong ETag, authenticated `304`, and no snapshot state change on rejected requests.
- [ ] Reader tests prove pending preflight, save-then-activate, activation retry after a lost response or displayed expiry, pending expiry, activated-reader persistence, list ordering, revocation, and the three-reader cap with expired rows removed first. Duplicate IDs and digests never replace or activate an existing reader; their approved outcomes are tested.
- [ ] Refresh tests prove activation requirement, one live request per reader, same-ID retry with its original expiry, last-completed-ID replay even while a newer request is pending, a different ID inside 60 seconds, expiry, cross-reader ID collision, sorted non-consuming Mac polling, idempotent acknowledgement, revocation cleanup, and at most three live requests.
- [ ] Destruction tests prove atomic state removal and repeatable `204`; successful responses, error rows, media types, no-store headers, body ceilings, and no intentional redirect match the shared fixtures and [relay response contract](../architecture/relay.md#v1-http-body-profile).
- [ ] Tests confirm the Durable Object has no plaintext usage, content key, provider credential, token bytes, or product history in persisted state or diagnostic output. Worker secrets are outside source, configuration, logs, and command arguments.
- [ ] The complete gate passes with `test_runner` evidence. The overview records results, affected docs and fixture notes are updated, and P1-M8 in [phase-1.md](phase-1.md) moves to `Done` only after all acceptance evidence exists.

## Checkpoints

- **A: Wire and snapshot.** Freeze the M7 fixture revision; implement strict validation, routing and authentication, SQLite schema, snapshot binding, ordering, ETags, and exact responses. Run focused relay tests and typecheck.
- **B: Readers and mailbox.** Implement reader lifecycle, refresh-request state and destruction with atomic transitions. Run focused concurrency, expiry, authority, fixture-parity, and typecheck checks.
- **C: Close-out.** Remove scaffold behavior, verify secret handling and all ten routes, run the complete gate on the reviewable implementation worktree, record evidence, and hand M9 its deployed-conformance work.

## Owner decisions for registration and refresh IDs

On 2026-10-23, the owner approved returning the original expiry for a repeated `PUT /v1/readers/{id}` with the same ID and digest. An existing ID with a changed digest, a digest bound to another reader, or a digest matching a write or administration token returns generic `400 badRequest` without mutation. An expired pending row may be removed before a new registration. M7 must pin these outcomes in shared fixtures; its existing `400` Transport mapping applies.

The owner also approved separate per-reader last-accepted and last-completed request IDs. A retry of the last accepted ID after its request expires, or an ID live for another reader, returns generic `400 badRequest` without mutation. The last completed ID remains a `409 requestAlreadyCompleted` even while a newer request is pending. The last-accepted guard is bounded: accepting a different ID replaces it; an older expired ID is then no longer remembered unless it is also the last completed ID. M7 must pin these cases in shared fixtures. Acceptance alone never marks an ID completed.

## Implementation evidence

### M8 implementation checklist

- [x] Replace the relay scaffold with the fixture-backed Worker and SQLite Durable Object, with local Workers Vitest evidence for all ten operations. Evidence: 13 Workers Vitest tests pass against the real Worker and SQLite Durable Object on 2026-10-23.

The relay package provides `npm run secrets:provision` for the owner-run M9 deployment step. It accepts the distinct write and administration SHA-256 digests as exactly two lowercase-hex lines on standard input and supplies each only to `wrangler secret put`; it neither echoes nor writes either value into the repository or command arguments.

Starting commit on 2026-10-23: `393334d`. The M8 implementation began from `353043d` with the existing M7 handoff and planning worktree changes shown by `git status --short`; those files, including the Transport implementation and `Fixtures/Protocol/`, predate the request and are preserved. M7 completed its fixture handoff at revision `5d69907210abdf502a855136c6cd00900c0dde80314e7995886f40ce901d5c81`; `Fixtures/Protocol/` contains the frozen envelope, pairing, operation, error, and collision/retry scenario bytes consumed directly by the relay tests. The prior baseline-gate record remains baseline evidence, not relay implementation acceptance.

M8 close-out validation on 2026-10-23 passed: the `test_runner` ran `npm --prefix relay ci`, 13 Workers Vitest tests, TypeScript typecheck, Wrangler deployment dry-run, `swift-format` lint, strict SwiftLint (zero violations), and `git diff --check`. Its sandbox could not access Xcode and CoreSimulator caches; with approved host-cache access, project generation, import checks, and `xcodebuild test -scheme ResetRadarMac -destination 'platform=macOS'` also passed (85 package tests in 16 suites plus the Mac smoke test). The secret-provisioning script rejected invalid standard input with exit 2 without invoking Wrangler. No Cloudflare deployment or live data access occurred.

M7 checkpoint A and its final gate are complete. When M8 resumes, record its isolated starting state and consume the fixture revision above; planning and the scaffold smoke test do not count as implementation evidence.

After recording the owner's decisions, the `test_runner` reran the complete contribution-guide gate on the documentation worktree: project generation, Swift format lint, strict SwiftLint (zero violations across 183 files), import check, Mac tests, two scaffold relay Vitest tests, TypeScript typecheck, and Wrangler dry run passed. npm dependency materialization needed a permitted host-access retry. `git diff --check` passed. This validates the documented decisions, not M8 implementation.

## Plan validation

On 2026-10-23, the `test_runner` ran the complete contribution-guide gate for the current planning worktree. Project generation, Swift formatting lint, strict SwiftLint, import checks, Mac `xcodebuild test` (83 tests in 15 suites plus the Mac smoke test), relay `npm ci`, Workers Vitest (2 scaffold tests), typecheck, and Wrangler dry run passed. The first Apple-side attempts hit sandbox cache and CoreSimulator restrictions; the runner reran those commands with approved host cache access and they passed. This validates the plan edit against the current scaffold, not M8's future isolated baseline or implementation.

After this review's edits, the `test_runner` reran the complete gate on 2026-10-23. Project generation, format lint, strict SwiftLint (zero violations), import check, Mac `xcodebuild test` (84 package tests in 16 suites plus the Mac smoke test), relay `npm ci`, two scaffold Vitest tests, typecheck, and Wrangler dry run passed. The Apple-side commands again needed approved host cache and CoreSimulator access after sandbox failures. `git diff --check` and the documentation link check passed. This is plan validation only; the M8 implementation baseline and acceptance gate remain open.

## Risks

- **Fixture drift.** M7 is `Done` with frozen revision `5d69907210abdf502a855136c6cd00900c0dde80314e7995886f40ce901d5c81`. M8 must consume these files directly; a protocol change requires cross-module review.
- **Atomicity.** Separate reads and writes could admit duplicate sequences, a fourth reader, or an extra manual request. Put each decision and its state change in one Durable Object storage transaction and test competing requests. An unauthenticated read must not trigger expiry cleanup.
- **Privacy and cost.** Worker diagnostics or a provisioning command could expose tokens; deployed limits and US$0 billing cannot be proven locally. M8 checks local secret handling and passes the synthetic-only implementation to M9 for the owner-run Cloudflare gate.
