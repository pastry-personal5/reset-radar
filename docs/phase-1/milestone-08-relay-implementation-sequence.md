# P1-M8: Relay implementation sequence

Status: Active

Work order and acceptance tests for the [M8 overview](milestone-08-relay-implementation-overview.md). The [relay design](../architecture/relay.md) and the M7 [v1 wire fixtures](milestone-07-transport-sequence.md#task-1-shared-wire-fixtures-and-generator) define behavior; this file identifies implementation seams and local verification before the P1-M9 Cloudflare gate.

## Constraints

- Keep production code in `relay/src/`, tests in `relay/test/`, and shared protocol JSON in `Fixtures/Protocol/`. `domain` and `application` have no Cloudflare imports; runtime adapters and `src/index.ts` own Worker and Durable Object APIs.
- Use the existing pinned Node, npm, Wrangler, TypeScript, and Workers Vitest dependencies and configuration. Do not introduce a new dependency, build tool, paid binding, log stream, alarm, WebSocket, provider integration, or live deployment.
- Use only synthetic ciphertext, IDs, and token bytes in tests. The content key and plaintext snapshot never enter a Worker test request or persisted Durable Object row.
- Preserve the [v1 HTTP body profile](../architecture/relay.md#v1-http-body-profile): compact sorted-key JSON, exact fields, UTC millisecond times, safe integer sequences, strong ETag, operation-specific errors, and the approved size limits. Read the same fixture files as Swift; never copy fixture bytes into TypeScript constants.
- Apply the two approved [registration and refresh-ID decisions](milestone-08-relay-implementation-overview.md#owner-decisions-for-registration-and-refresh-ids) in the shared fixtures before the affected state machines are written. A locally convenient response code or replay rule does not amend the approved shared protocol.
- Run focused relay tests and typecheck while iterating, then the complete [gate](../contribution-guide.md#required-validation) once at close-out. Delegate command execution and first-pass failure analysis to `test_runner`; retain implementation and final judgment in the main thread.

## Task 0: Baseline and fixture handoff

Record the starting commit, worktree state, complete baseline gate, and M7 checkpoint A fixture revision in the overview. Inspect the fixture manifest and verify the TypeScript tests can load it from the checked-in path under Workers Vitest. Check that the envelope, all ten operation forms, each success and error shape, and ETag bytes agree with the current relay and Transport designs. A discrepancy goes back to the M7 cross-module review before writing an alternate Worker interpretation. Keep unrelated work out of M8 evidence.

## Task 1: Domain protocol and bounded HTTP edge

Implement pure validators and serializers for IDs, versions, canonical outer-envelope fields, safe integer sequence, token encoding, request bodies, response bodies, and error codes. Reject unknown or duplicate JSON fields and noncanonical encodings by round-tripping the complete accepted byte string; ordinary `JSON.parse` alone cannot detect duplicate keys. Do not parse or log ciphertext as a usage snapshot. Count actual streamed request bytes, stopping at 64 KiB for snapshot PUT, 128 bytes for refresh POST, and a documented finite registration-body cap that includes its complete canonical fixture. Ignore absent or deceptive `Content-Length` for enforcement. Refuse any bytes on bodyless routes, reject an unexpected media type on JSON routes, and reject query-bearing or otherwise unapproved route forms. Return only approved compact responses, with error bodies at most 4 KiB and no intentional redirect.

Tests load literal M7 fixtures and mutations of them. Test the byte reader at one byte below, at, and above each cap; separately test the largest *valid canonical* envelope and registration/request bodies that fit their caps. A fixed-shape canonical JSON body may have no valid representation at the cap itself. Cover false or absent `Content-Length`; malformed JSON and UTF-8; whitespace, key order, duplicate or unknown fields; unsupported mandatory versions; malformed IDs and base64url; `9007199254740991` and its next integer; exact response bytes, content type, and limits. A rejected request does not reach a storage mutation.

## Task 2: Worker entry, authority, and storage adapter

Replace `src/index.ts`'s `501` stub with the Worker router and `RelayObject`. Route a fixed-name object only after the Worker authenticates write or administration calls; read-token authorization occurs inside the object against stored digests. Decode exactly 32 raw bearer-token bytes, hash those bytes with SHA-256, and compare digests in constant time. Use Worker-secret digest bindings for write and administration authority; absent, malformed, or equal role digests fail closed. Check authority before parsing a body beyond its size check. Do not forward an unauthenticated internal-authority header or let a client supply one. Never put a bearer token in a URL, error, log, SQL statement, or persisted row.

Add a versioned SQLite schema for the latest envelope, readers, and refresh requests, with an explicit upgrade path or fail-closed incompatible-state result. Store byte-exact envelope text and ETag, the bound publisher and last sequence, reader digests and minimal rate-limit/replay state, and opaque request metadata only. Keep each check-and-mutate decision inside a transaction; inject a clock for deadline and rate-limit tests. A missing or invalid read token may cause a lookup but no expiry cleanup or other write. Provisioning reads digests through standard input without echo and writes only Worker secrets; local tests use synthetic secret bindings and do not call Cloudflare.

Tests use `SELF` and Durable Object test facilities to exercise the real entry point and inspect storage where the harness allows it. Cover role crossover, equal write/admin digests, unknown and revoked tokens, absent bindings, malformed auth before malformed body, route and method confusion, generic error bytes, and absence of sensitive values from responses and stored rows. Assert that an invalid read token causes no database write, including when expired rows exist. Check that local configuration retains the approved single SQLite binding, `workers.dev`, and disabled observability.

## Task 3: Snapshot state machine

Implement `PUT` and `GET /v1/snapshot`. The first valid write atomically binds publisher and sequence; later writes require the same publisher and a strictly greater sequence. Preserve the exact accepted envelope bytes, compute the strong SHA-256 ETag over those bytes, and return it on write and read. Authenticate a read before comparing `If-None-Match`; return `304` only when a snapshot exists and the validator matches. A pending unexpired reader may preflight-read without becoming activated. Return the distinct authenticated first-publish `404` only when no snapshot exists.

Tests cover first binding, byte-for-byte retrieval, equal/older/concurrent writes, publisher mismatch, rejected version and size, ETag vectors, conditional/unconditional reads, pending preflight, unknown-route `404`, and retained state after every rejection. The sequence comparison stays exact at the v1 maximum. **Checkpoint A:** focused tests and complete gate pass with the fixture revision recorded.

## Task 4: Reader lifecycle

Implement administration `PUT`, `GET`, and `DELETE /v1/readers/{id}` plus read-token `POST /v1/readers/activate`. Registration records only a digest and a relay-assigned five-minute pending expiry. After successful authority checks, remove expired unactivated rows before reader work and cap checks; expired tokens cannot preflight or activate, and activated readers survive their former deadline. Derive activation identity from the presented token, ignore any client-supplied reader ID for activation, and make an already-activated retry return the same success even after the displayed deadline. An existing ID with the same digest returns its original expiry; changed or reused digests, including a privileged-role digest, return `400 badRequest` without mutation. List reader IDs in order with only activation flags; revocation removes that reader and any pending request atomically.

Tests cover three registrations and a fourth rejection, an expired slot becoming reusable, preflight without activation, local-save failure simulated by never calling activate, activation and a lost-response retry, expiry denial, activated survival, list ordering, revocation, malformed registration, exact registration retry, ID collision, and digest collision. A rejected collision does not alter the old activation or expiry. Competing registrations cannot exceed three rows.

## Task 5: Refresh-request mailbox

Implement activated-reader `POST /v1/refresh-requests` and write-token `GET` and `DELETE /v1/refresh-requests/{id}`. Accept one live request per reader for 60 seconds, return the original expiry on a same-ID pending retry, reject the last completed ID with `409 requestAlreadyCompleted`, and rate-limit a different ID within 60 seconds of the last accepted request. Keep live request IDs unique across readers because acknowledgement identifies only the request ID; a cross-reader collision returns `400 badRequest`. Track last accepted time and ID separately from the last completed ID so accepting a newer pending request cannot erase the completed-ID replay guard. Retrying the last accepted ID after expiry returns `400 badRequest` without calling it completed; a later different acceptance replaces this bounded guard. The Mac's list read is non-consuming and sorted by reader then request ID; successful acknowledgement and expiration remove a request but do not reset the reader's acceptance time. Reader revocation and relay destruction remove requests.

Tests use an injected clock and competing calls to cover same-ID/different-ID ordering, completed A replay while newer B is pending, cross-reader live-ID collision, all three readers, exact deadline and rate-limit edges, retry after expiry, Mac polling after a simulated crash, duplicate acknowledgement, revocation, wrong role, and no rejected request appearing in the Mac poll result. Only opaque IDs and times are stored or returned.

## Task 6: Destruction, parity, and close-out

Implement administration `DELETE /v1/relay` as an atomic deletion of all active object state; repeat deletion returns `204`. Verify a new setup can bind a new publisher after destruction and that old reader digests and requests no longer authorize or appear. Remove the placeholder source behavior, scaffold fixture marker dependency, and scaffold-only smoke test. Check all ten operations against the same checked-in fixtures, including status, error code, headers, exact JSON, and response-size ceiling.

Run the complete gate with `test_runner`, inspect `git diff --stat` and then the full diff, record accepted evidence in the overview, and update the docs index, phase plan, and changelog if affected. Mark M8 `Done` only when the checklist and gate pass. Hand M9 the version, synthetic fixtures, secret-provisioning steps, and open deployed checks: Free billing, actual platform quota response, 24-hour capacity and latency, cellular retrieval, promotion/rollback, and teardown. No real usage reaches Cloudflare during M8.

## Review focus

1. Authentication precedes body parsing except for a strict size limit, and failures do not reveal whether a token, reader, or publisher exists.
2. Every multi-step state decision is atomic under competing requests; a retry after a lost response has the documented result.
3. The relay treats ciphertext as opaque bytes and stores no history, plaintext, key, provider credential, or raw token.
4. The strong ETag hashes the exact bytes returned to readers; `304` requires an authenticated reader and an existing snapshot.
5. Local tests establish implementation behavior only. M9 owns platform-generated quota, deployed Free-plan, capacity, billing, and real network evidence.
