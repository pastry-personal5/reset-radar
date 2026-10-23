# P1-M8: Relay implementation sequence

Status: Planned

Work order and acceptance tests for the [M8 overview](milestone-08-relay-implementation-overview.md). The [relay design](../architecture/relay.md) and the M7 [v1 wire fixtures](milestone-07-transport-sequence.md#task-1-shared-wire-fixtures-and-generator) define behavior; this file identifies implementation seams and local verification before the P1-M9 Cloudflare gate.

## Constraints

- Keep production code in `relay/src/`, tests in `relay/test/`, and shared protocol JSON in `Fixtures/Protocol/`. `domain` and `application` have no Cloudflare imports; runtime adapters and `src/index.ts` own Worker and Durable Object APIs.
- Use the existing pinned Node, npm, Wrangler, TypeScript, and Workers Vitest dependencies and configuration. Do not introduce a new dependency, build tool, paid binding, log stream, alarm, WebSocket, provider integration, or live deployment.
- Use only synthetic ciphertext, IDs, and token bytes in tests. The content key and plaintext snapshot never enter a Worker test request or persisted Durable Object row.
- Preserve the [v1 HTTP body profile](../architecture/relay.md#v1-http-body-profile): compact sorted-key JSON, exact fields, UTC millisecond times, safe integer sequences, strong ETag, operation-specific errors, and the approved size limits. Read the same fixture files as Swift; never copy fixture bytes into TypeScript constants.
- Run focused relay tests while iterating and the complete [gate](../contribution-guide.md#required-validation) at checkpoints and close-out. Delegate command execution and first-pass failure analysis to `test_runner`; retain implementation and final judgment in the main thread.

## Task 0: Baseline and fixture handoff

Record the starting commit, worktree state, complete baseline gate, and M7 checkpoint A fixture revision in the overview. Inspect the fixture manifest and verify the TypeScript tests can load it from the checked-in path under Workers Vitest. Check that envelope, all ten request/response forms, errors, and ETag bytes agree with the current relay and Transport designs. A discrepancy goes back to the M7 cross-module review before writing an alternate Worker interpretation. Keep unrelated work out of M8 evidence.

## Task 1: Domain protocol and bounded HTTP edge

Implement pure validators and serializers for IDs, versions, canonical outer-envelope fields, safe integer sequence, token encoding, request bodies, response bodies, and error codes. Reject unknown or duplicate JSON fields and noncanonical encodings; do not parse or log ciphertext as a usage snapshot. Read request bodies with an actual byte counter, stopping at 64 KiB for snapshot PUT and 128 bytes for refresh POST; document and test a finite limit for the small reader-registration body before implementation. Refuse request bodies on bodyless routes. Return only approved compact responses, with error bodies at most 4 KiB and no intentional redirect.

Tests load literal M7 fixtures and mutations of them. Cover one byte below, at, and above each bound; false or absent `Content-Length`; malformed JSON and UTF-8; duplicate or unknown fields; unsupported mandatory versions; malformed IDs and base64url; `9007199254740991` and its next integer; and exact response bytes, content type, and limits. A rejected request does not reach a storage mutation.

## Task 2: Worker entry, authority, and storage adapter

Replace `src/index.ts`'s `501` stub with the Worker router and `RelayObject`. Route a fixed-name object only after the Worker authenticates write or administration calls; read-token authorization occurs inside the object against stored digests. Decode exactly 32 raw bearer-token bytes, hash those bytes with SHA-256, and compare digests in constant time. Use Worker-secret digest bindings for write and administration authority; absent or malformed secrets fail closed. Check authority before parsing a body beyond its size check. Never put a bearer token in a URL, error, log, SQL statement, or persisted row.

Add a versioned SQLite schema for the latest envelope, readers, and refresh requests, with an explicit upgrade path or fail-closed incompatible-state result. Store byte-exact envelope text and ETag, the bound publisher and last sequence, reader digests and minimal rate-limit state, and opaque request metadata only. Keep storage decisions inside transactions; inject a clock for deadline and rate-limit tests. Provisioning reads digests through standard input without echo and writes only Worker secrets; local tests use synthetic secret bindings and do not call Cloudflare.

Tests use `SELF` and Durable Object test facilities to exercise the real entry point. Cover role crossover, unknown and revoked tokens, absent bindings, malformed auth before malformed body, route and method confusion, generic error bytes, and absence of sensitive values from responses and stored rows. Check that local configuration retains the approved single SQLite binding, `workers.dev`, and disabled observability.

## Task 3: Snapshot state machine

Implement `PUT` and `GET /v1/snapshot`. The first valid write atomically binds publisher and sequence; later writes require the same publisher and a strictly greater sequence. Preserve the exact accepted envelope bytes, compute the strong SHA-256 ETag over those bytes, and return it on write and read. Authenticate a read before comparing `If-None-Match`; return `304` only when a snapshot exists and the validator matches. A pending unexpired reader may preflight-read without becoming activated. Return the distinct authenticated first-publish `404` only when no snapshot exists.

Tests cover first binding, byte-for-byte retrieval, equal/older/concurrent writes, publisher mismatch, rejected version and size, ETag vectors, conditional/unconditional reads, pending preflight, unknown-route `404`, and retained state after every rejection. The sequence comparison stays exact at the v1 maximum. **Checkpoint A:** focused tests and complete gate pass with the fixture revision recorded.

## Task 4: Reader lifecycle

Implement administration `PUT`, `GET`, and `DELETE /v1/readers/{id}` plus read-token `POST /v1/readers/activate`. Registration records only a digest and a relay-assigned five-minute pending expiry. Remove expired unactivated rows before reader work and cap checks; activated readers survive their former deadline. Derive activation identity from the presented token, ignore any client-supplied reader ID for activation, and make an already-activated retry return the same success even after the displayed deadline. List reader IDs in order with only activation flags; revocation removes that reader and any pending request atomically.

Tests cover three registrations and a fourth rejection, an expired slot becoming reusable, preflight without activation, local-save failure simulated by never calling activate, activation and a lost-response retry, expiry denial, activated survival, list ordering, revocation, and malformed registration. Competing registrations cannot exceed three rows.

## Task 5: Refresh-request mailbox

Implement activated-reader `POST /v1/refresh-requests` and write-token `GET` and `DELETE /v1/refresh-requests/{id}`. Accept one live request per reader for 60 seconds, return the original expiry on a same-ID pending retry, reject the last completed ID, and rate-limit a different ID within 60 seconds of the last accepted request. The Mac's list read is non-consuming and sorted by reader then request ID; successful acknowledgement and expiration remove a request but do not reset the reader's acceptance time. Reader revocation and relay destruction remove requests.

Tests use an injected clock and competing calls to cover every same-ID/different-ID ordering, all three readers, exact deadline and rate-limit edges, Mac polling after a simulated crash, duplicate acknowledgement, revocation, expiry, wrong role, and lack of a forced provider read on rejected calls. Only opaque IDs and times are stored or returned.

## Task 6: Destruction, parity, and close-out

Implement administration `DELETE /v1/relay` as an atomic deletion of all active object state; repeat deletion returns `204`. Verify a new setup can bind a new publisher after destruction and that old reader digests and requests no longer authorize or appear. Remove the placeholder source behavior, scaffold fixture marker dependency, and scaffold-only smoke test. Check all ten operations against the same checked-in fixtures, including status, error code, headers, exact JSON, and response-size ceiling.

Run the complete gate with `test_runner`, inspect `git diff --stat` and then the full diff, record accepted evidence in the overview, and update the docs index, phase plan, and changelog. Mark M8 `Done` only when the checklist and gate pass. Hand M9 the version, synthetic fixtures, secret-provisioning steps, and open deployed checks: Free billing, actual platform quota response, 24-hour capacity and latency, cellular retrieval, promotion/rollback, and teardown. **Checkpoint B and close-out:** no real usage reaches Cloudflare.

## Review focus

1. Authentication precedes body parsing except for a strict size limit, and failures do not reveal whether a token, reader, or publisher exists.
2. Every multi-step state decision is atomic under competing requests; a retry after a lost response has the documented result.
3. The relay treats ciphertext as opaque bytes and stores no history, plaintext, key, provider credential, or raw token.
4. The strong ETag hashes the exact bytes returned to readers; `304` requires an authenticated reader and an existing snapshot.
5. Local tests establish implementation behavior only. M9 owns platform-generated quota, deployed Free-plan, capacity, billing, and real network evidence.
