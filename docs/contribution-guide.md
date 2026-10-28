# Contribution Guide

Status: Active

How to set up `reset-radar`, validate a change, write commit messages, and open a pull request.

The documented local checks are named targets in the root `Makefile`; run `make help` to
list them and `make gate` for the complete gate. Make serializes its goals even with `-j` or
inherited `MAKEFLAGS`: generation, Apple builds/tests, and relay dependency installation must
finish before their consumers run. `make test` runs macOS, iPhone, iPad, Watch, then relay tests.
`make test-ios-ipad` runs the two iOS destinations in order with a shared reusable DerivedData
cache. Mac, iOS, and Watch caches remain separate to avoid cross-platform module reuse.

Apple simulator targets start with `make simulator-preflight`, a bounded CoreSimulator service
check. Run Apple validation in the logged-in host user session. A coding-agent filesystem sandbox
cannot access CoreSimulator's launchd service or Xcode/SwiftPM's user caches; errors such as
`Operation not permitted`, `Connection refused`, and missing runtimes in that environment require
approved host execution. Changing `HOME`, redirecting only DerivedData, or erasing simulator data
does not grant service access. Do not run independent gates against the same checkout at once.

Potentially blocking Make commands have a 600-second wall-clock watchdog. Override it for a
known-slow machine with `make COMMAND_TIMEOUT_SECONDS=900 gate`. The watchdog prints progress
every 30 seconds, forwards cancellation, kills remaining descendants even when their leader exits,
and returns 124 on timeout. `make pipeline-tests` checks deadline validation, exit codes, timeout,
and cancellation without requiring Xcode. Failed Apple test actions retain their console log and
result bundle at the printed `/private/tmp/reset-radar-xcode-test.*` path; successful actions remove
that scratch directory. Test results use unique local paths and coverage collection is disabled.
Neither setting is evidence that the workspace volume or coverage caused a stall.

The iOS runner executes the complete test plan once per destination, with Xcode worker
parallelism disabled. It has one deadline for the entire action and does not retry or split test
methods to conceal a failure. Run `make test-ios` or `make test-ipad` for one reference device.
Hosted reader tests inject a separate `FakeWatchLink` per harness. Never construct multiple
live bridges around `WCSession.default` in parallel tests: replacing its singleton delegate can
strand another harness's activation continuation and leave the test action waiting indefinitely.

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

- An Apple-silicon Mac running macOS 26.7.1 or newer, with an Xcode whose SDKs are at least iOS 27.0, watchOS 27.0, and macOS 26.7, and iOS and watchOS simulator runtimes at or above the minimum OS versions in [Platform targets](architecture.md#platform-targets). Select that Xcode with `xcode-select` and accept its license before building. Mac targets are arm64-only; Intel development and `x86_64` slices are unsupported.
- swiftlint, for example `brew install swiftlint`.
- swift-format, bundled with the Swift toolchain.
- XcodeGen 2.46.0 exactly, for example `brew install xcodegen`; `Scripts/generate-project.sh` refuses any other version.
- Node.js 26 and npm 11 for the TypeScript Cloudflare relay and its validation harness.
- Simulators: an iOS 27.0-or-newer runtime with the iPhone 18 Pro Max and iPad Air
  11-inch (M4), and a watchOS 27.0-or-newer runtime with the Apple Watch Series 11 (42mm).
  These exact reference destinations are owner-approved and used by the complete gate; do not
  substitute models implicitly.

```sh
make generate         # generate the ignored Xcode project
make test-mac         # bounded macOS tests
make test-ios-ipad    # reference iPhone, then iPad
make test-watch       # bounded Watch app and package tests
make format           # format maintained Swift roots
make format-check     # check formatting
make lint             # strict SwiftLint
make imports          # enforce the dependency rule
make mac-arch-check   # build and inspect unsigned Release Mac binaries
```

The relay exposes reproducible npm scripts for TypeScript checking, Workers Vitest tests, and a Wrangler deployment dry run that never contacts Cloudflare. Mac Release builds need an untracked `Config/Build/Local.xcconfig` copied from `Local.xcconfig.template`; Development builds and the gate do not. The architecture check makes an isolated unsigned Release build and verifies every Mach-O executable with `lipo`; it does not replace the signed Release scheme check. Do not run a real deployment until the synthetic-data procedure confirms Workers Free, disabled observability, and owner-present approval.

## Required validation

Before opening a pull request, run the full checks from the repository root:

```sh
make gate
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

The generated `ResetRadarWatch` scheme runs in signed Release for a physical Watch. Its
Development configuration remains unsigned for simulator builds and tests. If installation from
the iPhone Watch app stalls, use the direct Xcode Run steps in the
[sideloading guide](user-guide-for-sideloading.md#run-the-watch-app-from-xcode).

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
