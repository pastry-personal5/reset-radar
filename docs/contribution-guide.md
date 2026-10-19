# Contribution Guide

Status: Active

How to set up `reset-radar`, validate a change, write commit messages, and open a pull request.

## Setup and development

- macOS with Xcode 26 or newer (iOS 26 SDK and simulator).
- swiftlint, for example `brew install swiftlint`.
- swift-format, bundled with the Swift toolchain.

```sh
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17'  # run the tests
swift-format format --in-place --recursive .                                             # format
swift-format lint --strict --recursive .                                                 # check formatting
swiftlint --strict                                                                       # lint
```

## Required validation

Before opening a pull request, run the full checks from the repository root:

```sh
swift-format lint --strict --recursive .
swiftlint --strict
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Personal-device installation

The first version uses a free Apple account and Sideloadly rather than App Store or TestFlight distribution. The signing constraints, required physical-device checks, and future repeatable installation workflow are tracked in [personal-use-sideloading.md](research/phase-1/personal-use-sideloading.md). The workflow cannot be completed until P1-M3 creates the Xcode targets and an IPA.

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
