# P1-M17 maintained-code security review

Status: Active

This review covers the maintained Apple code, relay, scripts, build configuration, and active
security documentation at the current checkout. It records confirmed defects, repairs, focused
evidence, and the completed validation gate.

## Scope and method

The review traced provider input through parsing and local storage; Mac Keychain and relay
lifecycle; pairing, encryption, HTTP, and Worker authorization; reader cache and profile
publication; Watch delivery and scheduling; deployment scripts and entitlements; and active
security/privacy copy. It also searched maintained text for credential-like literals and
checked the npm lockfile against current advisories. Existing physical-device evidence gaps
remain assigned to [M14](milestone-14-ios-core-app-overview.md),
[M15](milestone-15-scheduling-validation.md), and
[M16](milestone-16-security-review.md); static inspection cannot close those gates.

| Boundary | Evidence inspected | Result |
|---|---|---|
| First-party tools to Mac | Bounded Codex RPC/process handling; Claude Code command parser, executable identity, synthetic composition, settings editor, owner-only files | Existing trust checks retained; no credential forwarding path found. |
| Mac local state | Keychain access, publisher state, storage transactions, diagnostics, signing and entitlements | Remote deletion needed a durable confirmation marker; repaired below. |
| Mac to relay | Origin guard, pairing codec, AES-GCM envelopes and profiles, HTTP bounds, redirects, response mapping | Canonical origin and authenticated envelope checks retained. |
| Relay authority and state | Worker role digests, read-token lookup, SQL transactions, body limits, sequence/revision checks, scripts and deployment contract | Two reader writes needed a token recheck after body receipt; repaired below. |
| Reader and Watch | Pairing, profile retry, cache commit/claim, Forget Mac, Watch wire codec, scheduling surfaces | A stale in-flight profile could attach to a new pairing; repaired below. No relay credential enters Watch payloads. |
| Documentation | Product/architecture privacy claims, relay state and response limits, Mac uninstall and recovery | Corrected statements and added account-side recovery. |
| Dependencies | Exact npm development pins and lockfile; npm advisory and license metadata | Seven pre-update development-tool advisories; owner-approved pins now audit clean. Deployed dependencies audited clean before and after. |

The credential-pattern scan found no credential literal in maintained code or active docs; two
matches in milestone text were ordinary `task-...` links. This scan is a pattern check, not a
claim that every possible secret format can be recognized.

## Confirmed findings and repairs

| Priority | Finding and impact | Repair and proof |
|---|---|---|
| High | `PUT /v2/reader-profile` and `POST /v2/refresh-requests` authenticated a read token before awaiting the body, then committed against reader ID alone. A revoke and replacement registration during that wait let the old token mutate the replacement reader. | [RelayObject](../../relay/src/index.ts) compares the originally authenticated token digest with the current row inside each SQL transaction. Streaming-body tests in [relay tests](../../relay/test/index.spec.ts) fail with `200`/`202` on the prior code and pass with `401` after the repair. |
| High | A missing Mac administration Keychain item was treated as evidence that remote relay deletion had completed. Local cleanup could report success while remote ciphertext and reader access remained. | [DestroyRelay](../../ResetRadarKit/Sources/ResetRadarApplication/Relay/DestroyRelay.swift) persists `remoteDeletionConfirmed` before deleting any secret. A missing token without that proof leaves `destroyPending` paused. [Tests](../../ResetRadarKit/Tests/ResetRadarApplicationTests/DestroyRelayTests.swift) cover both the missing-token refusal and retry after confirmed deletion. Older stores decode the optional marker as absent. |
| Medium | An in-flight reader profile could seal against an old pairing, then install that body into a newly paired reader's local retry state. | [ReportReaderProfile](../../ResetRadarKit/Sources/ResetRadarApplication/Reader/AcceptPairing.swift) checks the exact pairing at commit and before send/result application. A paused-secret [regression test](../../ResetRadarKit/Tests/ResetRadarApplicationTests/ReaderProfileReportingTests.swift) fails on the prior commit logic and passes after the repair. |
| Low | The iOS Privacy screen described only encrypted snapshots, omitting encrypted reader profiles and opaque refresh metadata; the relay document understated the v2 list limit and omitted its schema table. | Updated [iOS copy](../../ResetRadar/SettingsView.swift), [product limitations](../product-limitations.md), and [relay architecture](../architecture/relay.md). |
| Tooling | npm reported seven advisories in development tools, including high-severity transitive packages. | With owner approval, pinned Vitest 4.1.12, Workers Vitest plugin 1.4.9, and Wrangler 4.154.0 in the manifest, lockfile, and deployment contract. `npm audit --audit-level=low` now reports zero vulnerabilities; the three direct licenses remain MIT or MIT OR Apache-2.0. |

## Recovery and remaining validation

The owner chose an account-side recovery guide for older `Destroy Pending` installations that
have no deletion marker and have lost the administration token. The [Mac guide](../mac-installation-and-recovery.md#account-side-relay-recovery-when-the-administration-token-is-lost)
uses Cloudflare's namespace tombstone procedure and requires verification before manual local
uninstall. Deleting only the Worker or SQL rows is not presented as full storage deletion.

Focused relay, Swift destruction, and stale-pairing tests pass. On 2026-10-28, the complete
[contribution gate](../contribution-guide.md#required-validation) passed with isolated iOS and
Watch DerivedData paths: project generation, format check, strict SwiftLint with zero violations
in 377 files, import checks, pipeline tests, arm64-only Mac Release inspection, Mac/iPhone/iPad/Watch
tests, relay installation and tests, TypeScript checking, and the Wrangler dry run. An earlier gate
attempt stopped at an iOS test compile because a pre-existing shared DerivedData module from
17:32 shadowed the newly built 18:59 module; the isolated full rerun passed. The live post-upgrade
`npm audit --audit-level=low` reports zero advisories. A maintained-document check resolved 905
local links with zero missing targets, and `git diff --check` passed.
