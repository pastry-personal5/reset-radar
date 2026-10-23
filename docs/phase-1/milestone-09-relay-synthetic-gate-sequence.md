# P1-M9: Relay synthetic-data gate sequence

Status: Planned

Work order for the [M9 overview](milestone-09-relay-synthetic-gate-overview.md). Agent tasks 1 and 2 produce the harness; tasks 3 to 7 are owner-run with the agent assisting on documents only. The [runbook](../research/phase-1/cloudflare-relay-spike-runbook.md) holds the commands.

## Constraints

- Harness code lives in `relay/scripts/` with Node tests beside it; Worker code under `relay/src/` changes only for a defect the gate exposes, via a fixture-compatible fix and a regression test.
- No new dependency or build tool; exact pinned versions only. Synthetic data only. No script reads a secret from an argument, environment variable, file, or log.
- The agent never authenticates to Cloudflare, reads billing, or handles a token or key.

## Task 1: Entry and baseline

Resolve the M8 review-hardening item (commit the pending change with its concurrency test, or record the owner's deferral). Record the starting commit and worktree state, then run the complete gate with `test_runner`. The owner's four decisions are already recorded. Done when the entry criteria are checked with evidence.

## Task 2: Port and test the harness

Review `spike/cloudflare-relay:relay/scripts/` against the M8 relay and port `validate-spike-config.mjs` (as `check:deploy-config`), `smoke-remote.mjs`, `soak-remote.mjs`, and `destroy-remote.mjs`, adding npm scripts and extending `test` to run `node --test scripts/*.node-test.mjs`. Drop `provision-spike.mjs` in favor of `secrets:provision`. Read request and response bytes from `Fixtures/Protocol/` where the harness checks bodies; do not copy them into script constants.

Node tests assert, with no network: `check:deploy-config` fails on each forbidden setting (Preview URLs, observability, route, custom domain, extra binding, non-SQLite object, unpinned dependency); every remote script rejects a non-`workers.dev`, non-HTTPS, or path-bearing origin and any secret-shaped argument; redirect and oversized-response handling; output redaction of tokens, reader IDs, request IDs, and ciphertext; and the soak schedule arithmetic (17,280 five-second slots, per-reader manual rate above 60 seconds). Run these tests first and see them fail, then port. Also add a local run of the harness client logic against the real Worker through Workers Vitest so it is proven against M8 before any deployment. **Checkpoint A:** the complete gate passes. Update the runbook to match the shipped scripts, remove the stale branch instructions, and flip its status from Deferred.

## Task 3: Preflight and deploy (owner-run)

Follow runbook sections 1 and 3 to 4: dashboard preflight, `npm ci`, Wrangler login, secret generation into the private store, `secrets:provision`, `deploy:dry-run`, reviewed deploy, then billing and dashboard recheck. Stop on any runbook stop condition. Evidence is a redacted pass or fail per item.

## Task 4: Remote smoke (owner-run)

Run `smoke:remote` against the deployed origin, then recheck billing. It must pass every protocol case before the soak starts. A failure that implies a Worker defect returns to the agent as a regression test plus fix, then a redeploy and a fresh smoke.

## Task 5: 24-hour soak and quota boundary (owner-run)

Run `soak:remote` once, uninterrupted, under `caffeinate`, and record dashboard totals by UTC day. Only after it completes, record Cloudflare's published limit response and run the approved safe lower-bound simulation, showing the `quotaLimited` mapping; do not exhaust the daily limit. A restart voids the interval.

## Task 6: Faults, cellular, and release (owner-run)

Run runbook section 6: wall-clock pending-reader and request expiry, Mac awake, asleep, and offline refresh, revocation mid-request, source and publication failure, token replacement, destroy and re-pair, wrong key, malformed ciphertext, replay, clock skew, and unsupported version with last-valid-cache retention. Then the cellular read with the approved synthetic Shortcut or script, and a version-URL smoke, promotion, and rollback with a storage coherence check.

## Task 7: Teardown, evidence, and verdict

Run runbook section 7 and clear the secure store. The agent then writes one dated entry in [spike results](../research/phase-1/spike-results.md) from owner-supplied redacted numbers, checks the overview items against it, updates [phase-1.md](phase-1.md) (M9 status, spike row, P1-M2 open work row), the [docs index](../README.md), and the [changelog](changelog.md). A failure records the condition and owner decision and leaves P1-M14 blocked. Mark M9 `Done` only when every checklist item has evidence.

## Review focus

1. No path lets a secret, ciphertext, ID, or account identifier reach a command line, file, log, or evidence entry.
2. Deployed evidence, not local tests, backs every checked item; the soak is one continuous run.
3. Failure behavior keeps the last valid cache and never triggers an upgrade or charge.
4. Billing is checked before deploy, after smoke, after soak, and after teardown.
5. The harness and runbook stay in step with the checked-in fixtures and relay contract.
