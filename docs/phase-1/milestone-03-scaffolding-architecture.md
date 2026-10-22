# P1-M3: Scaffolding sequencing

Status: Planned

Order of work, prerequisites, and risks for [P1-M3](milestone-03-scaffolding-overview.md). The system design stays in the [software architecture](../architecture.md); the target directory tree is in [repository layout](../architecture/repository-layout.md).

## Toolchain prerequisites

Recorded on 2026-10-22 on the development Mac. Xcode, SDK, Swift, SwiftLint, Node, and npm versions were rechecked during plan review; CoreSimulatorService was unavailable during that recheck, so every runtime and device observation must be repeated before implementation:

| Item | State | Action |
|---|---|---|
| Xcode | 27.1 selected; SDKs meet the minimums. | None. |
| XcodeGen | Selected by the owner; not installed during plan review. | Install a documented tested version before implementation and record it in the contribution guide. |
| Personal Team identity | One Apple Development identity is present. | Confirm it is the owner's intended signing identity before the Mac build check. |
| swift-format, swiftlint, Node 26, npm 11 | Installed. | None. |
| iOS simulator runtimes | Only iOS 27.0 and 27.1 are installed. The iPhone 17 Pro Max and iPad Air 11-inch (M2) device types refuse to create on them (“Incompatible device”). | Install an iOS 26.x runtime at or above 26.6.2, then create both devices on it. If none can be installed, the destinations are an owner decision. |
| watchOS simulator runtime | watchOS 27.0 creates Apple Watch Series 11 (42mm). | Create the device; confirm the watchOS 27 runtime satisfies the 26.6 floor. |

Runtimes at or above the minimum are required, but the minimum alone is not enough: the runtime must also support the reference device types.

## Sequence

1. **Entry criteria and decisions.** Close the overview's entry criteria and open questions. Record answers in the changelog.
2. **Branch.** Work on a fresh branch from `main`, not the spike branch. Copy only reviewed fixtures or code from spikes.
3. **Configuration first.** Add `.swift-format`, `.swiftlint.yml`, `.gitignore` additions, a checked-in format script with explicit maintained source roots, shared Development and Release settings, and a committed template for untracked signing values. Ignore generated `ResetRadar.xcodeproj`. Keep formatter and linter inputs limited to maintained Swift sources rather than generated or spike output.
4. **Package.** Create `ResetRadarKit` with nine library targets and products, explicit target dependencies matching [Target imports](../architecture.md#target-imports), and eight test targets with one passing compile smoke test each. Link `ResetRadarTestSupport` only to tests. Prove the negative import cases and remove the probes.
5. **Project.** Create the XcodeGen specification for six production targets, four Xcode test targets, three shared schemes and checked-in test plans, entitlements, bundle identifiers, and empty asset catalogs. Generate the project from a clean state, verify the declared inventory, regenerate it to check determinism, and keep the generated project untracked. Verify patch-level deployment targets; apply the documented fallback if rejected.
6. **Mac signing.** Add the build-phase check; exercise it with the identity and with an ad-hoc build.
7. **Relay.** Create `package.json`, lockfile, TypeScript config, Workers Vitest config, and placeholder tests. Pin every direct development dependency and the compatibility date. Generate `worker-configuration.d.ts` on demand as part of type-checking and ignore it. Expose a `deploy:dry-run` script that validates and bundles the Wrangler configuration without contacting or deploying to Cloudflare.
8. **Fixtures.** Add `Fixtures/Protocol` and wire both test suites to it.
9. **Carried evidence.** Complete any P1-M2 physical-device validation explicitly assigned to P1-M3, using only synthetic state. Do not connect provider sources or real usage to the scaffold.
10. **Docs.** Update README, contribution guide, documentation index, phase doc, and changelog.
11. **Gate.** Start without `relay/node_modules`, run the complete gate once, and record concise results.

## Required gate shape

P1-M3 updates the contribution guide and the build contract together so a clean checkout installs locked relay dependencies before using them. The final gate retains the four approved simulator destinations and includes these operations, with the relay operations allowed on one shell line:

```sh
Scripts/generate-project.sh
Scripts/lint-swift-format.sh
swiftlint --strict
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M2)'
xcodebuild test -scheme ResetRadarMac -destination 'platform=macOS'
xcodebuild test -scheme ResetRadarWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)'
npm --prefix relay ci
npm --prefix relay test && npm --prefix relay run typecheck && npm --prefix relay run deploy:dry-run
```

The generation script must invoke the documented XcodeGen version against the checked-in specification and fail if its expected targets, shared schemes, configurations, or test plans are absent. The format script must invoke `swift-format lint --strict --recursive` with an explicit, reviewed list of maintained Swift roots; swift-format has no configuration-file exclusion mechanism. P1-M3 updates `AGENTS.md`, the development process, and the contribution guide to use both scripts consistently.

The relay dry run must not authenticate, create a Preview URL, deploy a Worker, or contact an existing Worker. It validates only the checked-in package and configuration.

Until those files and scripts land together, the existing contribution guide remains the current gate; this section specifies the required post-scaffold replacement and is not a claim that the planned commands exist yet.

## Risks

- **Runtime and device mismatch** blocks the gate (see prerequisites).
- **Free-account limits.** Count App IDs (iOS app, widget extension, Watch app, Watch complication) against the 10-per-7-days budget and keep identifiers stable; validate App Group availability when carried-forward physical signing is run.
- **Gate scope.** Extension and helper targets are built only through scheme dependencies; confirm each scheme's build and test actions actually build them.
- **Generated-project drift.** `ResetRadar.xcodeproj` is disposable output. Review and version the XcodeGen specification, never a hand-edited project file, and prove repeatable generation before the gate.
- **Package exposure.** An umbrella Swift package product would let composition roots acquire unintended modules. Expose the nine products individually and link only the products in the architecture's target-import table.
- **Unversioned local files.** Team identifiers and certificate fingerprints stay in untracked local settings created from a committed, non-secret template. Generated Worker types and build output also remain untracked.
