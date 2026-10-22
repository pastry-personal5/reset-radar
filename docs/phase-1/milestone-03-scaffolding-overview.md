# P1-M3: Scaffolding overview

Status: Planned

Create the empty-but-real Xcode project, `ResetRadarKit` package, relay package, and lint/format configuration described by the [software architecture](../architecture.md), so a fresh checkout passes the complete gate with no deferrals. No production use case, provider integration, or real-data path is implemented.

## Goal

A fresh checkout builds every target in [Composition roots and test targets](../architecture.md#composition-roots-and-test-targets), enforces the dependency rule, and passes the complete gate in the [contribution guide](../contribution-guide.md).

## Entry criteria

Do not start implementation until all of these hold.

P1-M2 is currently `Active`, so the first criterion is intentionally unmet. Plan review may finish now; scaffold implementation may not start merely because this document exists.

- [ ] P1-M2 is `Done`. Its open items (Keychain spike, platform spikes, runtime security review, gate record) are resolved or explicitly carried into this milestone in [changelog.md](changelog.md). A failed Mac Keychain spike returns the storage design to the owner before scaffolding.
- [x] The owner has answered the questions in [Owner decisions](#owner-decisions). Evidence: 2026-10-22 owner entry in [changelog.md](changelog.md).
- [ ] The toolchain prerequisites in [the architecture plan](milestone-03-scaffolding-architecture.md#toolchain-prerequisites) are met, including simulator runtimes that can create the exact gate destinations.
- [x] [Repository layout](../architecture/repository-layout.md) is accepted and `Active`. Evidence: 2026-10-22 owner entry in [changelog.md](changelog.md).

## In scope

- An XcodeGen specification that produces `ResetRadar.xcodeproj` with every composition-root and test target, schemes `ResetRadar`, `ResetRadarMac`, and `ResetRadarWatch`, and Development and Release configurations. The specification is the source of truth; generated project output is not committed.
- The `ResetRadarKit` package with nine library modules, one individually consumable library product per module, and eight test targets. The `ResetRadarTestSupport` product is available only to test dependency graphs and intentionally has no test target of its own.
- The `relay/` package: strict TypeScript, Workers Vitest, Wrangler pinned, committed lockfile, `test` and `typecheck` scripts.
- `.swift-format`, `.swiftlint.yml`, and ignore rules.
- Entitlements, bundle identifiers, App Group, and signing settings; the Mac signing build check.
- Three generator-owned shared scheme definitions and checked-in test plans, shared synthetic fixtures, empty asset catalogs with UX-vocabulary slots, and no temporary artwork that could be mistaken for an approved icon.
- Any physical-device signing, App Group, WidgetKit, Keychain re-sign, or seven-day Sideloadly evidence explicitly carried forward from P1-M2.
- Updates to `README.md`, the contribution guide, and the [documentation index](../README.md).

## Out of scope

- Product behavior, UI beyond an empty root view per platform, and any provider, relay, or Keychain call with real data.
- Product-level physical-device behavior beyond evidence explicitly carried forward from P1-M2. The carried work proves that the scaffold can be signed, installed, and share its empty synthetic state; it does not implement or validate product behavior.
- Promoting spike code. Only reviewed, reusable fixtures or code may be copied from `spikes/` or spike-branch relay code, and nothing is merged wholesale.
- CI services, Swift Package Manager third-party dependencies, and new relay dependencies beyond the approved toolchain.

## Owner decisions

Owner input is required; do not invent answers (see [AGENTS.md](../../AGENTS.md)).

- **Decided — XcodeGen.** The owner chose XcodeGen. Its checked-in specification is authoritative, and `ResetRadar.xcodeproj` is generated and ignored rather than maintained as a second source of truth.
- **Decided — identifiers.** Use bundle prefix `com.unidentifiedstealthstartup`, main-app identifier `com.unidentifiedstealthstartup.ResetRadar`, and App Group `group.com.unidentifiedstealthstartup.ResetRadar`. Target suffixes must be deterministic and listed before any App ID is registered.
- **Decided — simulator destinations.** Preserve iPhone 17 Pro Max and iPad Air 11-inch (M2), and install a compatible iOS 26.x runtime rather than changing the approved reference models.
- **Decided — repository layout.** The owner accepted the XcodeGen-based [repository layout](../architecture/repository-layout.md), which is now `Active`.

## Completion checklist

- [ ] Entry criteria all hold. Evidence: links to the changelog entries and command output.
- [x] Owner decisions are complete and recorded in [changelog.md](changelog.md) and [AGENTS.md](../../AGENTS.md). Evidence: 2026-10-22 owner entry and the binding scaffolding decision.
- [ ] Patch-level deployment targets (iOS/iPadOS 26.6.2, watchOS 26.6, macOS 26.7.1) are accepted by Xcode and SwiftPM, or the documented minor-version fallback is applied and recorded. Evidence: build settings and command output.
- [ ] Every target builds with Swift 6 language mode and strict concurrency. Evidence: build log summary.
- [ ] The generated target inventory is exact: six production Xcode targets, four Xcode test targets, nine Swift package library targets/products, eight Swift package test targets, and three shared schemes/test plans. Evidence: XcodeGen specification, `xcodebuild -list`, Swift package description, and test-plan listing.
- [ ] A deliberately violating import (an adapter importing another adapter, and a Domain import of Application) fails the build; the probe is removed afterward. Evidence: failing command output.
- [ ] The Mac signing build check passes with the Personal Team identity and fails an ad-hoc build. Evidence: both build outcomes.
- [ ] Entitlements match each composition root's configuration table; no Push Notifications, iCloud, CloudKit, analytics, provider-credential, or profile-requiring Mac entitlement. Evidence: entitlements inspection.
- [ ] App ID count is within the free account's 10-per-7-days budget and bundle identifiers are stable. Evidence: the identifier list and count.
- [ ] One shared test plan per scheme runs the package test targets for its platform plus its app-level bundle; the `ResetRadar` plan also runs `ResetRadarUITests` on both iPhone and iPad. Evidence: test-plan listing and test run.
- [ ] The checked-in format script passes explicit maintained source roots to `swift-format`, and SwiftLint exclusions cover generated, external, build, and spike output. Evidence: script inspection and lint output with inputs and exclusions listed.
- [ ] The relay installs from the lockfile with `npm ci`, pins direct development dependencies and the compatibility date, and generates ignored `worker-configuration.d.ts` on demand before type-checking. Evidence: clean-checkout install, generation, test, dry-run bundle, and type-check output.
- [ ] Shared protocol fixtures are present and read by both Swift Transport tests and relay tests.
- [ ] Every carried-forward physical-device check is completed with synthetic data, or the milestone remains incomplete. Evidence: the linked P1-M2 checklist item and dated result.
- [ ] Docs are updated: README no longer says the apps are unscaffolded; the contribution guide and architecture use the same clean-checkout gate, including `npm ci` and the non-deploying Wrangler dry run; and the documentation index lists new docs.
- [ ] From a clean checkout with no `node_modules/`, the complete gate installs relay dependencies and passes with no deferral in one run. Evidence: every command and result in the contribution guide.
