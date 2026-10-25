# P1-M12: Mac collector app overview

Status: Active

Build `ResetRadarMac` as the collector's composition root: object graph, lifecycle drivers, Keychain-backed secrets, publish loop, and every owner flow in [Mac app](../architecture/mac-app.md) except reset notifications. The [sequence](milestone-12-mac-collector-sequence.md) orders a signed-build tracer first, then the synthetic end-to-end loop, reactive drivers, flows, and owner-run validation.

## Goal

The Mac app runs the configured Codex and Claude Code sources, publishes encrypted snapshots through the relay under `PublicationPolicy`, never shows a Keychain prompt, and lets the owner set up sources and the relay, pair readers, and recover from a Keychain or signing failure. Screens are functional and unstyled; [P1-M13](phase-1.md#p1-m13-mac-ui) polishes them without changing behavior. The complete [contribution-guide gate](../contribution-guide.md#required-validation) passes, and the owner-run Keychain, eight-day re-read, and timer-drift evidence is recorded.

## Why this milestone can proceed

[Phase 1](phase-1.md#order-and-dependencies) lists M6, M7, M10, and M11 as dependencies. Code-complete M10 and M11 adapters on `main` with a passing gate are enough to start (owner-approved 2026-10-25); their open owner-present calibration gates only the final real-data step. M9 is not a start dependency. Until M9 evidence is recorded, M12 is synthetic-only.

## Planning basis

- [Mac app](../architecture/mac-app.md) is binding for drivers, signing and Keychain contract, owner flows, scenes, and tests.
- [Transport](../architecture/transport.md#secret-store), [Storage](../architecture/storage.md), [Application](../architecture/application.md), and [ProviderAdapters](../architecture/provider-adapters.md) supply the ports and use cases M12 wires; M12 adds no policy to them.
- [Mac Keychain research](../research/phase-1/mac-keychain-access.md) and [Platform behavior](../architecture.md#platform-behavior-to-be-proven-on-real-runtimes) define the owner-run evidence.
- M11 delivers the helper installer and configurator that M12 invokes through `ConfigureSources`.

## In scope

- `MacEnvironment` (one object graph per process) and injected protocols for every system touchpoint: signature reader, `SMAppService`, `NWPathMonitor`, `NSWorkspace` wake and session notifications, the process-activity assertion, the Keychain, and the pasteboard.
- Lifecycle drivers: `SingleInstanceLock`, `AppNapGuard`, `WakeMonitor`, `NetworkMonitor`, `LoginItem`, and `SigningCheck` with `SessionSecretCache` and the `secretsUnavailable` retry.
- Runtime drivers: `SourceRuntime`, `PublicationDriver`, and `ManualRequestDriver`.
- The Keychain `SecretStore` with user interaction disabled, a separate Development service and data directory, and the Release build post-action that rejects ad-hoc signing.
- Owner flows with functional unstyled screens in a Settings scene: source setup, relay setup, pairing (QR default, warned Copy fallback), paired devices with Revoke and Destroy Relay, and Keychain recovery.
- The launch-at-login toggle backed by registration status, and the documented install, update, and uninstall paths.
- A `PublishingMode` guard: `synthetic` publishes fixtures through the real pipeline; `live` is refused with a typed error until the M9 pass marker is recorded.
- A reset-notification hook seam at the post-commit point with no driver, no permission prompt, and no `UNUserNotificationCenter` use.
- Owner-run Keychain checks, the eight-day re-read, and 24-hour timer-drift measurement, with only sanitized evidence in the repository.

## Out of scope

- `NotificationDriver` and Mac reset notifications, deferred to [P1-M15](phase-1.md#p1-m15-scheduling).
- Visual design, Account List and Details polish, rings, sidebar styling, menu-bar content design, and alias-editing polish ([P1-M13](phase-1.md#p1-m13-mac-ui)).
- Real provider usage on the relay before M9 passes, changes to relay protocol or crypto, notarization, an auto-updater, and new dependencies.

## Security and privacy invariants

- No Keychain dialog under any path. Every call disables interaction; failure routes to recovery and never to a prompt or silently generated secrets.
- Release builds are signed with the Personal Team identity; an ad-hoc Release build fails before it can touch the Keychain.
- Development builds and tests never touch the installed app's Keychain items or data directory.
- The only network use is outbound HTTPS to the relay, enforced in review.
- `live` publication cannot be reached without the recorded M9 marker; no fallback silently downgrades or upgrades the mode.
- Logs, diagnostics, and evidence contain no secret, token, usage value, or provider identity.

## Implementation decisions

These are newly exposed M12 choices. Implementation is blocked until the owner answers them.

1. **M9 marker form.** Recommend a checked-in constant naming the M9 evidence entry, flipped by the commit that records that evidence, so enabling `live` is reviewable.
2. **Development isolation names.** Recommend the Keychain service and Application Support directory use a `.dev` suffix of the bundle identifier, with a distinct relay secret set.
3. **Settings stub shape.** Recommend one Settings scene with the five architecture sections as plain `Form` views over view models that M13 restyles in place.
4. **Local relay for the synthetic loop.** Recommend the Workers Vitest/Miniflare relay already in `relay/` for integration and the owner's deployed M9 relay only for owner-run drift measurement, with synthetic payloads.

## Completion checklist

- [x] Plan reviewed against the binding architecture; decisions above answered and recorded in [changelog.md](changelog.md).
- [x] Entry: M10 and M11 code-complete on `main`; baseline revision `abaf26e9973432976745251913dcc07da7d94c46`, clean worktree, and sandbox limitations recorded.
- [x] Release post-action rejects ad-hoc signing (tested with a fake signature reader) and a signed Release build exists with sanitized signing evidence recorded.
- [x] Keychain `SecretStore` reads non-interactively; development, test, and installed-app stores are isolated; `interactionRequired` pauses publication and retries.
- [x] `MacEnvironment`, single-instance lock, App Nap guard, session secret cache, wake and network monitors are covered by `ResetRadarMacTests`.
- [x] Synthetic collection through `PublishSnapshot`, `HTTPRelayGateway`, local Miniflare, and authenticated read-back passes end to end; normal launches use live sources and `--synthetic` selects fixtures.
- [x] `ManualRequestDriver` polling, coalescing, publish-before-acknowledge, and sleep/wake behavior are tested.
- [ ] Source setup, relay setup (including interruption recovery), pairing, paired devices, Destroy Relay, and Keychain recovery work through functional screens.
- [ ] Launch at login reflects registration status and errors; uninstall order is documented and tested where automatable.
- [ ] Status-line helper integration with a synthetic Claude Code payload passes.
- [ ] Owner-run: no Keychain dialog across rebuild, login after reboot, ad-hoc build, and locked keychain; eight-day re-read; 24-hour timer drift with the window closed. Sanitized evidence recorded.
- [ ] Roadmap, phase plan, docs index, changelog, README, and affected architecture docs match the implementation.
- [ ] The `test_runner` passes the complete gate from the final reviewable state.
