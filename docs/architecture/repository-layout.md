# Repository layout

Status: Active

Directory structure of the `reset-radar` repository: the Xcode project, the `ResetRadarKit` package, one directory per Xcode target, shared configuration and fixtures, and the `relay/` package. It names only structure-defining files; source files belong in the module and composition-root designs linked from the [software architecture](../architecture.md).

## Tree

```text
reset-radar/
├── project.yml                     XcodeGen source of truth for targets, schemes, configurations
├── ResetRadar.xcodeproj/           Generated, ignored Xcode project; never edited directly
├── Design/                          Editable source artwork for exported app assets
├── ResetRadarKit/                  Local Swift package; no third-party dependencies
│   ├── Package.swift               Nine library products/targets and eight test targets
│   ├── Sources/
│   │   ├── ResetRadarDomain/
│   │   ├── ResetRadarApplication/
│   │   ├── ResetRadarStorage/
│   │   ├── ResetRadarTransport/
│   │   ├── ResetRadarScheduling/
│   │   ├── ResetRadarWatchSync/
│   │   ├── ResetRadarProviderAdapters/
│   │   ├── ResetRadarUI/
│   │   └── ResetRadarTestSupport/
│   └── Tests/
│       ├── ResetRadarDomainTests/
│       ├── ResetRadarApplicationTests/
│       ├── ResetRadarStorageTests/
│       ├── ResetRadarTransportTests/
│       ├── ResetRadarSchedulingTests/
│       ├── ResetRadarWatchSyncTests/
│       ├── ResetRadarProviderAdaptersTests/
│       └── ResetRadarUIComponentTests/
├── ResetRadar/                     iOS and iPadOS app target
│   └── Resources/                  Asset catalog, localized strings
├── ResetRadarWidgets/              iOS widget extension
│   └── Resources/
├── ResetRadarWatch/                watchOS app target
│   └── Resources/
├── ResetRadarWatchWidgets/         watchOS complication extension
│   └── Resources/
├── ResetRadarMac/                  macOS app target
│   └── Resources/
├── ResetRadarStatusLine/           macOS command-line helper embedded in the Mac app
├── ResetRadarTests/                iOS app-level integration tests
├── ResetRadarUITests/              iOS UI tests (iPhone and iPad simulators)
├── ResetRadarMacTests/             Mac lifecycle and integration tests
├── ResetRadarWatchTests/           Watch payload and complication tests
├── Config/
│   ├── Build/                      Shared and per-configuration build settings
│   ├── Entitlements/               Entitlements for targets that require capabilities
│   └── TestPlans/                  One test plan per scheme
├── Scripts/                        Build-phase and gate scripts, including the Mac signing check
├── Fixtures/
│   ├── Protocol/                   Synthetic relay protocol and envelope fixtures shared with relay/
│   └── Providers/                  Synthetic Codex and Claude Code payloads
├── relay/                          Cloudflare relay; independent TypeScript package
│   ├── src/
│   │   ├── domain/
│   │   ├── application/
│   │   └── adapters/
│   ├── test/
│   └── scripts/                    Provisioning script for Worker secrets
├── docs/                           Plans and design documents
└── spikes/                         Throwaway spike harnesses; never promoted wholesale
```

## Rules

- **One production module, one directory pair.** Each production `Sources/<Module>` has a `Tests/<Module>Tests` directory, except UI, whose tests are `ResetRadarUIComponentTests`. The ninth module, `ResetRadarTestSupport`, is test support and has no test directory of its own.
- **One module, one product.** Each package module is exposed as its own library product so Xcode targets link only the modules allowed by [Target imports](../architecture.md#target-imports). There is no umbrella product. The `ResetRadarTestSupport` product is linked only into test targets and never into a production app, extension, or helper.
- **Dependencies point inward.** Directory placement mirrors [Target imports](../architecture.md#target-imports). Package target dependencies enforce them; directories do not.
- **Generated project and shared schemes.** `project.yml` is the reviewed source of truth. XcodeGen produces the ignored project and shared `ResetRadar`, `ResetRadarMac`, and `ResetRadarWatch` schemes; hand edits to generated files are discarded. `Config/TestPlans/` holds one checked-in test plan per scheme. Each plan lists the package test targets for the modules its platform uses plus its own app-level bundle; the iOS plan also includes `ResetRadarUITests`.
- **Fixtures are synthetic.** `Fixtures/` never contains real account, credential, or usage data. `Fixtures/Protocol/` is the only content shared with `relay/`, and sharing is by checked-in data, never executable source ([Relay](relay.md#position)).
- **Machine-local values stay out of the repository.** Team identifier and certificate fingerprint live in an untracked local build-settings file under `Config/Build/`, created from a committed template containing no personal value.
- **Generated and external files stay out of linting.** A checked-in script passes only the maintained Swift roots to swift-format because its configuration file has no path exclusions. SwiftLint configuration excludes `relay/`, `spikes/`, `node_modules/`, `.build/`, `DerivedData/`, and generated sources.
