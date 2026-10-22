# P1-M3: Scaffolding overview

Status: Done

Create the empty-but-real Xcode project, `ResetRadarKit` package, relay package, and lint/format configuration described by the [software architecture](../architecture.md), so a fresh checkout passes the complete gate with no deferrals. No production use case, provider integration, or real-data path is implemented.

## Goal

A fresh checkout builds every target in [Composition roots and test targets](../architecture.md#composition-roots-and-test-targets), enforces the dependency rule, and passes the complete gate in the [contribution guide](../contribution-guide.md).

## Entry criteria

Do not start implementation until all of these hold.

On 2026-10-22 the owner started this milestone without waiting for P1-M2 (see [changelog.md](changelog.md)). P1-M2 stayed `Active` then; its open spikes were neither carried into nor blocking this milestone and are now archived in [P1-M2 open work](../archive/p1-m2-open-work.md).

- [x] Owner override: P1-M2 does not gate P1-M3. Evidence: 2026-10-22 owner entry in the changelog. No physical-device checks are carried forward.
- [x] The owner has answered the questions in [Owner decisions](#owner-decisions). Evidence: 2026-10-22 owner entry in [changelog.md](changelog.md).
- [x] The owner has approved the exact relay development dependency versions and the bundle identifier list in [the sequence plan](milestone-03-scaffolding-sequence.md). Evidence: 2026-10-22 changelog entry.
- [x] The toolchain prerequisites in [the architecture plan](milestone-03-scaffolding-sequence.md#toolchain-prerequisites) are met, including simulator runtimes that can create the exact gate destinations.
- [x] [Repository layout](../architecture/repository-layout.md) is accepted and `Active`. Evidence: 2026-10-22 owner entry in [changelog.md](changelog.md).

## In scope

- An XcodeGen specification that produces `ResetRadar.xcodeproj` with every composition-root and test target, schemes `ResetRadar`, `ResetRadarMac`, and `ResetRadarWatch`, and Development and Release configurations. The specification is the source of truth; generated project output is not committed.
- The `ResetRadarKit` package with nine library modules, one individually consumable library product per module, and eight test targets. The `ResetRadarTestSupport` product is available only to test dependency graphs and intentionally has no test target of its own.
- The `relay/` package: strict TypeScript, Workers Vitest, Wrangler pinned, committed lockfile, `test` and `typecheck` scripts.
- `.swift-format`, `.swiftlint.yml`, and ignore rules.
- Entitlements, bundle identifiers, App Group, and signing settings; the Release-only Mac signing check.
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
- **Decided — simulator destinations.** Preserve iPhone 17 Pro Max and iPad Air 11-inch (M2). The owner lowered the iOS and iPadOS floor to 26.1 so the installed 26.1 runtime hosts both; no other model changes.
- **Decided — test frameworks.** Swift Testing for package test targets; XCTest for the app-level and UI bundles.
- **Decided — XcodeGen pin.** `Scripts/generate-project.sh` requires XcodeGen 2.46.0 exactly.
- **Decided — Mac signing scope.** Only Release builds are signed with the identity and checked; Development builds are unsigned.
- **Decided — repository layout.** The owner accepted the XcodeGen-based [repository layout](../architecture/repository-layout.md), which is now `Active`.

## Completion checklist

- [x] Entry criteria all hold. Evidence: links to the changelog entries and command output.
- [x] Owner decisions are complete and recorded in [changelog.md](changelog.md) and [AGENTS.md](../../AGENTS.md). Evidence: 2026-10-22 owner entry and the binding scaffolding decision.
- [x] Deployment targets (iOS/iPadOS 26.1, watchOS 26.6, macOS 26.7.1) are accepted by Xcode and SwiftPM, or the documented minor-version fallback is applied and recorded. Evidence: build settings and command output.
- [x] Every target builds with Swift 6 language mode and strict concurrency. Evidence: build log summary.
- [x] The generated target inventory is exact: six production Xcode targets, four Xcode test targets, nine Swift package library targets/products, eight Swift package test targets, and three shared schemes/test plans. Evidence: XcodeGen specification, `xcodebuild -list`, Swift package description, and test-plan listing.
- [x] A deliberately violating import (an adapter importing another adapter, and a Domain import of Application) fails the build; the probe is removed afterward. Evidence: failing command output.
- [x] The Release Mac signing check passes with the Personal Team identity and fails an ad-hoc Release build; its placement relative to code signing is recorded. Development builds and the gate run without a local signing file. Evidence: build outcomes.
- [x] The import-boundary check rejects a transitive import from an Xcode target and the iOS widget extension's import of Scheduling beyond notifications and activity attributes. Evidence: failing probes, removed afterward.
- [x] Each simulator destination name resolves to one device on the intended runtime. Evidence: `xcrun simctl list devices` excerpt.
- [x] `Scripts/generate-project.sh` rejects any XcodeGen version other than 2.46.0. Evidence: failing and passing output.
- [x] Entitlements match each composition root's configuration table; no Push Notifications, iCloud, CloudKit, analytics, provider-credential, or profile-requiring Mac entitlement. Evidence: entitlements inspection.
- [x] App ID count is within the free account's 10-per-7-days budget and bundle identifiers are stable. Evidence: the identifier list and count.
- [x] One shared test plan per scheme runs the package test targets for its platform plus its app-level bundle; the `ResetRadar` plan also runs `ResetRadarUITests` on both iPhone and iPad. Evidence: test-plan listing and test run.
- [x] The checked-in format script passes explicit maintained source roots to `swift-format`, and SwiftLint exclusions cover generated, external, build, and spike output. Evidence: script inspection and lint output with inputs and exclusions listed.
- [x] The relay installs from the lockfile with `npm ci`, pins direct development dependencies and the compatibility date, and generates ignored `worker-configuration.d.ts` on demand before type-checking. Evidence: clean-checkout install, generation, test, dry-run bundle, and type-check output.
- [x] Shared protocol fixtures are present and read by both Swift Transport tests and relay tests.
- [x] No physical-device check is carried forward from P1-M2 (owner override). Evidence: 2026-10-22 changelog entry.
- [x] Docs are updated: README no longer says the apps are unscaffolded; the contribution guide and architecture use the same clean-checkout gate, including `npm ci` and the non-deploying Wrangler dry run; and the documentation index lists new docs.
- [x] From a clean checkout with no `node_modules/`, the complete gate installs relay dependencies and passes with no deferral in one run. Evidence: every command and result in the contribution guide.

## Acceptance evidence

Recorded 2026-10-22 on the development Mac (Xcode 27.1, XcodeGen 2.46.0, Node 26, npm 11).

- **Deployment targets.** SwiftPM accepted `.iOS("26.1")`, `.watchOS("26.6")`, and `.macOS("26.7.1")`; Xcode built all three schemes at those targets with no minor-version fallback.
- **Language mode.** Every target builds in Swift 6 mode with `SWIFT_STRICT_CONCURRENCY = complete` with no warnings.
- **Inventory.** `Scripts/generate-project.sh` asserts ten targets, the Development and Release configurations, exactly the three shared schemes `ResetRadar`, `ResetRadarMac`, and `ResetRadarWatch`, and the three checked-in test plans; regeneration produced an identical `project.pbxproj` hash. Xcode also lists auto-created, unshared schemes for package products; they are not part of the inventory.
- **Import probes.** With `swift build --explicit-target-dependency-import-check=error`, a Domain import of Application failed (dependency cycle) and a Storage import of Transport failed (“missing a dependency”). `Scripts/check-imports.sh` rejected a `ResetRadar` import of ProviderAdapters, an unscoped and an unlisted scoped widget import of Scheduling, and a Mac import of TestSupport, and accepted the listed `ResetActivityAttributes` scoped import. All probes were removed. Without the explicit flag, plain `swift build` accepted the violations.
- **Mac signing.** The `ResetRadarMac` scheme's post-action passes a Release build signed with the Personal Team identity (local, untracked `Config/Build/Local.xcconfig`) and fails an ad-hoc Release build with exit 65. A script phase runs before signing, so a post-action is required.
- **Entitlements.** The four iOS and watchOS entitlement files contain only `com.apple.security.application-groups` and `keychain-access-groups`; the Mac app has none.
- **App IDs.** Four profile-bearing identifiers (`ResetRadar`, `.Widgets`, `.watchkitapp`, `.watchkitapp.Widgets`), within the budget of ten.
- **Destinations.** `name=iPhone 17 Pro Max` alone resolves to “OS:latest” (27.1), where no such device exists, and fails. The gate therefore pins `OS=26.1` for both iOS destinations; the iPad Air 11-inch (M2) was created on iOS 26.1, and the Apple Watch Series 11 (42mm) on watchOS 27.0.
- **Relay.** From a clean tree, `npm ci` installed 81 packages from the lockfile; the two Workers Vitest tests (including the shared fixture), type-check, and `deploy:dry-run` passed. The dry run exits after bundling with no login, browser, or upload. `npm audit` reports two moderate advisories in development dependencies; they were not addressed because remediation would change approved pins.
- **Clean-checkout gate.** In a fresh clone with no `node_modules`, generated project, or local signing file, all ten gate steps exited 0: 10 tests on iPhone, 10 on iPad, 9 on Mac, 6 on Watch, and 2 relay tests; formatting, SwiftLint (31 files, 0 violations), and the import check passed.
