# P1-M4: Domain model overview

Status: Planned

Implement `ResetRadarDomain` as specified in [Domain](../architecture/domain.md): identities, records, wire conventions, per-window validation, Home slot resolution, and the availability policies, all pure and covered by Swift Testing. No other module changes; nothing here touches storage, networking, providers, or UI.

## Goal

`ResetRadarDomain` contains every type and policy in [domain.md](../architecture/domain.md), imports only Foundation, is deterministic (time and randomness arrive as arguments), and its tests pass in the complete gate in the [contribution guide](../contribution-guide.md).

## Entry criteria

- [ ] P1-M3 is `Done` and merged to `main`; P1-M4 work starts on a fresh branch from `main`, not on `feat/p1-m3-scaffolding`. Evidence: branch base.
- [x] The owner has answered the [open questions](#open-questions), or accepted each recommendation. Evidence: 2026-10-22 changelog entry.
- [ ] A clean-checkout gate passes before any change (baseline). Evidence: command results.

## In scope

- Every type in the domain.md Identity, Records, and Availability sections, including the records whose encoding belongs to other modules (`WatchPayload`, `WatchEraseReceipt`, `PairingPackage`, `EnvelopeHeader`): this milestone defines their fields, schema versioning, and `Codable` shape; Transport (P1-M7) owns their byte-level codecs, and Storage (P1-M6) their persistence.
- Wire conventions: explicit schema versions, stable lowerCamelCase enum values, unknown optional values decoding to `unknown`, unknown mandatory schema versions rejecting the record.
- Per-window validation producing redacted `DiagnosticEvent`s, Home slot resolution, presentation-state derivation with next-change instant, current-data windows, Mac liveness, and manual-refresh result validation (retention cap, expiry, reader matching).
- Test coverage listed in domain.md "Tests", plus the [review focus](milestone-04-domain-model-sequence.md#review-focus) cases.
- Doc updates: [domain.md](../architecture/domain.md) if an open question changes it, this milestone's evidence, the [phase doc](phase-1.md), and the [changelog](changelog.md).

## Out of scope

- Ports, use cases, refresh and publication policies, `CollectUsage`, snapshot reduction (P1-M5). `SourceSnapshot` is defined here as a record only.
- Encryption, account-scope derivation, pairing codec, relay protocol and shared fixtures (P1-M7). `AccountScope` here is an opaque comparable value.
- Provider parsing (P1-M10, P1-M11), persistence (P1-M6), formatting and copy (UI).
- Confirming the 15- and 60-minute current-data windows; they stay candidate constants until source calibration (P1-M10, P1-M11).
- Any dependency, build-tool, or repository-layout change.

## Open questions

Domain.md left these wire-level details open. The owner accepted every recommendation below on 2026-10-22 (see [changelog.md](changelog.md)); they are decided.

1. **Date encoding.** Recommend ISO-8601 UTC with millisecond precision, provided by one `WireCoding` encoder/decoder pair in Domain, so Transport and the relay fixtures share it. Alternative: integer epoch milliseconds.
2. **Precision metadata.** Recommend `fractionDigits` of 0 (Codex integers) or 1 (Claude Code), validated.
3. **Provider limit state.** Recommend a small enum (`reached`, `ordinaryUsageAllowed`, `unknown`); P1-M10 may add cases, which the unknown-tolerant decoding makes additive.
4. **`DiagnosticEvent` categories.** Recommend a closed enum with an `unknown` decode fallback, extended by later milestones as their failure behavior needs.
5. **Non-positive `heartbeatSeconds`.** Recommend rejecting the whole snapshot as invalid, since three heartbeats of zero would mark the Mac never publishing.
6. **Unknown `TransportStatus` in a `WatchPayload`.** The status is device-local but travels to the Watch. Recommend decoding an unknown value to `incompatible`, so an older Watch shows a safe state rather than rejecting the payload.

## Completion checklist

- [ ] Entry criteria hold. Evidence: changelog entry and baseline gate output.
- [ ] Every type and policy named in domain.md exists in `ResetRadarDomain`; `Package.swift` still declares Foundation-only dependencies for the target. Evidence: type inventory against the doc and `swift package describe`.
- [ ] `ResetRadarDomain` imports only Foundation, and `Scripts/check-imports.sh` passes. Evidence: command output.
- [ ] Percentages `0`, fractional, `100`, NaN, ±infinity, negative, and above 100 are accepted or rejected per window, valid siblings kept, with a redacted diagnostic. Evidence: named tests.
- [ ] Unknown optional enum values decode to `unknown`; an unknown mandatory schema version rejects the record. Evidence: named tests.
- [ ] Home slot resolution covers match, no match, and two default windows with equal duration (unavailable plus diagnostic). Evidence: named tests.
- [ ] Presentation precedence is tested at every threshold boundary, including a retained window past its reset, `resetsAt == now`, `observedAt == now + 5 minutes`, and the returned next-change instant. Evidence: named tests.
- [ ] Manual-refresh validation covers the four-per-reader and twelve-total caps, the two-minute expiry, and wrong-reader matching. Evidence: named tests.
- [ ] Mac liveness uses three heartbeats and never makes an old observation current. Evidence: named tests.
- [ ] `DiagnosticEvent` has no initializer accepting a free-form string. Evidence: public-interface inspection.
- [ ] Round-trip and golden-JSON tests exist for every `Codable` record. Evidence: test list.
- [ ] Complete gate passes from a clean checkout. Evidence: every command and result in the contribution guide.
- [ ] Docs updated: phase-1.md status, changelog, README index, and domain.md if an answer changed it. Evidence: diff.
