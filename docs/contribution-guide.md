# Contribution Guide

Status: Active

How to set up `reset-radar`, validate a change, write commit messages, and open a pull request.

The documented local checks are also available as named targets in the root
`Makefile`; run `make help` to list them and `make gate` for the complete gate. `make test`
runs the macOS suite and then the iPhone, iPad, and Watch suites so they do not compete for Xcode
and simulator services, beside the independent relay suite. The iPhone and iPad suites run in one
`xcodebuild` invocation (`make test-ios-ipad`), which builds once and tests both simulators concurrently;
`make test-ios` and `make test-ipad` run a single destination. Each suite retains its native
bounded test scheduling. The Make targets keep reusable DerivedData caches isolated by platform,
preventing iOS, Watch, and Mac simulator modules from contaminating one another while retaining
incremental builds.

The iOS UI tests launch the Development app with `-ResetRadarSyntheticScenario <name>`, which uses
an isolated temporary store, in-memory secrets, and an in-process synthetic relay. Development
builds are unsigned, so a simulator run has no App Group entitlement and uses its own Debug
storage instead. UI tests wait with `appears(timeout:)` or `waitUntil(timeout:_:)` from
`ResetRadarUITests/ReaderUITestSupport.swift`, not `waitForExistence(timeout:)` or
`XCTNSPredicateExpectation`, because XCTest checks those only about once a second.

Run `make run-mac` to generate, build, and open the Development Mac collector with its normal
live-source mode. Use Xcode to supply launch arguments such as `--synthetic` for fixture work.
For local root-cause analysis, read Development's bounded JSON Lines in
`~/Library/Logs/ResetRadar.dev/`. Release has a separate
`~/Library/Logs/ResetRadar/` directory. For example, inspect recent Development events with
`tail -n 100 "$HOME/Library/Logs/ResetRadar.dev"/events-*.jsonl`; these logs contain typed,
redacted events and retain at most eight UTC days. Do not copy the logs into the repository.

## Setup and development

- An Apple-silicon Mac running macOS 26.7.1 or newer, with an Xcode whose SDKs are at least iOS 26.1, watchOS 26.6, and macOS 26.7, and iOS and watchOS simulator runtimes at or above the minimum OS versions in [Platform targets](architecture.md#platform-targets). Select that Xcode with `xcode-select` and accept its license before building. Mac targets are arm64-only; Intel development and `x86_64` slices are unsupported.
- swiftlint, for example `brew install swiftlint`.
- swift-format, bundled with the Swift toolchain.
- XcodeGen 2.46.0 exactly, for example `brew install xcodegen`; `Scripts/generate-project.sh` refuses any other version.
- Node.js 26 and npm 11 for the TypeScript Cloudflare relay and its validation harness.
- Simulators: an iOS 26.1 runtime with the iPhone 17 Pro Max and iPad Air 11-inch (M2), and a watchOS runtime at or above 26.6 with the Apple Watch Series 11 (42mm). The iOS destinations name the runtime because `name=` alone resolves to the newest installed runtime, which cannot host these devices.

```sh
Scripts/generate-project.sh                                                                # generate the ignored Xcode project
xcodebuild test -scheme ResetRadarMac -destination 'platform=macOS'                       # run the tests
make test-ios-ipad                                                                         # build once; test both iOS destinations concurrently
xcodebuild test -scheme ResetRadarWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)'             # Watch app and package tests
swift-format format --in-place --recursive <maintained roots in Scripts/swift-roots.txt>   # format
Scripts/lint-swift-format.sh                                                               # check formatting
swiftlint --strict                                                                         # lint
Scripts/check-imports.sh                                                                   # enforce the dependency rule
Scripts/check-mac-architecture.sh                                                          # build and inspect unsigned Release Mac binaries
```

The relay exposes reproducible npm scripts for TypeScript checking, Workers Vitest tests, and a Wrangler deployment dry run that never contacts Cloudflare. Mac Release builds need an untracked `Config/Build/Local.xcconfig` copied from `Local.xcconfig.template`; Development builds and the gate do not. The architecture check makes an isolated unsigned Release build and verifies every Mach-O executable with `lipo`; it does not replace the signed Release scheme check. Do not run a real deployment until the synthetic-data procedure confirms Workers Free, disabled observability, and owner-present approval.

## Required validation

Before opening a pull request, run the full checks from the repository root:

```sh
Scripts/generate-project.sh
Scripts/lint-swift-format.sh
swiftlint --strict
Scripts/check-imports.sh
Scripts/check-mac-architecture.sh
xcodebuild test -scheme ResetRadarMac -destination 'platform=macOS'
make test-ios-ipad
xcodebuild test -scheme ResetRadarWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)'
npm --prefix relay ci
npm --prefix relay test && npm --prefix relay run typecheck && npm --prefix relay run deploy:dry-run
```

The relay has no separate linter or formatter; adding one is a dependency decision that needs owner approval.

## Personal-device installation

The first version uses a free Apple account and Sideloadly rather than App Store or TestFlight
distribution. Follow the [sideloading user guide](user-guide-for-sideloading.md) for routine
installation. Physical validation uses the reference devices in
[Platform targets](architecture.md#platform-targets); maintainers should follow the detailed
[owner-run installation procedure](research/personal-use-sideloading.md#p1-m14-reader-installation-procedure)
for package inspection, current Xcode Apple Accounts navigation, and sanitized evidence.
Sideloadly Normal Install placed the app on the reference iPhone, it launched after owner trust,
and physical QR pairing succeeded on 2026-10-27. Extension behavior, first-unlock and
cache-persistence checks, the reference iPad run, and a seven-day renewal path still need device
evidence.

After configuring Release signing in the untracked `Config/Build/Local.xcconfig` as that procedure
requires, run `make ipa` from the repository root. It creates the signed package at
`.build/ipa/ResetRadar.ipa`; if that file already exists, the target preserves it. Remove or move
that specific package before running the target again when a fresh export is required.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org):
`<type>[(scope)]: <imperative summary>`. Keep the lowercase title at most 50
characters with no period. Use a short body only to explain why.

Keep each commit focused. Example:

    feat(parser): add support for nested lists

    Nested list items were flattened into a single level. Keep the nesting
    so the parsed document matches the source.

## Pull requests

TBD
