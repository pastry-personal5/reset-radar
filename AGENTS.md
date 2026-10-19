# AGENTS.md

Instructions for contributors and AI coding agents. This is the single source of agent instructions; `CLAUDE.md` imports it with `@AGENTS.md`.

## Project

`reset-radar`: An Apple-platform app that monitors AI-service usage and reset times across MacBook, iPhone, and Apple Watch.

Stack: Swift, iOS 26+ and watchOS 26+ apps with a macOS collector, swift-format, SwiftLint and XCTest.

See [README.md](README.md) for the overview and [docs/product-behavior.md](docs/product-behavior.md) for product scope. Setup and contribution rules are in [docs/contribution-guide.md](docs/contribution-guide.md); other docs are indexed at [docs/README.md](docs/README.md).

## Agent workflow

- Work only on a clear task in the active milestone. Read its plans, relevant design docs, and applicable "Undecided" items first.
- Before implementation, add a verifiable completion checklist to the milestone overview. Check items only when evidence exists.
- Keep implementation, tests, and affected docs together. A milestone is done only when its checklist is complete and the gate passes: `swift-format lint --strict --recursive .`, `swiftlint --strict`, and `xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17'`. Before the executable scaffold exists, a check that is inapplicable solely because its planned files or targets do not exist may be explicitly deferred to the scaffolding milestone; record the command, blocker, and target milestone in the checklist. All applicable checks must pass, and the scaffolding milestone must pass the complete gate. Other command failures leave the item unchecked and must be reported.
- Ask before building on an undecided item, changing dependencies or build tools, deleting user data, or broadly restructuring the repository. Other work within the approved task and milestone may proceed.
- Follow the active phase and milestone order in `docs/roadmap.md` unless the phase plan says otherwise. Create the roadmap when planning the first phase.

## Decided — ask before changing

- **Technical stack:** Swift, iOS 26+ and watchOS 26+ apps with a macOS collector, swift-format, SwiftLint and XCTest.
- **Product scope:** [product-behavior.md](docs/product-behavior.md).
- **Interaction model:** [ux-gui.md](docs/ux-gui.md). Component vocabulary is in [ux-terms.md](docs/ux-terms.md) and the layout containment model in [ux-information-architecture.md](docs/ux-information-architecture.md).
- **License:** Apache-2.0 for all project code.
- **Process:** numbered phases contain numbered milestones; milestone numbering restarts per phase. IDs use `P1-M2`. See [docs/development-process.md](docs/development-process.md).
- **Claude paid weekly reset anchor:** a fixed day and time assigned to the account, unchanged by session or subscription start, and visible in Settings > Usage. Source: [P1-M1 research](docs/research/phase-1/initial-research-on-feasibility.md), section 2.
- **Distribution:** personal use only, signed with the owner's free Apple account and sideloaded. Sideloadly is the supported iPhone and embedded-watch install/refresh path; LiveContainer is excluded while Reset Radar includes WidgetKit extensions. Physical-device validation must prove the paired Apple Watch workflow. See [personal-use-sideloading.md](docs/research/phase-1/personal-use-sideloading.md).
- **Usage tracking:** percentages are automatic. A Mac collector actively reads Codex app-server for Codex and imports Claude Code's last-response status-line snapshots for Claude, then sends credential-free observations to paired Apple devices. Manual entry is not the primary source; private consumer endpoints and copied credentials remain excluded. Source/freshness are visible and percentages are never inferred from elapsed time. See [usage-tracking.md](docs/research/phase-1/usage-tracking.md), [automatic-usage-acquisition.md](docs/research/phase-1/automatic-usage-acquisition.md), and the [pinned upstream audit](docs/research/phase-1/upstream-automatic-usage-sources.md).
- **Cloudflare relay hostname:** use the included `workers.dev` hostname while the US$0 requirement applies. Do not require or purchase a custom domain for Reset Radar. Source: [Cloudflare synchronization research](docs/research/phase-1/cloudflare-synchronization.md), section 2.
- **P1-M1 owner decisions:** [owner-decisions.md](docs/phase-1/owner-decisions.md) resolves Q2, Q3, Q5 to Q8, Q10, and Q11 and is binding on P1-M2. In summary: exclude consumer credentials and API-key mode; start manual ChatGPT setup blank; keep a neutral Reset Radar identity; include Live Activities for eligible short windows and an Apple Watch app; bind recurring rules to their selected time zone while presenting times in the OS's local zone; exclude threshold alerts, history, and forecasts; require the Mac collector in the first usable version; use one authoritative Mac; accept foreground plus opportunistic background refresh; and use locally development-signed Mac distribution.
- **Cloudflare relay boundary:** conditionally approved as the primary cellular transport with ciphertext only, one authoritative Mac, and no APNs architecture. Approval becomes final only if the required synthetic-data spike passes; no real usage data may reach the relay before then. See [owner-decisions.md](docs/phase-1/owner-decisions.md) and [cloudflare-synchronization.md](docs/research/phase-1/cloudflare-synchronization.md).
- **Product vocabulary:** use **Codex** and **Claude Code** as the canonical tracked-product names. Use **Codex app-server** and **Claude Code status line** only when identifying the acquisition source. Do not shorten Claude Code to Claude or rename Codex to Codex CLI in product-facing taxonomy.
- **Percentage orientation:** present provider-reported percentage used, from 0% toward 100%. Do not invert it into percentage remaining.
- **Architecture-document isolation:** architecture documents describe the system without phase or milestone IDs, names, status, sequencing, or other planning references. Planning documents may link to architecture documents.

