# P1-M7: Transport crypto and protocol overview

Status: Planned

Implement `ResetRadarTransport` behind the P1-M5 ports, using the [Transport design](../architecture/transport.md) and the [relay protocol](../architecture/relay.md). This milestone supplies authenticated snapshot envelopes, account scoping, pairing packages, non-interactive secret storage, an HTTPS relay client, and checked-in fixtures for P1-M8. The [sequence](milestone-07-transport-sequence.md) gives the work order and acceptance tests.

## Goal

The real Transport implementations satisfy `SecretStore`, `SecretGenerator`, `EnvelopeCipher`, `AccountScoper`, `PairingCodec`, and `RelayGateway` without changing the use cases. Swift tests and relay tests consume the same protocol fixtures. The complete [contribution-guide gate](../contribution-guide.md#required-validation) passes using synthetic data and test doubles, with no live Cloudflare deployment or real Keychain access.

## Entry criteria

- [ ] P1-M4 and P1-M5 are `Done`, and the starting commit and worktree are recorded. Evidence: [phase plan](phase-1.md) and `git status --short`. P1-M6 is also marked `Done`; preserve any separate uncommitted follow-up work.
- [x] The owner answered the [owner decisions](#owner-decisions), including the test-target dependency edit and v1 sequence bound. Evidence: the 2026-10-23 [changelog](changelog.md) entry.
- [ ] The full gate passes on an isolated baseline before Transport implementation. Evidence: commands and result recorded here or in the changelog.

## In scope

- Cryptographically secure generation of independent 256-bit content, write, administration, read, and account-scope secrets; SHA-256 token digests and non-secret jitter.
- HMAC-SHA-256 account scopes; AES-GCM seal and open with authenticated `EnvelopeHeader`, exact version checks, and rejection when the plaintext publisher differs from the header. The reader use cases also check that header against the paired publisher.
- A compact base64url pairing package, strict endpoint and deadline validation, and a confirmation code over the exact encoded package.
- `KeychainSecretStore` with an injectable backend, Mac login-keychain and iOS data-protection policies, Debug/Release service separation, non-interactive operations, and per-process cache invalidation. Signed-build and device behavior remain the P1-M12 and P1-M14 evidence gates.
- `HTTPRelayGateway`: all ten port operations, canonical `workers.dev` origin validation, redirect refusal, ephemeral session, bounded streaming bodies, status and body mapping, and no credential forwarding.
- Checked-in, synthetic, cross-language protocol fixtures in `Fixtures/Protocol/` for the outer envelope, pairing, request bodies, response bodies, error codes, and ETags. Both language suites consume the same files; M8 consumes the frozen contract before implementing the Worker.
- Transport tests against cryptographic vectors, a stub Keychain backend, an injected pasteboard interface, and a local URL protocol or equivalent request harness; integration tests run P1-M5 use cases with real Transport adapters and fake relay or secret dependencies.

## Out of scope

- The Cloudflare Worker, Durable Object, deployment, quota and billing measurements (P1-M8 and M9). The relay stores ciphertext and never receives a content key.
- Mac collector wiring, signed Release and eight-day Keychain re-read, setup UI, and clipboard lifecycle calls (P1-M12); iPhone/iPad pairing UI, widget wiring, and physical Keychain verification (P1-M14).
- Product or reset-policy changes, provider adapters, Watch credentials or direct relay access from Watch, live provider readings, and any real usage sent to Cloudflare.
- New external dependencies, build tools, targets, or broad repository restructuring without owner approval.

## Owner decisions

The owner accepted all six choices on 2026-10-23. The v1 field schema and byte rules are specified in [Transport](../architecture/transport.md#v1-wire-profile) and [relay](../architecture/relay.md#v1-http-body-profile); M7 will pin literal golden bytes in shared fixtures.

1. **Canonical envelope and pairing bytes — accepted.** Use protocol and envelope version `1`, reserved key version `1`, sorted-key UTF-8 JSON via `WireCoding` for the authenticated `EnvelopeHeader`, one compact outer JSON record, unpadded base64url nonce/ciphertext/tag, and strict rejection of unknown outer fields.
2. **Relay request and response contract — accepted.** Define operation-specific versioned JSON bodies, stable machine-readable error codes, and an exact strong-ETag rule. The mapper uses the operation and bounded body rather than prose; M9 separately records any Cloudflare-generated quota response.
3. **Pairing deadline tolerance — accepted.** Accept the relay deadline from `now - 30 seconds` through `now + five minutes + 30 seconds`, inclusive. Outside that interval, decoding rejects it. A relay `401` remains authoritative for activation recovery.
4. **Test-target imports — accepted.** Add the existing local `ResetRadarDomain` and `ResetRadarApplication` targets to `ResetRadarTransportTests` in `Package.swift` when M7 implements the direct imports. This authorizes no external package or new target.
5. **Clipboard helper ownership — accepted.** Put the macOS-only conditional-clear helper in Transport behind an injected pasteboard interface. The Mac composition root owns explicit Copy, activation/view/expiry/relaunch calls and warning text.
6. **Sequence number range — accepted.** V1 accepts JSON-number sequences `1...9007199254740991` (`2^53 - 1`). Swift refuses to seal or send a larger v1 sequence; the Worker rejects it before ordering or storage. Test both sides of the boundary.

## Completion checklist

- [ ] Entry criteria hold and every owner decision is recorded.
- [x] Plan review confirms the existing port signatures, relay operation count, fixture consumers, and deferred runtime evidence. Evidence: review below against the checked-in Application ports, `RelayStatusContract`, Transport and relay designs, and owner decisions on 2026-10-23.
- [ ] `ResetRadarTransport` implements all six ports and its placeholder source and smoke test are removed; `Scripts/check-imports.sh` passes.
- [ ] Deterministic envelope and pairing fixtures have exact Swift round trips, rejected-version and tamper cases, and matching TypeScript fixture validation without decryption. Both suites load the checked-in files directly, independently of the process working directory.
- [ ] Generator, account-scope, secret-store, cache, and injected pasteboard-helper tests cover the cases in [Transport tests](../architecture/transport.md#tests) and the sequence.
- [ ] Every `RelayStatusContract` row maps to the expected `RelayOutcome`, including operation-specific `200`, both `404` cases, all three `409` cases, both `429` cases, redirects, and offline failures.
- [ ] Relay-client tests prove origin and redirect refusal, token isolation for read/write/admin roles, a 64 KiB limit for successful snapshot bodies and a 4 KiB limit for other responses including errors, even with missing or deceptive `Content-Length`; they also prove request-size preflight, timeouts, and unchanged validated cache on failure.
- [ ] Real Transport adapters pass relevant P1-M5 use-case flows with synthetic inputs; no gate test accesses a real Keychain, provider tool, or network.
- [ ] The full contribution-guide gate passes; the test runner reports command results and first-pass failure analysis. The milestone overview records acceptance evidence and the phase plan moves to `Done` only then.
- [ ] Affected architecture and protocol docs, fixture notes, docs index, phase plan, and changelog are updated with any approved contract details. M8 can consume the frozen fixture set.

## Checkpoints

- **A: Wire contract and crypto.** Create shared fixtures, generator, HMAC, envelope, and pairing codec under the approved v1 profile and all six owner decisions.
- **B: Secrets and HTTPS.** Use the approved questions 4 and 5; implement Keychain backends, cache, clipboard helper, relay client, mapper, and bounded response reader.
- **C: Integration and close-out.** Run use cases over real adapters, check fixture parity, complete the gate, and record evidence. M8 may start from the approved A fixture contract; M9 still waits for M7 and M8 completion.

## Plan review evidence

- The six listed adapters match the six existing Application ports, and `RelayGateway` declares ten operations. `EnvelopeCipher.open` can check the plaintext publisher against its authenticated header; the existing reader use cases check that header against the paired publisher.
- `RelayStatusContract` already names the ambiguous `404`, `409`, and `429` outcomes. The owner approved versioned operation-specific bodies, stable error codes, a strong ETag, and the safe JSON-number sequence bound; the v1 profile now pins them.
- M7 can prove the synthetic Worker quota mapping. M9 must separately measure and pin any Cloudflare-generated Free-limit response; the M7 gate cannot claim deployed quota conformance.
- The shared fixtures must be read by Swift and TypeScript tests without a copied fixture set. The Mac signing and locked-Keychain behavior, iOS first-unlock and widget access, Cloudflare deployment, and billing remain the later runtime evidence gates named above.

## Risks

- **Wire drift.** A Swift-only golden fixture would let the TypeScript relay implement a different format. Both suites read the same checked-in fixture files, with no second hand-maintained copy. Reject noncanonical encodings that could give the same pairing fields different confirmation codes.
- **Credential disclosure.** Redirects, URL construction, errors, and debugging can expose bearer tokens or package content. Harnesses inspect every outgoing request and logged/error value for redaction.
- **Keychain uncertainty.** Stubbed backend tests prove adapter decisions only. M12 and M14 retain signed, locked, and first-unlock runtime validation; a failure returns the storage decision to the owner.
- **Quota-response uncertainty.** Cloudflare's actual Free-limit response is established in M9. Until then, an unrecognized bounded platform `429` maps to `protocolFailure` and keeps the last valid cache; bounded `5xx` and network failures map to `offline`.
