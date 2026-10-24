# P1-M9: Relay synthetic-data gate sequence

Status: Active

Work order for the [M9 overview](milestone-09-relay-synthetic-gate-overview.md). The agent produces and locally validates the harness; only the owner executes commands that authenticate, deploy, mutate Cloudflare state, inspect the dashboard, or handle secrets. If a remote exercise exposes a defect, the agent may implement and locally validate a fixture-compatible fix without receiving credentials or running the remote command. The [runbook](../research/phase-1/cloudflare-relay-spike-runbook.md) holds the owner commands after Task 2 reconciles it.

## Constraints

- Harness code lives in `relay/scripts/` with Node tests beside it; Worker code under `relay/src/` changes only for a defect the gate exposes, via a fixture-compatible fix and a regression test.
- No new repository dependency or build tool; exact pinned versions only. Synthetic data only. No script reads a secret from an argument, environment variable, file, or log. The owner approved temporary Scriptable solely for the cellular exercise; no other third-party app, hosted page, or product dependency is authorized.
- The agent never authenticates to Cloudflare, reads billing, or handles a token or key.
- No ad hoc `curl`, dashboard edit, or Wrangler substitution may replace a missing reviewed harness command. A failed validation exercise still proceeds to the documented safe teardown.

## Task 1: Entry and baseline

Confirm the completed M8 handoff and frozen protocol-fixture revision, record the starting commit and worktree state, then run the complete gate with `test_runner`. Record the current Node, npm, Wrangler, compatibility-date, and direct dependency pins. The owner inventories account-wide workloads and confirms every required metric has an evidence path with observability disabled. Resolve and document the release-smoke decision. Done when every entry criterion is checked with evidence.

## Task 2: Port and test the harness

Review `spike/cloudflare-relay:relay/scripts/` as historical input, then implement reviewed M8-native commands for deployment validation, finite remote smoke, soak, reproducible faults, release exercise, and destruction. Do not port the spike-only health route or its obsolete JSON bodies, base64url identifiers, envelope construction, configuration name, or dependency ranges. Read exact request and response bytes from `Fixtures/Protocol/` where fixtures exist; use the current canonical encoders for generated sequences and synthetic encrypted results rather than copying wire constants.

Node tests assert, with no network:

- `check:deploy-config` rejects every unapproved top-level key, Preview/Version URLs, observability, a route or custom domain, an extra binding, a non-SQLite object, a missing or extra required secret, a changed entry point or compatibility date, and an unpinned direct dependency;
- `secrets:provision` derives the exact fixture digests from distinct canonical tokens entered through hidden prompts, retains the two-digest standard-input interface for the future Mac path, and sends both together to a bounded mocked process boundary without exposing tokens or digests in arguments, output, an environment value, or a file;
- deployment, default-prior-version rollback, and confirmed isolated-Worker deletion run through bounded wrappers that suppress Wrangler output and expose only fixed redacted summaries; and
- every remote script rejects a non-`workers.dev`, non-HTTPS, credential-bearing, port-bearing, path-bearing, query-bearing, or fragment-bearing origin and any extra or secret-shaped argument;
- redirects, timeouts, invalid media types, malformed or oversized bodies, unexpected status/body pairs, and failing body streams remain bounded and redact tokens, digests, content keys, reader IDs, request IDs, publisher IDs, ciphertext, raw URLs, and Cloudflare identifiers from success and failure output;
- the stateful synthetic reader commits only fully authenticated, newer, compatible snapshots and retains its prior cache through every planned fault; and
- a checked-in workload model generates all additive categories in the architecture budget. Its tests pin the 5.05-second pacing, manual requests more than 60 seconds apart per reader, each daily per-operation count, and the 69,445-request no-retry total, plus the exact counts for the owner-approved 30-minute sample. The old harness's coalesced publication or acknowledgement count is not accepted as the additive worst case.

Run the Node tests first and see the new cases fail, then implement. Inject the M8 Workers Vitest `SELF` fetcher into the same finite-smoke, fault-client, and response-bound logic used remotely so local passing evidence covers the shipped Worker without a special route. The approved Scriptable artifact must self-test the exact public v1 AES-GCM vector before it accepts private inputs, retain no persistent cache or secret, and fail closed if WebCrypto is unavailable. **Checkpoint A:** the complete gate passes. Update the runbook to name only shipped scripts and current paths, document failure-safe teardown, and flip its status from `Deferred` to `Active`.

## Task 3: Preflight and deploy (owner-run)

The owner follows the reconciled runbook in this order:

