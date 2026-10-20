# AGENTS.md

Instructions for contributors and AI coding agents. This is the single source of agent instructions; `CLAUDE.md` imports it with `@AGENTS.md`.

## Project

`reset-radar` is a personal Apple-platform app for monitoring Codex and Claude Code allowance usage and reset times. It uses Swift apps for iOS, iPadOS, watchOS, and macOS plus a strict TypeScript Cloudflare relay.

Start with the [documentation index](docs/README.md). Product scope lives in [product-behavior.md](docs/product-behavior.md), setup and validation in the [contribution guide](docs/contribution-guide.md), and binding owner choices in [owner-decisions.md](docs/phase-1/owner-decisions.md).

## Agent workflow

- Work only on a clear task in the active milestone. Read its plan, relevant design docs, and applicable "Undecided" items first.
- Before implementation, add a verifiable checklist item to the milestone overview; check it only when evidence exists.
- Keep code, tests, and affected docs together. Run the complete gate in the [contribution guide](docs/contribution-guide.md).
- Before P1-M3 creates the executable scaffold, defer a structurally inapplicable gate check only by recording the command, blocker, and P1-M3 target. Report every other failure and leave the item unchecked. P1-M3 must pass the complete gate.
- Ask before building on an undecided item, changing dependencies or build tools, deleting user data, or broadly restructuring the repository. Other work within the approved task and milestone may proceed.
- Follow the active phase and milestone order in [roadmap.md](docs/roadmap.md) unless its plan says otherwise.

## Decided — ask before changing

The following sources are binding:

- **Scope and security:** [product behavior](docs/product-behavior.md) and [owner decisions](docs/phase-1/owner-decisions.md). Never copy provider credentials, use private consumer endpoints or API-key mode, invent manual values or reset rules, or send real usage through the relay before its synthetic-data gate passes.
- **Platforms and distribution:** [platform targets](docs/architecture.md#platform-targets) and [personal-use sideloading](docs/research/phase-1/personal-use-sideloading.md). Use the owner's free Apple account and Sideloadly; LiveContainer, App Store, and TestFlight distribution are excluded.
- **Interaction and language:** [UX GUI](docs/ux-gui.md), [information architecture](docs/ux-information-architecture.md), and [UX terms](docs/ux-terms.md). Show provider-reported percentage used, never percentage remaining.
- **System design:** [software architecture](docs/architecture.md) and its module documents. `ResetRadarKit` is a dependency-free local package following Domain ← Application ← adapters/UI ← composition roots; adapters never import each other.
- **Relay:** [relay architecture](docs/architecture/relay.md) and [Cloudflare research](docs/research/phase-1/cloudflare-synchronization.md). Use strict TypeScript, npm, Wrangler, Workers Vitest, a SQLite-backed Durable Object, the included `workers.dev` hostname, ciphertext only, one authoritative Mac, and no APNs architecture or paid relay service.
- **Mac integration:** [Mac architecture](docs/architecture/mac-app.md), [Keychain research](docs/research/phase-1/mac-keychain-access.md), and [ProviderAdapters](docs/architecture/provider-adapters.md). Use one stable Personal Team signature and non-interactive Keychain access; reject ad-hoc builds. Never replace an unsafe or unprovable Claude Code status-line command, and store only the prior setting for restoration.
- **Process and license:** [development process](docs/development-process.md) and Apache-2.0 for all project code. Architecture documents contain no phase or milestone planning.

Use **Codex** and **Claude Code** for the tracked products. Use **Codex app-server** and **Claude Code status line** only for acquisition sources; never shorten Claude Code to Claude or rename Codex to Codex CLI in product-facing text.

## Undecided — ask before inventing

No P1-M1 or P1-M2 owner question remains open. The conditional evidence gates in [owner-decisions.md](docs/phase-1/owner-decisions.md) are validation work, not permission to invent behavior when a test fails or exposes a new product choice.

## Code conventions

- Format with `swift-format`; do not hand-format.
- Keep `swiftlint --strict` free of warnings.
- Target only the OS versions in [Platform targets](docs/architecture.md#platform-targets); use SwiftUI and Swift concurrency over legacy APIs.
- Throw specific errors; do not swallow them with `try?` unless the failure is truly irrelevant.
- New dependencies require approval and an Apache-2.0-compatible license.

## Documentation

- `README.md` is user-facing; `AGENTS.md` holds contributor rules; `docs/` holds plans and design; `docs/archive/` holds inactive docs.
- Use lowercase kebab-case filenames. Start each doc with a title, `Status:` line, and one- to three-sentence summary; add it to [docs/README.md](docs/README.md).
- Update affected docs with code. Update `README.md` for user-visible changes and this file for tooling, commands, or decisions.
- Link instead of copying facts.
- Archive completed or superseded docs according to the [development process](docs/development-process.md). Archived docs are not maintained.

## Token efficiency

- Skip build/dependency output (`.build/`, `DerivedData/`, `.swiftpm/`, `xcuserdata/`), lockfiles, `LICENSE`, and `docs/archive/` unless needed. Search with `git grep` or `rg`.
- Start at `docs/README.md` and read only relevant docs or sections.
- Keep logs short. Run affected tests while iterating and the full gate once at the end.
- Make targeted edits, inspect `git diff --stat` before the full diff, and report concise results rather than raw logs.
