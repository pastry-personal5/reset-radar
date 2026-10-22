# Contribution Guide

Status: Active

How to set up `reset-radar`, validate a change, write commit messages, and open a pull request.

## Setup and development

- macOS 26.7.1 or newer, with an Xcode whose SDKs are at least iOS 26.1, watchOS 26.6, and macOS 26.7, and iOS and watchOS simulator runtimes at or above the minimum OS versions in [Platform targets](architecture.md#platform-targets). Select that Xcode with `xcode-select` and accept its license before building.
- swiftlint, for example `brew install swiftlint`.
- swift-format, bundled with the Swift toolchain.
- Node.js 26 and npm 11 for the planned TypeScript Cloudflare relay and its validation harness.

```sh
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'  # run the tests
swift-format format --in-place --recursive .                                             # format
swift-format lint --strict --recursive .                                                 # check formatting
swiftlint --strict                                                                       # lint
```

The relay workspace will expose reproducible npm scripts for TypeScript checking, Workers Vitest tests, and a Wrangler deployment dry run when its files are added. Do not run a real deployment until the synthetic-data procedure confirms Workers Free, disabled observability, and owner-present approval.

## Required validation

Before opening a pull request, run the full checks from the repository root:

```sh
swift-format lint --strict --recursive .
swiftlint --strict
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M2)'
xcodebuild test -scheme ResetRadarMac -destination 'platform=macOS'
xcodebuild test -scheme ResetRadarWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)'
npm --prefix relay test && npm --prefix relay run typecheck
```

The relay has no separate linter or formatter; adding one is a dependency decision that needs owner approval.

## Personal-device installation

The first version uses a free Apple account and Sideloadly rather than App Store or TestFlight distribution. Physical validation uses the reference devices in [Platform targets](architecture.md#platform-targets). The signing constraints, required physical-device checks, and future repeatable installation workflow are tracked in [personal-use-sideloading.md](research/phase-1/personal-use-sideloading.md). The workflow cannot be completed until P1-M3 creates the Xcode targets and an IPA.

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
