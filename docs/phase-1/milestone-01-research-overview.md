# P1-M1: Initial research overview

Status: Done

Establish whether Reset Radar can track allowance usage and reset times across iOS 26+, watchOS 26+, and a Mac collector, and on what terms. The findings feed the product scope and the software architecture.

## Goal

Produce a sourced feasibility study that ends in a clear verdict: which reset-tracking approaches work, which do not, and what the first version should and should not do. P1-M2 must be able to decide without guessing.

## Deliverable

`docs/research/phase-1/initial-research-on-feasibility.md`, with `Status: Draft` until the owner approves it and `Status: Active` afterward. Required sections, in order:

1. **Verdict and recommendation:** half a page. Feasible, feasible with constraints, or not feasible, and the recommended first-version approach.
2. **Service matrix:** one row per service, with the columns under "Service matrix" below.
3. **Reset-time acquisition options:** each way to learn a reset time (official API, usage endpoint, response headers, in-app or web usage page, user-entered, calendar or email signals), with pros, cons, legal and terms-of-service risk, and fragility.
4. **iOS capability analysis:** what each mechanism can and cannot do for "tell me when a limit resets", with limits quoted from Apple documentation.
5. **Privacy and security:** credentials the app would need, safe storage, and data that must never leave the device.
6. **Prior art:** existing trackers and what they teach.
7. **Candidate scope and non-goals:** proposed first-version features and explicit exclusions.
8. **Open questions and risks:** each with an owner decision needed, a proposed default, and the P1-M2 decision it blocks.

## Research questions

### Services and limit models

The owner chose two services: Claude and ChatGPT. Other services are out of scope for this milestone. Cover every consumer plan tier of each that has limits, and note API-key usage separately. For each service, record:

- Plan tiers that have limits and what the limits are measured in (messages, tokens, requests, compute time).
- Reset type: rolling window (for example "N hours after first use"), fixed calendar reset (daily, weekly, monthly, anchored to the billing date), or both.
- Per-model or per-feature sub-limits that reset on their own clocks.
- Whether the limits and reset behavior are officially documented, and when that documentation was last updated.

### Service matrix

| Column | Meaning |
|---|---|
| Service and plan | For example "Claude Pro". |
| Limit model | Rolling, fixed, or both, with the unit. |
| Reset time visible to the user | Where in the service's own UI the reset appears, if anywhere. |
| Machine-readable source | Official API, usage endpoint, headers, or none. |
| Auth needed | OAuth, API key, session cookie, or none. |
| Terms-of-service stance | Allowed, forbidden, or unclear, with a quote and link. |
| Confidence | High (documented), medium (observed), low (inferred). |

### Reset-time acquisition

Rank the options by reliability, terms-of-service risk, and effort. A user-entered or rule-based computed reset (for example "five hours after the user taps 'I started a session'") is the baseline every other option has to beat. Flag any option that needs a user's session cookie or password. Such options need an explicit owner decision and must not be adopted by default.

### iOS capabilities

For each mechanism, state what works on iOS 26+ without a backend, what needs one, and the platform limits:

- Local notifications: scheduling limits, time zone and daylight-saving behavior, Focus and notification summary effects.
- Background refresh and background tasks: how reliably the system runs them, and why polling is not a dependable design.
- Widgets and Live Activities: update budgets, lifetime limits, and what a countdown can do without background execution.
- App Intents, Shortcuts and Siri: "when does my limit reset" as a voice or automation action.
- Additional surfaces: Apple Watch, Lock Screen and StandBy.
- Whether any push-based design would require a server, and what that does to cost, privacy and the App Store review.

### Privacy, security and distribution

- Credential and token storage options (Keychain, access groups) and what the app would hold.
- Whether any design sends usage data off the device.
- App Store review risks: apps that automate or scrape third-party services, and how the guidelines apply. Cite the current guideline numbers.
- Whether trademarks of the services can appear in the app name, icon or listing.

### Prior art

Survey at least five existing trackers, menu-bar tools, widgets or community scripts for AI usage limits. Note their reset-time source, platform, price, and the main complaints in their reviews or issues.

## Method and source rules

- Prefer primary sources: vendor documentation, vendor terms, Apple documentation and the App Store Review Guidelines. Use community sources only to illustrate observed behavior, and label them as such.
- Fetch current documentation rather than answering from memory. Limits and plans change often, so record the date every source was checked.
- Mark each claim `documented`, `observed`, or `inferred`. Anything not `documented` must carry a confidence note.
- Do not log in to real accounts, scrape a service, or probe undocumented endpoints without explicit owner approval. If observing real behavior would help, list it as a proposed experiment instead.
- Time-box the research to the checklist below. If a question cannot be answered from public sources, list it under open questions rather than extending the milestone.

## In scope

- Everything listed under "Research questions".
- A recommended first-version scope and non-goals.
- Constraints worth noting for [ux-gui.md](../ux-gui.md) and [product-behavior.md](../product-behavior.md).

## Out of scope

- Choosing the app structure or writing code (P1-M2 and P1-M3).
- Visual design and UX decisions.
- Building prototypes, other than a throwaway spike the owner approves in the changelog.

## Completion checklist

