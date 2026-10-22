# P1-M3: Scaffolding sequencing

Status: Done

Order of work, prerequisites, and risks for [P1-M3](milestone-03-scaffolding-overview.md). The system design stays in the [software architecture](../architecture.md); the target directory tree is in [repository layout](../architecture/repository-layout.md).

## Toolchain prerequisites

Rechecked on 2026-10-22 on the development Mac after the earlier plan review, which could not reach CoreSimulatorService. Repeat every observation at the start of implementation:

| Item | State | Action |
|---|---|---|
| Xcode | 27.1 selected; SDKs meet the minimums. | None. |
| XcodeGen | 2.46.0 installed (Homebrew, 2026-10-22). | Record 2.46.0 as the tested version; `Scripts/generate-project.sh` fails on any other version. Document the install in the contribution guide. |
| Personal Team identity | One Apple Development identity is present. | Confirm it is the owner's intended signing identity before the Mac build check. |
| swift-format, swiftlint, Node 26, npm 11 | Installed. | None. |
| iOS simulator runtimes | iOS 26.1, 27.0, and 27.1 are installed. Both iOS reference device types create on 26.1 and refuse on 27.x (“Incompatible device”); verified 2026-10-22 and the probe device removed. | The owner lowered the iOS and iPadOS floor to 26.1 (see the [changelog](changelog.md)). Create the iPhone 17 Pro Max and iPad Air 11-inch (M2) devices on the iOS 26.1 runtime and confirm `xcodebuild` resolves each destination name uniquely. |
| watchOS simulator runtime | watchOS 26.1 and 27.0 are installed; 27.0 creates Apple Watch Series 11 (42mm). | Create the device on a runtime at or above the 26.6 floor (27.0) and confirm the destination name resolves uniquely. |

Runtimes at or above the minimum are required, but the minimum alone is not enough: the runtime must also support the reference device types. Duplicate device names across runtimes make `name=` destinations ambiguous, so the gate records the resolved runtime for each destination.

## Sequence

