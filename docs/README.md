# Documentation index

Status: Active

This index lists the design and process docs, one line each. Read only the doc you need. The rules for writing docs are in [AGENTS.md](../AGENTS.md) under "Documentation".

| Doc | What it covers |
|-----|----------------|
| [development-process.md](development-process.md) | Phases, milestones, IDs (`P1-M2`), definition of done, where plans live, and doc status values. |
| [contribution-guide.md](contribution-guide.md) | Local setup, required validation, commit message style, and pull request conventions. |
| [product-behavior.md](product-behavior.md) | Product scope: what the app does and what it deliberately does not do. |
| [ux-terms.md](ux-terms.md) | Canonical UI terms for products, usage concepts, states, actions, and components, with code-facing identifiers. |
| [ux-information-architecture.md](ux-information-architecture.md) | The Standard Layout: how the app's components contain one another. |
| [ux-gui.md](ux-gui.md) | Current interface and owner-approved GUI behavior, with planned behavior kept separate. |
| [architecture.md](architecture.md) | System architecture: principles, trust boundaries, clean-architecture layers and module map, platform targets, sync and refresh model, pairing and loss, failure behavior, verification, and build contract. Active. |
| [architecture/domain.md](architecture/domain.md) | Domain module: identities, records, wire conventions, Home slot resolution, and availability policies. Active. |
| [architecture/application.md](architecture/application.md) | Application module: use cases, ports, refresh/publication/complication policies, and read models. Active. |
| [architecture/storage.md](architecture/storage.md) | Storage adapter: versioned atomic files, cross-process locks, preferences, migration, and diagnostics. Active. |
| [architecture/transport.md](architecture/transport.md) | Transport adapter: key material, Keychain secret store, envelope encryption, account scope, pairing codec, and relay client. Active. |
| [architecture/scheduling.md](architecture/scheduling.md) | Scheduling adapter: reset notifications and Reset Live Activity mechanics. Active. |
| [architecture/watch-sync.md](architecture/watch-sync.md) | WatchSync adapter: WatchConnectivity channels, payloads, and refresh requests. Active. |
| [architecture/provider-adapters.md](architecture/provider-adapters.md) | ProviderAdapters: Codex app-server and Claude Code status-line sources, setup, and the status-line helper. Active. |
| [architecture/ui.md](architecture/ui.md) | UI adapter: screen models, shared components, formatting, and accessibility. Active. |
| [architecture/relay.md](architecture/relay.md) | Cloudflare relay: internal layering, canonical protocol, state, operations, and tests. Active. |
| [architecture/ios-app.md](architecture/ios-app.md) | iOS composition root: iPhone/iPad app, widget extension, App Intent, refresh drivers, and process model. Active. |
| [architecture/mac-app.md](architecture/mac-app.md) | Mac composition root: collector runtime, App Nap and wake handling, signing and Keychain, owner flows, and lifecycle. Active. |
| [architecture/watch-app.md](architecture/watch-app.md) | Watch composition root: payload commit, refresh requests, background delivery, and complication. Active. |
| [roadmap.md](roadmap.md) | All phases with status; the sole authority for the active phase. |
| [phase-1/phase-1.md](phase-1/phase-1.md) | Phase 1 goal, exit criteria, and milestones. |
| [phase-1/milestone-01-research-overview.md](phase-1/milestone-01-research-overview.md) | P1-M1 scope and completion checklist. |
| [phase-1/milestone-02-software-architecture-overview.md](phase-1/milestone-02-software-architecture-overview.md) | P1-M2 scope, deliverables, validation work, and completion checklist. |
| [phase-1/owner-decisions.md](phase-1/owner-decisions.md) | Owner-approved P1-M1 product, security, scheduling, synchronization, and distribution decisions that constrain P1-M2. |
| [research/phase-1/initial-research-on-feasibility.md](research/phase-1/initial-research-on-feasibility.md) | P1-M1 feasibility study: service limits, reset-time sources, iOS capabilities, prior art, and owner-approved scope. Active. |
| [research/phase-1/github-prior-art.md](research/phase-1/github-prior-art.md) | P1-M1 GitHub survey: open-source reset trackers, data sources, credentials, licenses, maintenance signals, and issue patterns. Active. |
| [research/phase-1/personal-use-sideloading.md](research/phase-1/personal-use-sideloading.md) | P1-M1 distribution research: free Apple account constraints and the Sideloadly decision over LiveContainer. Active. |
| [research/phase-1/usage-tracking.md](research/phase-1/usage-tracking.md) | P1-M1 usage research: percentage semantics, acquisition options, prior art, freshness, and data-model consequences. Active. |
| [research/phase-1/automatic-usage-acquisition.md](research/phase-1/automatic-usage-acquisition.md) | P1-M1 automatic acquisition research: recent GitHub implementations, selected Codex/Claude sources, and secure desktop-to-mobile boundaries. Active. |
| [research/phase-1/official-mobile-usage-access.md](research/phase-1/official-mobile-usage-access.md) | P1-M2 review of optional vendor-supported device login and independent iPhone/iPad usage access; records the missing API and authorization gates. Draft. |
| [research/phase-1/upstream-automatic-usage-sources.md](research/phase-1/upstream-automatic-usage-sources.md) | P1-M1 upstream audit: pinned Codex app-server and Claude Code percentage/reset schemas, updates, freshness, and compatibility rules. Active. |
| [research/phase-1/mobile-network-synchronization.md](research/phase-1/mobile-network-synchronization.md) | P1-M1 synchronization research: cost-savvy Mac-to-iPhone delivery over cellular, including iCloud Drive, CloudKit, Tailscale, and a minimal relay. Active. |
| [research/phase-1/cloudflare-synchronization.md](research/phase-1/cloudflare-synchronization.md) | P1-M1 Cloudflare-primary synchronization research: accepted `workers.dev` hostname, US$0 contract, Durable Object selection, encrypted relay protocol, pairing, threats, privacy, operations, limits, and spike criteria. Active. |
| [research/phase-1/mac-keychain-access.md](research/phase-1/mac-keychain-access.md) | P1-M2 Mac Keychain research: why ad-hoc signing prompts, storage options, the owner-selected stable-signing design, and its validation spike. Active. |
| [research/phase-1/mac-keychain-validation-spike-runbook.md](research/phase-1/mac-keychain-validation-spike-runbook.md) | P1-M2 owner-run, synthetic-only harness and evidence procedure for validating unattended Mac Keychain access. Active. |
| [research/phase-1/source-calibration-spike-runbook.md](research/phase-1/source-calibration-spike-runbook.md) | P1-M2 owner-run, privacy-safe command-line procedure for calibrating the installed signed-in Codex and Claude Code sources. Active. |
| [research/phase-1/spike-results.md](research/phase-1/spike-results.md) | P1-M2 spike evidence: relay, platform lifecycle, and source calibration measurements. Draft. |
| [phase-1/changelog.md](phase-1/changelog.md) | Phase 1 decisions and plan changes. |