- [x] The deliverable exists with all eight sections and left `Status: Draft` only after owner approval. Evidence: `docs/research/phase-1/initial-research-on-feasibility.md` is `Status: Active` following the 2026-10-19 review.
- [x] The service matrix covers every agreed consumer plan and API usage separately, with a source and check date on each row. Evidence: section 2 covers Claude Free, Pro, Max 5x, Max 20x and API; ChatGPT Free, Go, Plus, Pro 100/200/500 and API.
- [x] Every substantive claim is labeled `documented`, `observed` or `inferred`, and every `inferred` claim has a confidence note. Evidence: the evidence-label convention at the top of the deliverable and labels throughout sections 1 to 8.
- [x] At least three reset-time acquisition options are compared, and the baseline user-entered option is included. Evidence: section 3, options 1 to 7.
- [x] Each iOS mechanism has its relevant platform constraint quoted from Apple documentation, with links; where Apple does not publish a current number, the gap is explicit. Evidence: section 4 covers notifications, background tasks, widgets, Live Activities, App Intents, optional surfaces and push.
- [x] Credential storage and data-leaving-the-device are addressed, and App Store review risks cite guideline numbers. Evidence: section 5 covers the data inventory, Keychain accessibility, vendor terms, and guidelines 2.5.1, 2.5.4, 2.5.16, 4.1(c), 4.5.4, 5.1.1, 5.2.1 and 5.2.2.
- [x] At least five prior-art tools are surveyed with source, platform, price and issue/review signal. Evidence: section 6 covers seven tools.
- [x] A separate GitHub prior-art study records the search method and inventories relevant repositories with platform, reset-time source, credential model, license, maintenance signal, and public issue evidence. Evidence: `docs/research/phase-1/github-prior-art.md`, covering 16 direct and eight adjacent repositories.
- [x] Personal-use sideloading research records the owner's distribution decision, compares LiveContainer and Sideloadly against the required app capabilities, and documents free-account constraints. Evidence: `docs/research/phase-1/personal-use-sideloading.md` selects Sideloadly and records the P1-M3 device checks.
- [x] The first-version Apple Watch decision is recorded with a credential-free iPhone-mediated data boundary and explicit Personal Team signing, paired-device installation, synchronization, and seven-day refresh validation. Evidence: `docs/phase-1/owner-decisions.md`, `docs/product-behavior.md`, and `docs/research/phase-1/personal-use-sideloading.md`.
- [x] Usage-tracking research defines percentage semantics, compares acquisition methods for consumer and API plans, studies prior-art behavior, and identifies the decisions that block P1-M2. Evidence: `docs/research/phase-1/usage-tracking.md`.
- [x] Automatic usage-acquisition research audits recent GitHub implementations at code level, selects provider-specific sources, and records desktop-to-mobile security requirements. Evidence: `docs/research/phase-1/automatic-usage-acquisition.md`.
- [x] Upstream-source research pins automatic percentages and reset times to current `openai/codex` and `anthropics/claude-code` revisions, distinguishes queryable from last-response data, and records schema, refresh, and absence semantics. Evidence: `docs/research/phase-1/upstream-automatic-usage-sources.md`.
- [x] Mobile-network synchronization research compares cost, security, free-account signing compatibility, offline delivery, and operational burden; recommends a cost-savvy path; and consolidates duplicated transport requirements in the research set. Evidence: `docs/research/phase-1/mobile-network-synchronization.md` is canonical; related studies link to it instead of repeating the transport contract.
- [x] A Cloudflare-primary synchronization study selects the appropriate Workers storage primitive, defines the pairing/authentication/encryption and replay model, covers privacy, operations, limits, deletion, and failure behavior, and leaves implementation-checkable spike criteria. Evidence: `docs/research/phase-1/cloudflare-synchronization.md` selects a SQLite-backed Durable Object, and the owner conditionally approved it subject to the spike in [owner-decisions.md](owner-decisions.md).
- [x] The Cloudflare study proves a $0 personal-use configuration from current first-party pricing, identifies account-wide quotas and every optional feature that can introduce charges, and defines fail-closed cost guardrails. Evidence: section 2 of `docs/research/phase-1/cloudflare-synchronization.md` audits the Free-only contract and hidden-fee paths; `docs/research/phase-1/mobile-network-synchronization.md` reflects the contract in the canonical comparison.
- [x] The owner's acceptance of `workers.dev` is recorded as the hostname decision, the custom-domain question is removed from active research, and the broader relay-validation decision remains explicit. Evidence: `AGENTS.md`, the Cloudflare and mobile synchronization studies, and the phase changelog.
- [x] The research set clearly separates supported Claude Code/Codex coding allowances from unsupported general Claude/ChatGPT web and mobile usage, and inventories remaining documentation-only decisions versus live validation work. Evidence: section 9 of the feasibility study audits the remaining work; product behavior, usage tracking, and automatic acquisition now use the same coding-allowance boundary.
- [x] The verdict states one recommended first-version approach and a fallback. Evidence: section 1.
- [x] Each research question names the P1-M2 decision it blocks; the owner has resolved Q2, Q3, Q5 to Q8, Q10, and Q11 in [owner-decisions.md](owner-decisions.md), and `AGENTS.md` records them under "Decided." Former Q1 and Q9 were resolved by automatic usage acquisition; former Q4 was resolved by multi-window tracking; the earlier Claude-anchor question was resolved by current first-party documentation.
- [x] The deliverable is added to [docs/README.md](../README.md).
- [x] [product-behavior.md](../product-behavior.md) reflects the owner-approved first-version scope and links to the decision record.
- [x] The owner has reviewed and approved the research results, and the review is recorded in [changelog.md](changelog.md). Evidence: owner approval on 2026-10-19.
- [x] Every applicable gate check passes, and structurally inapplicable checks are deferred under the pre-scaffolding exception. Evidence: on 2026-10-19, `swift-format lint --strict --recursive .` passed; `swiftlint --strict` reported no lintable files; and `xcodebuild test -scheme ResetRadar -destination 'platform=iOS Simulator,name=iPhone 17'` reported that the repository contains no Xcode project, workspace, or package. P1-M3 must create the Swift files, project, scheme, and targets and pass the complete gate.