1. Recheck current official limits and pricing; inventory account-wide workloads; confirm Workers Free, US$0 billing, allowed metrics, disabled logs/traces/Logpush, and no unapproved resource.
2. From the recorded clean worktree, run `npm ci`, the complete local gate, `check:deploy-config`, and `deploy:dry-run` before Wrangler authentication or any remote mutation.
3. Generate six independent synthetic values into the private secure store, authenticate with the pinned Wrangler, and run the reviewed bulk standard-input `secrets:provision` command.
4. Treat secret provisioning as a deployment-capable remote mutation. Immediately inspect versions, bindings, observability, resources, and billing before the reviewed code deployment or promotion step, then inspect them again afterward.

Stop on any runbook condition. Evidence is a redacted pass or fail per item; command output containing a secret or identifier is not evidence and triggers cleanup.

## Task 4: Remote smoke (owner-run)

After the owner confirms the origin is the isolated M9 Worker and may be destructively reset, run the finite remote smoke, then recheck resources, observability, usage, and billing. It must pass all ten operations, fixture-defined static responses and canonical dynamic response shapes, role crossover, preflight without activation, simulated local-save failure without activation, activation after synthetic local commit, idempotent lost-response retry, wall-clock pending expiry, reader cap and revocation, mailbox acceptance/poll/result/acknowledgement/expiry/replay/rate behavior, AES-GCM round trip, strict ordering, conditional reads, response bounds, and repeated destruction before the soak starts. A failure that implies a Worker or harness defect returns to the agent as a redacted reproduction, regression test, and fixture-compatible fix, followed by the complete local gate, an owner-run redeploy, and a fresh smoke.

## Task 5: 30-minute soak and quota boundary (owner-run)

Run `soak:remote` once for 30 minutes, uninterrupted, under `caffeinate`, and reconcile its observed per-operation counts with the tested workload model. Record overall and per-operation p50/p95 client latency, response bytes, Worker CPU, Durable Object duration, rows read and written, and storage. Unexplained account activity or a restart voids the interval. Report the result as a 30-minute sample and use the separately tested 24-hour calculation for daily Free-limit comparison; do not claim 24-hour stability.

Only after the soak completes, date and record the published platform limit response and run the approved safe lower-bound simulation; do not exhaust the daily limit. Add or update the bounded platform-response fixture and Transport regression so the supported form maps to `quotaLimited`, then run the complete gate. If current official documentation does not define enough of the response to recognize it without guessing, record a failed criterion and return to the owner.

## Task 6: Faults, cellular, and release (owner-run)

Run the reviewed fault command for wall-clock pending-reader and request expiry, synthetic Mac awake/asleep/offline refresh, revocation mid-request, source and publication failure, token replacement, destroy and re-pair, rate and quota failure, relay outage, wrong key, altered tag, malformed ciphertext, replay, clock skew, and unsupported version. Its stateful synthetic reader must show its cache sequence before and after each failure and emit only redacted pass/fail output.

For cellular evidence, publish on Mac Wi-Fi, disconnect the Mac, disable iPhone Wi-Fi, and use the approved artifact to fetch, bound, authenticate, decrypt, validate, and commit one synthetic envelope while recording only byte counts and pass/fail. Then use the owner-approved release-smoke order, privately verify which version is active, run the finite smoke at each required point, roll back, and verify coherent storage. Recheck billing and observability after each deployment mutation.

## Task 7: Teardown, evidence, and verdict

Run teardown after a pass, a failed exercise, or an owner stop: authenticate destruction twice, prove active state is empty, remove the two secrets and all deployed versions/Worker resources that Cloudflare permits removing, clear exactly the six synthetic secure-store items and pasteboard, and recheck usage and billing. Record Cloudflare's provider-managed recovery-retention caveat instead of claiming immediate physical erasure.

The agent then writes one dated entry in [spike results](../research/phase-1/spike-results.md) from owner-supplied redacted numbers, checks the overview items against it, and updates [phase-1.md](phase-1.md), the [docs index](../README.md), and the [changelog](changelog.md). Do not edit the archived P1-M2 open-work record. A failure records the condition and owner decision and leaves real relay usage and P1-M14 blocked. Mark M9 `Done` only when every checklist item has direct evidence.

## Review focus

1. Only the non-secret canonical Worker origin may appear on a command line. No token, key, digest, ciphertext, reader/request/publisher/version identifier, or account identifier reaches an argument, file, log, or repository evidence; the raw origin also stays out of logs and evidence.
2. The remote harness imports or generates the current v1 contract; no spike-only endpoint or obsolete branch encoding survives the port.
3. Deployed evidence, not local tests, backs every deployed criterion; the soak is one continuous run whose generated load matches its checked-in accounting.
4. Failure behavior keeps the last valid cache and never triggers an upgrade or charge.
5. Billing, resources, and disabled observability are checked before the first remote mutation, after each deployment-capable mutation, after smoke, after soak, and after teardown.
6. A failed checkpoint still reaches safe teardown, and teardown distinguishes active deletion from provider-managed recovery retention.
7. The harness, runbook, fixtures, relay contract, and approved release mechanism stay in step.
