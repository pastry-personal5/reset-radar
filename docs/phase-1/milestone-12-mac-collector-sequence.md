# P1-M12: Mac collector app sequencing

Status: Done

Work order and acceptance tests for the [M12 overview](milestone-12-mac-collector-overview.md). Binding behavior remains in [Mac app](../architecture/mac-app.md); this sequence names seams, test-first order, checkpoints, and the owner-run boundary.

## Constraints

- Production code stays in `ResetRadarMac/`, tests in `ResetRadarMacTests/`. The Mac root imports Domain, Application, Storage, Transport, ProviderAdapters, and UI; Scheduling stays out until M15. Drivers carry no policy.
- Every system touchpoint is an injected protocol; tests use fakes and the in-memory `SecretStore`. The real Keychain, App Nap, and login item are proven only by owner-run checks.
- Swift 6 strict concurrency and Swift Testing; no new package, service, or build tool.
- Never log or assert on secrets, tokens, usage values, or provider identity. Fixture sentinels make leakage checks deterministic.
- Run focused `ResetRadarMacTests` while iterating and the complete [gate](../contribution-guide.md#required-validation) at the baseline, each checkpoint, and close-out, delegated to `test_runner`.

## Commit strategy

One conventional commit per checkpoint, each eligible only after its complete gate passes: signing and secrets, runtime loop, drivers and flows, close-out.

## Task 0: Decisions, branch, and baseline

Answer the overview decisions and record them in the changelog. Record branch, starting commit, and `git status --short`. Confirm M10 and M11 are code-complete on `main` and the gate passes. Add the overview checklist before code. Set M12 to `Active` only when implementation begins.

## Task 1: Signing and Keychain tracer (Checkpoint A)

1. Test first: a `SigningCheck` with an injected signature reader reports ad-hoc, missing-team, and changed-team outcomes.
2. Add the Release build post-action that inspects the signed app and embedded helper and fails without a team identifier; Development configurations skip it.
3. Implement the Keychain `SecretStore` with interaction disabled, separate Development service, and mapping of `interactionRequired` to `secretsUnavailable`.
4. Owner-run: first signed Release build with the Personal Team identity. Record the team identifier and date; this starts the eight-day re-read clock.

## Task 2: Environment and lifecycle

Test first, then implement `MacEnvironment`, `SingleInstanceLock` (second instance activates the first and exits; Debug uses separate state), `AppNapGuard`, `SessionSecretCache` (read once per launch, cleared on quit, Destroy Relay, or setup replacement), and recovery routing from `SigningCheck`.

## Task 3: Synthetic end-to-end loop (Checkpoint B)

1. `PublishingMode` first: normal launches compose configured live sources, while `--synthetic`
   never reads a real source and uses fixtures through the real pipeline. The mode is explicit;
   no M9 marker gates live publication.
2. `SourceRuntime` routes a synthetic source's updates into `CollectUsage` and forwards `wake`, `foreground`, and `manual` reasons.
3. `PublicationDriver` arms one timer for the instant `PublicationPolicy` allows and handles `transition` changes.
4. Integration against the local Workers Vitest relay: collect, encrypt, publish, read back.

## Task 4: Reactive drivers

`WakeMonitor` (immediate refresh and publish on wake), `NetworkMonitor` (publish on path restored after failure), `ManualRequestDriver` (15-second poll while ready and readers exist; coalesce; publish before acknowledging; stop on no readers, setup, destruction, or `secretsUnavailable`; resume on wake), and the reset-notification hook seam.

## Task 5: Owner flows and Settings (Checkpoint C)

Test view models first, then add plain Settings sections: Sources (Codex discoveries with no fixed account-count limit, Claude Code guided setup through `ConfigureSources` with preview and confirmed removal, unsafe commands untouched), Relay & Pairing (digests, `SetUpRelay` wipe-and-bind with interruption recovery, QR pairing with five-second activation polling and expiry revocation, warned Copy fallback with conditional pasteboard cleanup), paired devices (Revoke, Destroy Relay with paused publication on failure), and Keychain recovery copy for both causes.

## Task 6: Login item and lifecycle docs

`LoginItem` over `SMAppService.mainApp` shows real registration status and errors. Write install, update, and uninstall steps from [Mac app](../architecture/mac-app.md#installation-and-lifecycle) and recovery notes for the six listed failures. Add the helper integration test with a synthetic Claude Code payload.

## Task 7: Owner-run validation and close-out

1. Unless the owner explicitly accepts the validation risk, prove no Keychain dialog across a
   rebuild, login after reboot, an ad-hoc build, and a keychain locked before launch; prove that a
   later lock preserves the cached-secret behavior.
2. Unless waived, complete the eight-day re-read after the Task 1 signing date and a 24-hour
   timer-drift run with the window closed using synthetic payloads.
3. Record either sanitized evidence or the owner-approved waiver in
   `docs/research/spike-results.md` and the changelog; update README, docs index,
   roadmap, and phase plan; run the complete gate. Real-data end-to-end does not wait for M9.

## Checkpoints

| Checkpoint | After | Evidence |
|---|---|---|
| A | Task 1 | Gate passes; signed build and team identifier recorded |
| B | Task 3 | Gate passes; synthetic loop reaches the local relay |
| C | Task 5 | Gate passes; flows covered by view-model tests |
| Close | Task 7 | Owner-run evidence recorded; final gate passes |
