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
| [mac-installation-and-recovery.md](mac-installation-and-recovery.md) | Owner installation, Gatekeeper, manual update, ordered uninstall, helper restoration, and six recovery paths for the Mac collector. Active. |
| [user-guide-for-sideloading.md](user-guide-for-sideloading.md) | Build the signed IPA and install Reset Radar on an iPhone or iPad with Sideloadly Normal Install, including privacy, trust, renewal, and troubleshooting guidance. Active. |
| [architecture/watch-app.md](architecture/watch-app.md) | Watch composition root: payload commit, refresh requests, background delivery, and complication. Active. |
| [architecture/repository-layout.md](architecture/repository-layout.md) | Planned repository directory structure: Xcode project, package, targets, shared configuration, fixtures, and relay. Active. |
| [roadmap.md](roadmap.md) | All phases with status; the sole authority for the active phase. |
| [phase-1/phase-1.md](phase-1/phase-1.md) | Phase 1 goal, exit criteria, and milestones. |
| [phase-1/milestone-01-research-overview.md](phase-1/milestone-01-research-overview.md) | P1-M1 scope and completion checklist. |
| [phase-1/milestone-02-software-architecture-overview.md](phase-1/milestone-02-software-architecture-overview.md) | P1-M2 scope, deliverables, and completion checklist. Done. |
| [archive/p1-m2-open-work.md](archive/p1-m2-open-work.md) | Archived: P1-M2's unfinished validation work, assigned to the owning modules. Not maintained. |
| [phase-1/milestone-03-scaffolding-overview.md](phase-1/milestone-03-scaffolding-overview.md) | P1-M3 scope, entry criteria, open questions, and completion checklist. |
| [phase-1/milestone-03-scaffolding-sequence.md](phase-1/milestone-03-scaffolding-sequence.md) | P1-M3 toolchain prerequisites, identifiers, work sequence, and risks. |
| [phase-1/milestone-04-domain-model-overview.md](phase-1/milestone-04-domain-model-overview.md) | P1-M4 scope, entry criteria, open questions, and completion checklist. |
| [phase-1/milestone-04-domain-model-sequence.md](phase-1/milestone-04-domain-model-sequence.md) | P1-M4 task order, interfaces, tests, and review focus. |
| [phase-1/milestone-05-application-use-cases-overview.md](phase-1/milestone-05-application-use-cases-overview.md) | P1-M5 scope, spec corrections, open questions, and completion checklist. |
| [phase-1/milestone-05-application-use-cases-sequence.md](phase-1/milestone-05-application-use-cases-sequence.md) | P1-M5 task order, port and outcome interfaces, tests, and review focus. |
| [phase-1/milestone-06-storage-overview.md](phase-1/milestone-06-storage-overview.md) | P1-M6 scope, owner decisions, and completion evidence. Done. |
| [phase-1/milestone-06-storage-sequence.md](phase-1/milestone-06-storage-sequence.md) | P1-M6 task order, store and core interfaces, tests, and review focus. Done. |
| [phase-1/milestone-07-transport-overview.md](phase-1/milestone-07-transport-overview.md) | P1-M7 scope, owner decisions, checkpoints, and completion checklist. Done. |
| [phase-1/milestone-07-transport-sequence.md](phase-1/milestone-07-transport-sequence.md) | P1-M7 protocol handoff, implementation order, tests, and review focus. Done. |
| [protocol fixtures](../Fixtures/Protocol/README.md) | Synthetic golden envelope, pairing, HTTP operation, and error bytes shared by Swift and relay tests. |
| [platform response fixtures](../Fixtures/Platform/README.md) | Synthetic bounded hosting-platform responses used by Transport regression tests. |
| [phase-1/milestone-08-relay-implementation-overview.md](phase-1/milestone-08-relay-implementation-overview.md) | P1-M8 relay scope, fixture dependency, checkpoints, and completion checklist. Done. |
| [phase-1/milestone-08-relay-implementation-sequence.md](phase-1/milestone-08-relay-implementation-sequence.md) | P1-M8 Worker and Durable Object task order, tests, and M9 handoff. Done. |
| [phase-1/milestone-09-relay-synthetic-gate-overview.md](phase-1/milestone-09-relay-synthetic-gate-overview.md) | P1-M9 synthetic-data gate scope, owner decisions, evidence model, checkpoints, and completion checklist. Active. |
| [phase-1/milestone-09-relay-synthetic-gate-sequence.md](phase-1/milestone-09-relay-synthetic-gate-sequence.md) | P1-M9 harness adaptation, owner-run deployment, soak, fault, and teardown order. Active. |
| [phase-1/milestone-10-codex-adapter-overview.md](phase-1/milestone-10-codex-adapter-overview.md) | P1-M10 two-account Codex adapter scope, owner decisions, privacy boundary, checkpoints, and completion checklist. Active. |
| [phase-1/milestone-10-codex-adapter-sequence.md](phase-1/milestone-10-codex-adapter-sequence.md) | P1-M10 account contracts, profile configuration, bounded JSON-RPC, normalization, scheduling, tests, and source-calibration order. Active. |
| [phase-1/milestone-11-claude-code-adapter-overview.md](phase-1/milestone-11-claude-code-adapter-overview.md) | P1-M11 Claude Code adapter scope, owner decisions, privacy boundary, checkpoints, and completion checklist. Done. |
| [phase-1/milestone-11-claude-code-adapter-sequence.md](phase-1/milestone-11-claude-code-adapter-sequence.md) | P1-M11 bounded helper, safe status-line composition, session merging, tests, and source-calibration order. Done. |
| [phase-1/milestone-12-mac-collector-overview.md](phase-1/milestone-12-mac-collector-overview.md) | P1-M12 Mac collector scope, recorded decisions, invariants, and completion checklist. Done. |
| [phase-1/milestone-12-mac-collector-sequence.md](phase-1/milestone-12-mac-collector-sequence.md) | P1-M12 signing tracer, synthetic loop, drivers, owner flows, and close-out order. Done. |
| [phase-1/milestone-13-mac-ui-overview.md](phase-1/milestone-13-mac-ui-overview.md) | P1-M13 Mac UI scope and completion checklist. Done. |
| [phase-1/milestone-13-mac-ui-architecture.md](phase-1/milestone-13-mac-ui-architecture.md) | P1-M13 Mac UI implementation sequence. Done. |
| [phase-1/milestone-14-ios-core-app-overview.md](phase-1/milestone-14-ios-core-app-overview.md) | P1-M14 iPhone/iPad reader scope, entry criteria, handoffs, and completion checklist. Active; physical iPhone QR pairing is verified, with remaining owner-run device evidence pending. |
| [phase-1/milestone-14-ios-core-app-sequence.md](phase-1/milestone-14-ios-core-app-sequence.md) | P1-M14 composition, pairing, refresh, UI, test, and device-validation order. Active. |
| [phase-1/milestone-15-scheduling-overview.md](phase-1/milestone-15-scheduling-overview.md) | P1-M15 scheduling scope, M14 handoff, review findings, and completion checklist. Active. |
| [phase-1/milestone-15-scheduling-sequence.md](phase-1/milestone-15-scheduling-sequence.md) | P1-M15 Scheduling, Mac notifications, background refresh, widgets, ActivityKit, and device-validation order. Active. |
| [phase-1/milestone-15-scheduling-validation.md](phase-1/milestone-15-scheduling-validation.md) | P1-M15 automated review evidence, known validation limits, and pending owner-run device checks. Active. |
| [phase-1/milestone-16-watch-overview.md](phase-1/milestone-16-watch-overview.md) | P1-M16 Watch scope, handoff review, physical-device evidence, and completion checklist. Active. |
| [phase-1/milestone-16-watch-sequence.md](phase-1/milestone-16-watch-sequence.md) | P1-M16 WatchSync, iPhone and Watch wiring, complication, signing, and validation order. Active. |
| [phase-1/milestone-16-security-review.md](phase-1/milestone-16-security-review.md) | P1-M16 row-by-row failure and trust-boundary evidence table. Active. |
| [phase-1/milestone-16-validation.md](phase-1/milestone-16-validation.md) | P1-M16 integrated handoff, automated evidence, and remaining paired-device proof. Active. |
| [phase-1/milestone-17-gui-polish-overview.md](phase-1/milestone-17-gui-polish-overview.md) | P1-M17 experience, pairing, synchronization, and presentation scope. Active. |
| [phase-1/milestone-17-gui-polish-sequence.md](phase-1/milestone-17-gui-polish-sequence.md) | P1-M17 implementation and validation order. Active. |
| [research/cloudflare-relay-spike-runbook.md](research/cloudflare-relay-spike-runbook.md) | Active owner-run P1-M9 deployment, smoke, 30-minute sample, fault, release, and teardown procedure. |
| [phase-1/owner-decisions.md](phase-1/owner-decisions.md) | Owner-approved P1-M1 product, security, scheduling, synchronization, and distribution decisions that constrain P1-M2. |
| [research/initial-research-on-feasibility.md](research/initial-research-on-feasibility.md) | P1-M1 feasibility study: service limits, reset-time sources, iOS capabilities, prior art, and owner-approved scope. Active. |
| [research/github-prior-art.md](research/github-prior-art.md) | P1-M1 GitHub survey: open-source reset trackers, data sources, credentials, licenses, maintenance signals, and issue patterns. Active. |
| [research/personal-use-sideloading.md](research/personal-use-sideloading.md) | P1-M1 distribution research: free Apple account constraints and the Sideloadly decision over LiveContainer. Active. |
| [research/usage-tracking.md](research/usage-tracking.md) | P1-M1 usage research: percentage semantics, acquisition options, prior art, freshness, and data-model consequences. Active. |
| [research/automatic-usage-acquisition.md](research/automatic-usage-acquisition.md) | P1-M1 automatic acquisition research: recent GitHub implementations, selected Codex/Claude sources, and secure desktop-to-mobile boundaries. Active. |
| [research/official-mobile-usage-access.md](research/official-mobile-usage-access.md) | P1-M2 review of optional vendor-supported device login and independent iPhone/iPad usage access; records the missing API and authorization gates. Draft. |
| [research/upstream-automatic-usage-sources.md](research/upstream-automatic-usage-sources.md) | P1-M1 upstream audit: pinned Codex app-server and Claude Code percentage/reset schemas, updates, freshness, and compatibility rules. Active. |
| [research/claude-code-mod-usage-acquisition.md](research/claude-code-mod-usage-acquisition.md) | Follow-up research on whether a Claude Code Mod can export account allowance usage, and how it compares with the selected status-line source. Active. |
| [research/claude-code-mod-research-by-claude-code.md](research/claude-code-mod-research-by-claude-code.md) | Independent Claude Code Mod check with a signed-in same-session probe: identical rate-limit data to the status line, write-path and trust gaps, candidate designs, open questions, and the combined conclusion. Active. |
| [research/mobile-network-synchronization.md](research/mobile-network-synchronization.md) | P1-M1 synchronization research: cost-savvy Mac-to-iPhone delivery over cellular, including iCloud Drive, CloudKit, Tailscale, and a minimal relay. Active. |
| [research/cloudflare-synchronization.md](research/cloudflare-synchronization.md) | P1-M1 Cloudflare-primary synchronization research: accepted `workers.dev` hostname, US$0 contract, Durable Object selection, encrypted relay protocol, pairing, threats, privacy, operations, limits, and spike criteria. Active. |
| [research/mac-keychain-access.md](research/mac-keychain-access.md) | P1-M2 Mac Keychain research: why ad-hoc signing prompts, storage options, the owner-selected stable-signing design, and its validation spike. Active. |
| [research/mac-keychain-validation-spike-runbook.md](research/mac-keychain-validation-spike-runbook.md) | P1-M2 owner-run, synthetic-only harness and evidence procedure for validating unattended Mac Keychain access. Active. |
| [research/source-calibration-spike-runbook.md](research/source-calibration-spike-runbook.md) | P1-M2 owner-run, privacy-safe command-line procedure for calibrating the installed signed-in Codex and Claude Code sources. Active. |
| [research/m15-scheduling-device-runbook.md](research/m15-scheduling-device-runbook.md) | P1-M15 owner-run synthetic-device procedure for notifications, widgets, Live Activities, background refresh, and re-sign evidence. Active. |
| [research/m16-watch-device-runbook.md](research/m16-watch-device-runbook.md) | P1-M16 owner-run synthetic paired-Watch installation, delivery, App Group, complication, and erase procedure. Active. |
| [research/spike-results.md](research/spike-results.md) | P1-M2 spike evidence: relay, platform lifecycle, and source calibration measurements. Draft. |
| [phase-1/changelog.md](phase-1/changelog.md) | Phase 1 decisions and plan changes. |