1. **Entry criteria and decisions.** Close every overview entry criterion, including exact-version approval for the relay development dependencies (see [Relay](#relay-dependencies)). Record answers in the changelog, then set P1-M3 to `Active` in [phase-1.md](phase-1.md) and add the milestone's verifiable checklist items before writing code.
2. **Branch and clean-up.** Work on a fresh branch from `main`, not a spike branch. Remove the untracked leftover `relay/` directory (`node_modules` and `worker-configuration.d.ts` from the spike branch) before creating the real package. Copy only reviewed fixtures or code from spikes.
3. **Configuration first.** Add `.swift-format`, `.swiftlint.yml`, `.gitignore` additions, a checked-in format script with explicit maintained source roots, shared Development and Release settings, and a committed template for untracked signing values. Ignore generated `ResetRadar.xcodeproj`. Keep formatter and linter inputs limited to maintained Swift sources rather than generated or spike output.
4. **Package.** Create `ResetRadarKit` with nine library targets and products, explicit target dependencies matching [Target imports](../architecture.md#target-imports), and eight test targets with one passing compile smoke test each. Link `ResetRadarTestSupport` only to tests. Package tests use Swift Testing. Prove the negative import cases and remove the probes. SwiftPM target dependencies do not by themselves stop an Xcode target from importing a transitively linked module or let the iOS widget extension import only part of Scheduling, so choose and prove a check that covers Xcode targets and that partial import before relying on the dependency rule.
5. **Project.** Create the XcodeGen specification for six production targets, four Xcode test targets (XCTest, which the app-level and UI bundles require), three shared schemes and checked-in test plans, entitlements, bundle identifiers, and empty asset catalogs. Generate the project from a clean state, verify the declared inventory, regenerate it to check determinism, and keep the generated project untracked. Verify patch-level deployment targets; apply the documented fallback if rejected.
6. **Mac signing.** Add the Release-configuration signing check and decide where it runs relative to code signing; a script phase can run before signing, so a scheme post-action or a separate verification step may be needed. Exercise it with the identity and with an ad-hoc Release build. Development builds are unsigned and skip the check, so the gate needs no machine-local signing file.
7. **Relay.** Reuse only reviewed pieces of the spike relay. Create `package.json`, lockfile, TypeScript config, Workers Vitest config, and placeholder tests. Pin every direct development dependency and the compatibility date. Generate `worker-configuration.d.ts` on demand as part of type-checking and ignore it. Expose a `deploy:dry-run` script that validates and bundles the Wrangler configuration without contacting or deploying to Cloudflare.
8. **Fixtures.** Add `Fixtures/Protocol` and wire both test suites to it.
9. **Carried evidence.** Complete any P1-M2 physical-device validation explicitly assigned to P1-M3, using only synthetic state. Do not connect provider sources or real usage to the scaffold.
10. **Docs.** Update README, contribution guide, documentation index, phase doc, and changelog.
11. **Gate.** Start without `relay/node_modules`, run the complete gate once, and record concise results.

## Relay dependencies

The spike relay declares `@cloudflare/vitest-plugin ^1.0.0`, `typescript ^5.9.3`, `vitest ^4.1.0`, and `wrangler ^4.0.0`. At implementation start, resolve their current exact versions, list them with licenses for owner approval in the changelog, and pin them exactly in `package.json` with a committed lockfile. Add nothing else without approval.

## Identifiers

Bundle identifiers are proposed here and are not final until the owner confirms the list; register no App ID before then. The App ID budget counts only the four profile-bearing iOS and watchOS targets.

| Target | Proposed identifier | App ID |
|---|---|---|
| `ResetRadar` | `com.unidentifiedstealthstartup.ResetRadar` | yes |
| `ResetRadarWidgets` | `com.unidentifiedstealthstartup.ResetRadar.Widgets` | yes |
| `ResetRadarWatch` | `com.unidentifiedstealthstartup.ResetRadar.watchkitapp` | yes |
| `ResetRadarWatchWidgets` | `com.unidentifiedstealthstartup.ResetRadar.watchkitapp.Widgets` | yes |
| `ResetRadarMac` | `com.unidentifiedstealthstartup.ResetRadarMac` | no |
| `ResetRadarStatusLine` | `com.unidentifiedstealthstartup.ResetRadarMac.StatusLine` | no |

## Required gate shape

P1-M3 updates the contribution guide and the build contract together so a clean checkout installs locked relay dependencies before using them. The final gate retains the four approved simulator destinations and includes these operations, with the relay operations allowed on one shell line:

```sh
Scripts/generate-project.sh
Scripts/lint-swift-format.sh
swiftlint --strict
Scripts/check-imports.sh
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.1'
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M2),OS=26.1'
xcodebuild test -scheme ResetRadarMac -destination 'platform=macOS'
xcodebuild test -scheme ResetRadarWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)'
npm --prefix relay ci
npm --prefix relay test && npm --prefix relay run typecheck && npm --prefix relay run deploy:dry-run
```

The generation script must invoke the documented XcodeGen version against the checked-in specification and fail if its expected targets, shared schemes, configurations, or test plans are absent. The format script must invoke `swift-format lint --strict --recursive` with an explicit, reviewed list of maintained Swift roots; swift-format has no configuration-file exclusion mechanism. P1-M3 updates `AGENTS.md`, the development process, and the contribution guide to use both scripts consistently.

The relay dry run must not authenticate, create a Preview URL, deploy a Worker, or contact an existing Worker. It validates only the checked-in package and configuration.

The iOS destinations carry `OS=26.1` because `name=` alone resolves to the newest installed runtime (27.1), where the reference iPhone and iPad device types do not exist. The commands above are now the gate in the [contribution guide](../contribution-guide.md).

## Risks

- **Runtime and device mismatch** blocks the gate (see prerequisites). The iOS 26.1 floor is simulator-proven only.
- **Signing-check placement (resolved).** A script phase would run before code signing, so the Release check is the `ResetRadarMac` scheme's build post-action. It runs only through that scheme (`xcodebuild -scheme ResetRadarMac`, Archive); a bare target build skips it.
- **Import-boundary coverage (resolved).** `Scripts/check-imports.sh` runs SwiftPM's explicit dependency import check on the package and compares each Xcode target's `ResetRadar*` imports with `Config/import-boundaries.txt`; the iOS widget extension may import Scheduling only through a scoped import of a listed symbol. Only `ResetActivityAttributes` is listed; add the notification-reconciliation symbol when Scheduling defines it.
- **Free-account limits.** Count App IDs (iOS app, widget extension, Watch app, Watch complication) against the 10-per-7-days budget and keep identifiers stable; validate App Group availability when carried-forward physical signing is run.
- **Gate scope.** Extension and helper targets are built only through scheme dependencies; confirm each scheme's build and test actions actually build them.
- **Generated-project drift.** `ResetRadar.xcodeproj` is disposable output. Review and version the XcodeGen specification, never a hand-edited project file, and prove repeatable generation before the gate.
- **Package exposure.** An umbrella Swift package product would let composition roots acquire unintended modules. Expose the nine products individually and link only the products in the architecture's target-import table.
- **Unversioned local files.** Team identifiers and certificate fingerprints stay in untracked local settings created from a committed, non-secret template. Generated Worker types and build output also remain untracked.