## Undecided — ask before inventing

No P1-M1 owner question remains open. The conditional evidence gates in [owner-decisions.md](docs/phase-1/owner-decisions.md) are validation work, not permission to invent behavior when a test fails or exposes a new product choice.

## Environment

- macOS with Xcode 26 or newer (iOS 26 SDK and simulator).
- swiftlint, for example `brew install swiftlint`.
- swift-format, bundled with the Swift toolchain.

## Commands

```sh
xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17'  # run the tests
swift-format format --in-place --recursive .                                             # format
swift-format lint --strict --recursive .                                                 # check formatting
swiftlint --strict                                                                       # lint
```

## Code conventions

- Format with `swift-format`; do not hand-format.
- Keep `swiftlint --strict` free of warnings.
- Target iOS 26 and watchOS 26 or newer; use SwiftUI and Swift concurrency over legacy APIs.
- Throw specific errors; do not swallow them with `try?` unless the failure is truly irrelevant.

## Dependencies

Approved dependencies must have licenses compatible with Apache-2.0.

## Documentation

- `README.md` is user-facing; `AGENTS.md` holds contributor rules; `docs/` holds plans and design; `docs/archive/` holds inactive docs.
- Use lowercase kebab-case filenames. Start each doc with a title, `Status:` line, and one- to three-sentence summary.
- Add every doc to [docs/README.md](docs/README.md). Follow [docs/development-process.md](docs/development-process.md) for phase and milestone plans.
- Update affected docs with code. Update `README.md` for user-visible changes and this file for tooling, commands, or decisions.
- Link instead of copying facts.
- Archive completed or superseded docs: update status, `git mv` them under `docs/archive/` (completed phase directories go under `docs/archive/phases/`), and fix links. Archived docs are not maintained.

## Token efficiency

- Skip build/dependency output (`.build/`, `DerivedData/`, `.swiftpm/`, `xcuserdata/`), lockfiles, `LICENSE`, and `docs/archive/` unless needed. Search with `git grep` or `rg`.
- Start at `docs/README.md` and read only relevant docs or sections.
- Keep logs short with quiet flags or filtering. Run affected tests while iterating and the full gate once at the end.
- Consult only the needed dependency source/module for API details.
- Make targeted edits; inspect `git diff --stat` before a full diff.
- Reply with concise summaries, not raw logs.
