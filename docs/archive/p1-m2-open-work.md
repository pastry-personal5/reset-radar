# P1-M2 open work

Status: Archived

The unfinished validation work extracted from P1-M2 when that milestone closed on 2026-10-22. It is a record, not a plan: nothing here is scheduled or tracked as a milestone, and the file is not maintained. Each item belongs to the module named below and is implemented and verified there, as part of that module's feature work.

## How the work is carried

- The owning module implements the feature the item exercises and adds the verification as ordinary tests. The module's design in `docs/architecture/` stays the source of truth for the behavior.
- Items that need a physical device, a signed-in provider, or elapsed time stay owner-run. Their runbooks remain in `docs/research/` and are linked below.
- Real usage data still must not reach the relay until the relay's synthetic-data gate passes.
- If a result contradicts an accepted decision, stop and return it to the owner instead of adjusting behavior; the original rule for a rejected current-data window stays in force.

## Open work by module

| Open work | Owning modules | Condition to satisfy |
|---|---|---|
| Cloudflare synthetic-data spike | [Relay](../architecture/relay.md), [Transport](../architecture/transport.md) | Every criterion in the [Cloudflare research](../research/cloudflare-synchronization.md) and “Relay conformance” in the [architecture](../architecture.md#relay-conformance) passes, including three-reader add/revoke/cap, manual-refresh request and acknowledgement, latency, and Free-tier capacity, or the failed condition and the owner's decision are recorded. Synthetic data only. Prior measurements: [spike results](../research/spike-results.md). |
| WatchConnectivity on a paired physical watch | [WatchSync](../architecture/watch-sync.md), [Watch app](../architecture/watch-app.md), [iOS app](../architecture/ios-app.md) | Application-context and complication user-info delivery; Watch-initiated refresh waking the iPhone app and replying before the message times out; the complication reading the Watch App Group; offline cache, complication reload, and stale display; Forget Mac while the Watch is offline with durable pending erasure, a queued receipt after reconnection, and eventual complication reload. |
| Seven-day Sideloadly install and refresh | [iOS app](../architecture/ios-app.md), [Storage](../architecture/storage.md), [Transport](../architecture/transport.md) | iPhone and iPad results after the re-sign, including whether the app and widget still read their Keychain items, per the [sideloading research](../research/personal-use-sideloading.md). |
| Source calibration for Codex and Claude Code | [ProviderAdapters](../architecture/provider-adapters.md) | Per provider: installed version, field shape, timing, and the confirmed or rejected current-data window; Codex default-bucket identity and legitimate frame size against the proposed bound; Claude Code new-response signal. No raw responses or identifiers. Procedure: [source-calibration runbook](../research/source-calibration-spike-runbook.md). |
| Calibration profile selection | [ProviderAdapters](../architecture/provider-adapters.md) | Every owner-designated `codex-profile` profile is selected explicitly, isolated in its own app-server process and report, verified, and never inferred from an ambient `CODEX_HOME`; no profile name is retained in project evidence. The synthetic tests passed on 2026-10-22; the installed-schema preflight and live observations remain owner-run. |
| Widget, Live Activity, and shared-state behavior | [Scheduling](../architecture/scheduling.md), [Storage](../architecture/storage.md), [Transport](../architecture/transport.md), [iOS app](../architecture/ios-app.md) | WidgetKit timeline degradation at threshold crossings; Live Activity start, update, stale, and end including `staleDate` and the eight-hour limit; App Group sharing and widgets on iPhone and iPad; widget-reload ingest under the cross-process lock, including suspension or background-task expiry mid-commit; widget-only reset-notification replacement, cancellation, and expiry fallback; Keychain access after first unlock from the app and the widget extension. |
| Mac Keychain validation | [Transport](../architecture/transport.md#secret-store), [Mac app](../architecture/mac-app.md) | Per the [Mac Keychain research](../research/mac-keychain-access.md#5-validation-spike): no dialog across a rebuild, at login launch, or eight days after signing; an ad-hoc build fails with an error instead of a dialog; a prelaunch lock blocks a fresh read; a later lock leaves the running cache usable until process exit. A failure returns the storage decision to the owner. Done so far: stable rebuild, post-reboot login launch, ad-hoc rejection, prelaunch lock, and running-process cache. Open: the no-dialog observation for fresh locked processes (inconclusive) and the eight-day read. Procedure: [validation runbook](../research/mac-keychain-validation-spike-runbook.md). |
| Refresh timing | [Mac app](../architecture/mac-app.md), [iOS app](../architecture/ios-app.md), [Application](../architecture/application.md#policies) | Mac timer drift with the main window closed over 24 hours, and iOS background-task run intervals over 24 hours, on the reference devices. |
| Runtime security review | [Transport](../architecture/transport.md), [Relay](../architecture/relay.md), [ProviderAdapters](../architecture/provider-adapters.md), [Storage](../architecture/storage.md) | A table walking every row of “Failure behavior” and each trust boundary in the [architecture](../architecture.md) and finding no path that copies provider credentials, exposes plaintext to Cloudflare, fabricates usage, or silently upgrades a free service. The design-level review is in the [spike results](../research/spike-results.md#static-architecture-review--2026-10-20); each module contributes its runtime rows as it implements, and the table is closed when all owning modules have. |

## Closed without work

- **Pre-scaffolding gate deferrals.** P1-M2 recorded the gate commands that could not run before a project existed. P1-M3 passed the complete gate with no deferrals, so nothing remains.

## Timing constraints

Some observations take elapsed time, so start them early in the owning module's work: relay and timer measurements run 24 hours, and the Mac Keychain re-read runs eight days after signing. The relay measurement is followed by the offline-publish and manual-refresh cases (awake, asleep, offline, and after reader revocation) and a check that billing stays US$0.
