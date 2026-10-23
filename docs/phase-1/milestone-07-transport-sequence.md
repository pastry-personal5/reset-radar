# P1-M7: Transport crypto and protocol sequence

Status: Done

Work order and test evidence for the [M7 overview](milestone-07-transport-overview.md). The [Transport design](../architecture/transport.md), [relay protocol](../architecture/relay.md), and existing Domain and Application ports define behavior; this file only makes the implementation order and cross-language handoff explicit.

## Constraints

- Keep production sources in `ResetRadarKit/Sources/ResetRadarTransport/`, tests in `ResetRadarKit/Tests/ResetRadarTransportTests/`, and shared JSON in `Fixtures/Protocol/`. Transport imports Domain, Application, Foundation, CryptoKit, Security, and platform frameworks only as needed. No adapter imports another adapter.
- Use `WireCoding` for versioned Domain records. All test tokens, IDs, keys, account identifiers, and usage snapshots are synthetic. Never log package text, keys, digests, ciphertext, or relay identifiers.
- Run focused Transport tests while iterating and the full [gate](../contribution-guide.md#required-validation) at each checkpoint and close-out. Use the `test_runner` subagent for command execution and first-pass analysis.
- Follow the six recorded [owner decisions](milestone-07-transport-overview.md#owner-decisions). Record any necessary Application port change in the changelog before editing dependent modules, and return any new product or protocol choice to the owner.

## Task 0: Contract and baseline

Record the base commit, worktree state, and full baseline gate in an isolated checkout so unrelated M6 follow-up edits do not become M7 evidence. Apply all six approved owner decisions and the exact Transport and relay v1 profiles, and agree on `Fixtures/Protocol/` schema and names with M8. The fixtures use synthetic keys and tokens only, with no live credential or provider output. Keep one canonical fixture file per operation or error class, with a short README explaining producers and consumers. Swift and TypeScript fixture loaders read those checked-in files directly from either `swift test` or the Mac Xcode scheme, without copying fixture bytes into a second source file. Add only the approved Domain and Application test-target dependencies to `Package.swift`.

## Task 1: Shared wire fixtures and generator

Implement `CryptoSecretGenerator` and fixture loading. Generate 32-byte independent secrets through system cryptographic randomness, implement `randomUnit()` in `0...1`, and SHA-256 digest bytes. Pin deterministic vectors for a fixed key, nonce, header, snapshot, pairing package, each request body, each distinct response shape or error code, and a strong ETag; production nonce generation remains random. Tests verify lengths, independence over repeated draws, digest vectors, identifiers, and no secret in descriptions or mirrors. The fixture generator must be a documented test utility, not a runtime dependency. An account-scope key is per installation and survives relay destruction, as the existing use case requires.

The first M8 handoff is the frozen outer-envelope, request, response, and ETag fixture set. Include the owner-approved [registration retry and collision, expired-ID retry, and cross-reader ID collision outcomes](milestone-08-relay-implementation-overview.md#owner-decisions-for-registration-and-refresh-ids), using the existing `400 badRequest` mapping where specified. Its TypeScript tests parse and validate outer metadata, versions, safe-integer bounds, and body shapes without a content key. Swift tests decode the same files and authenticate the encrypted sample. Record the fixture revision in the M7 overview; M8 changes to the contract require a documented cross-module review.

## Task 2: Account scoping and envelope

Implement `HMACAccountScoper` and `AESGCMEnvelopeCipher` behind their ports. Read or establish the per-install account-scope key through `SecretStore`, including concurrent first calls in the Mac process; HMAC the Codex account identifier, truncate to 128 bits, and retain neither the identifier nor a reversible copy. Seal `UsageSnapshot` with a fresh 96-bit nonce and the approved canonical header bytes as additional authenticated data. Encode the approved outer JSON form. Open only after version, length, and tag checks, then validate the decoded snapshot and require its publisher to match the authenticated header. `AcceptPairing` and `IngestRelaySnapshot` retain the separate paired-publisher check.

Tests use deterministic crypto injection for golden vectors; production uses secure randomness. Cover a round trip, wrong key, every header field changed, altered ciphertext, truncated tag, malformed base64/JSON, duplicate or unknown outer keys, noncanonical outer bytes, unsupported version/key version, publisher mismatch, invalid snapshot, the 64 KiB encoded-envelope boundary, and sequence values `9007199254740991` and `9007199254740992`. A failed open returns no snapshot or partial plaintext. Verify two distinct identifiers produce distinct scopes under one key and one identifier is stable under that key. The existing `PublishSnapshot` size check and the HTTP gateway preflight both reject sending an oversized sealed envelope.

## Task 3: Pairing codec and origin guard

Implement `OriginGuard` once and reuse it in `JSONPairingCodec` and `HTTPRelayGateway`. It accepts only the approved canonical `https://<worker>.<account>.workers.dev` origin with no explicit port, trailing slash, path, user information, query, or fragment. Encode the `PairingPackage` as compact JSON then base64url, and derive the grouped confirmation code from SHA-256 of the exact encoded string. The decoder rejects alternate encodings of the same fields under the approved canonical rule.

Expose the same guard for M12's setup entry point: `SetUpRelay.prepare(endpoint:)` stores a URL before its first gateway call, so the Mac composition root must validate the entered origin before calling it. The gateway independently validates every supplied endpoint before attaching a token.

Tests cover every package field under tampering, malformed IDs, 32-byte key/token lengths, unsupported version, missing, unknown, or duplicate fields, alternate base64 padding, near-expired and too-far deadlines at the approved skew boundaries, and origin tricks (lookalike hostname, mixed case, trailing dot or slash, explicit port, path, user info, query, fragment, HTTP). Verify that changed package contents require a different confirmation code in representative fixtures; never infer package integrity from the publisher fingerprint alone.

**Checkpoint A:** Swift and TypeScript read the same approved protocol fixtures, focused tests pass, and the complete gate passes. Record the fixture revision M8 must use.

## Task 4: Secret store and clipboard helper

Implement `KeychainSecretStore` over an injectable SecItem backend. Use non-synchronizing generic-password items under fixed Debug and Release service names, Mac login-keychain access with interaction disabled, and iOS `AfterFirstUnlockThisDeviceOnly` with explicit shared App Group `kSecAttrAccessGroup` on every operation. Map not-found, interaction-required, and unexpected status classes to `SecretStoreError` without a label or OS message. Read once per process on Mac; invalidation on write/delete, setup replacement, and destruction prevents reuse of superseded secrets. Add the approved macOS conditional-clear helper with digest and `changeCount` checks through an injected pasteboard interface.

Tests use a stub SecItem backend and pasteboard abstraction. Cover every operation and status mapping, duplicate-item update behavior, Debug/Release isolation, all iOS access-group calls, Mac no-prompt policy, idempotent delete, concurrent cache reads, a read racing with replacement, invalidation after mutation, a locked-backend read before and after a cached read, and unchanged versus changed clipboard contents across a simulated relaunch. The real Keychain and system pasteboard are not exercised in the gate; M12 and M14 own runtime evidence.

## Task 5: Relay request builder and response reader

Implement `HTTPRelayGateway` with an ephemeral, no-cookie, no-cache URLSession; 10-second request and 15-second resource timeouts; no wait for connectivity. Build all ten port operations from the guarded origin and put bearer credentials only in `Authorization`. Validate upload size before creating a request. The task delegate refuses every redirect, including same-origin and HTTPS-to-HTTP. Read response bytes incrementally; enforce 64 KiB for successful snapshot bodies and 4 KiB for all other bodies, including snapshot-read errors, independently of `Content-Length`.

Tests use a local request harness to inspect method, path, media type, exact bearer-token base64url encoding, and body for each operation and token role; confirm no token is forwarded on same-origin or cross-origin redirects. Cover cancellation, timeout, false or absent length, one byte above and exactly at each response cap, an oversized upload that sends nothing, over-limit chunk delivery, and a malformed body. No live network request runs in the gate.

## Task 6: Response mapping and use-case integration

Implement `ResponseMapper` against every `RelayStatusContract` row and the approved body schema. Distinguish operation-specific success; authenticated first-publish `404` from an unknown route; publisher, reader-cap, and completed-request `409`; manual rate limit from Free quota `429`; and all redirects and failures. Keep the M9 platform-quota case as a separately specified mapping until deployed evidence identifies its response. Carry ETag and sequence only from a valid bounded snapshot response, and relay-assigned deadlines only from valid registration or refresh responses. Validate the strong ETag against exact envelope bytes, derive the read sequence from its outer header, and compare a write acknowledgement's sequence to the submitted header. Preserve the existing one-time retry when an unconditional GET unexpectedly receives `304`. A malformed or oversized result never updates a use case's validated snapshot, ETag, or last-success time.

Run `SetUpRelay`, `PublishSnapshot`, `PairReader`/`AcceptPairing`, `IngestRelaySnapshot`, `RequestMacRefresh`, `RevokeReader`, and `DestroyRelay` with real Transport adapters where applicable and fake storage/clock/network. Verify the sequence is committed before send, a lost activation response retries with the same token, `304` without a matching cached snapshot causes an unconditional retry, a nonmatching encrypted manual result does not complete the request, and a relay failure preserves the last validated cache. Exercise role separation and redacted errors in each flow.

**Checkpoint B:** focused Transport and use-case integration tests plus the complete gate pass.

## Task 7: Close-out

Remove the Transport placeholder source and smoke test. Check imports and fixture references, update approved contract details in Transport and relay docs, record gate and test evidence in the overview, and mark M7 `Done` in [phase-1.md](phase-1.md) only after all checklist items are satisfied. Run the complete gate from a clean checkout. Hand the fixture revision and any still open M9 runtime checks to M8 and M9; do not send real usage to Cloudflare.

## Review focus

1. Authentication covers the exact header the relay parses, including version, publisher, sequence, and key version; canonicalization has a cross-language golden byte test.
2. A package copied by hand carries a durable content key; the confirmation code covers the exact full package and conditional cleanup cannot erase another app's pasteboard value.
3. A token never reaches a redirected URL, URL query, diagnostic, thrown error, or test failure dump.
4. The body cap counts delivered bytes even when the server lies about `Content-Length`; failed responses retain cached state.
5. The same HTTP status can have different meanings only through the approved operation and stable body code, never through guessed response text.
6. Keychain backend tests are not presented as evidence for stable signing, a locked login keychain, or first-unlock behavior on real devices.
