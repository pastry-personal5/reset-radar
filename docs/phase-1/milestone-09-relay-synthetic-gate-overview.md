# P1-M9: Relay synthetic-data gate overview

Status: Active

Prove, on an owner-present Cloudflare Free deployment and with synthetic data only, that the P1-M8 relay satisfies [Relay conformance](../architecture.md#relay-conformance) and the relay criteria in the [Cloudflare validation spike](../research/phase-1/cloudflare-synchronization.md#10-required-validation-spike). The [sequence](milestone-09-relay-synthetic-gate-sequence.md) orders the harness work, owner-run exercises, and evidence. Real usage stays blocked until this gate passes; P1-M14 does not start until it does. The separate Sideloadly installation criterion remains P1-M14 work and is still required before Phase 1 closes.

## Goal

The relay runs on Workers Free at US$0 with no paid subscription or add-on, and a finite remote smoke, a continuous 30-minute capacity and latency sample, fault and release exercises, a cellular read, and teardown all have recorded evidence. Each result names the evidence source and tests the shipped M8 relay rather than the obsolete spike implementation. If any criterion fails, the failed condition and the owner's decision are recorded instead, per the [phase risks](phase-1.md).

## Authority

- The agent builds and locally tests the harness only. The owner runs everything that authenticates to Cloudflare, handles a token or content key, inspects billing, or deploys; see [runbook authority](../research/phase-1/cloudflare-relay-spike-runbook.md#authority-and-stop-conditions). The owner authorization in [owner decisions](owner-decisions.md) covers a synthetic-only deployment on an existing Free account.
- Only generated synthetic ciphertext, IDs, and tokens reach Cloudflare. No provider adapter, credential, or real snapshot is involved.

## Entry criteria

- [x] P1-M8 is `Done`, including atomic reader revalidation after an asynchronous body read, against frozen fixture revision `5d69907210abdf502a855136c6cd00900c0dde80314e7995886f40ce901d5c81`. Evidence: the [M8 implementation checklist](milestone-08-relay-implementation-overview.md#m8-implementation-checklist) and commits `1e68c6c` and `dc3e102`.
- [x] Record the starting commit and worktree state; the M9 baseline gate passes. Evidence: Task 1 began from commit `dc3e102` on branch `plan/p1-m10-codex-adapter`, whose tip matched `main`, with five modified M9 planning documents (`docs/README.md`, `docs/phase-1/changelog.md`, this overview, the M9 sequence, and `docs/research/phase-1/cloudflare-synchronization.md`). On 2026-10-24, the delegated baseline gate passed project generation, Swift format lint, strict SwiftLint with zero violations across 198 files, import checks, 39 Swift package tests plus the Mac smoke test, `npm ci`, 23 Workers Vitest tests, TypeScript checking, the non-deploying Wrangler dry run, `git diff --check`, and the tracked relative Markdown-link check.
- [x] Owner inventories the existing Free account's other workloads and rechecks its plan. Evidence: on 2026-10-24 the owner confirmed Workers Free, no paid add-on, and no existing Worker. Because per-Worker metrics do not exist before the first Worker, the owner approved an immediate post-deploy metric check and teardown if any required metric is unavailable without logs, traces, Logpush, or a paid feature.
- [x] The release-smoke decision below is approved and reconciled with the binding architecture and research before harness implementation. Evidence: 2026-10-24 owner interview and the release rules in the relay architecture and Cloudflare research; the runbook is reconciled in Task 2.

## In scope

- Porting reviewed harness ideas from the unmerged `spike/cloudflare-relay` branch (`77d8001`) onto the M8 layered relay: fail-closed deployment validation, finite remote smoke, a capacity soak, reproducible fault exercises, authenticated destruction, and Node script tests. That branch uses obsolete routes, identifiers, bodies, envelope bytes, configuration, and dependency ranges; reuse behavior by review, not files by merge.
- Hardening `secrets:provision` so both required digests reach Wrangler together through standard input, no partially provisioned version is deliberately served, and the configuration declares exactly `WRITE_TOKEN_DIGEST` and `ADMIN_TOKEN_DIGEST` as required secrets.
- Harness safety rules from the runbook: tokens and the content key only through hidden prompts, only a canonical HTTPS `workers.dev` origin on the command line, no redirects, bounded responses, redacted output.
- An in-memory synthetic Mac and reader client that proves last-valid-cache retention, request/result matching, and failure classification without requiring the future composition roots.
- Owner-run deployment, finite remote smoke, 30-minute soak, quota-boundary, fault, recovery, approved promotion and rollback exercises, iPhone cellular read, and teardown.
- Reconciling the [runbook](../research/phase-1/cloudflare-relay-spike-runbook.md) with the shipped scripts, then recording results in [spike results](../research/phase-1/spike-results.md).

## Out of scope

- Any real usage, provider adapter, or composition-root wiring; changing the v1 wire contract; a new dependency or build tool; a paid Cloudflare service, custom domain, or log stream.
- The Sideloadly re-sign check; it belongs to P1-M14, which owns the first installable iOS build. M9 does not close that separate Phase 1 criterion.
- Merging `spike/cloudflare-relay`.

## Owner decisions

Approved by the owner on 2026-10-23:

1. **M8 hardening.** Finish the reader-revalidation item (test, verify, commit) before M9 Task 1; it is not deferred.
2. **Cellular read client.** A synthetic-only script on the iPhone that fetches and decrypts a synthetic envelope and shows only pass or fail. On 2026-10-24 the owner approved temporary use of Scriptable, including an isolated WebView for WebCrypto, followed by deletion of the script and app. This is gate tooling, not product architecture.
3. **Script tests.** Node's built-in `node --test` is acceptable; it adds no dependency or build tool.
4. **Account and quota.** Use the existing Free account after inventorying its other workloads. Do not exhaust the daily limit; record Cloudflare's published limit response plus a safe lower-bound simulation, which must map to `quotaLimited`.

## Release-smoke decision

- [x] **Release smoke.** Retain `preview_urls: false` and the exact binding set. On the isolated synthetic-only M9 Worker, upload the candidate, promote it to 100%, verify the active deployment privately, run the finite smoke immediately, and roll back on failure and again as the planned rollback exercise. Evidence: owner approval on 2026-10-24. Cloudflare documents that [Version URLs are not generated for Workers that implement Durable Objects](https://developers.cloudflare.com/workers/versions-and-deployments/version-urls/#limitations), and its [version-override verification](https://developers.cloudflare.com/workers/versions-and-deployments/version-overrides/#verify-that-version-overrides-were-applied) would require forbidden observability or a new metadata binding.

## Evidence model

| Evidence | What it can prove | What it cannot replace |
|---|---|---|
| Node and Workers Vitest tests | Harness safety, exact fixtures, schedule arithmetic, synthetic-client state, and the real M8 Worker locally | Deployed Cloudflare behavior or billing |
| Redacted remote smoke and fault summaries | Deployed protocol, recovery, and fail-closed behavior | Dashboard quota, metric, or billing evidence |
| Owner-observed dashboard totals | Plan, resource, observability, account-wide quota, and aggregate runtime metrics | Client-side decryption or cache behavior |
| Continuous soak summary | Intended request mix and client p50/p95 latency over the measured interval | A restarted interval or unmeasured account activity |
| iPhone cellular result | Fetch, bounded transfer, authenticated decrypt, and cache commit with the Mac disconnected | Sideloadly, production iOS composition, or background execution |

The 2026-10-20 remote checkpoint in [spike results](../research/phase-1/spike-results.md) is historical input only. It exposed Preview URL defaults and harness gaps, but it predates M8 and satisfies no M9 checklist item.

## Completion checklist

- [x] The M9 plan is reconciled with the binding relay contract, validation-spike criteria, current M8 handoff, and repository validation process; review findings and resulting plan changes are recorded in the changelog. Evidence: the 2026-10-24 changelog entry and this plan's release decision, evidence model, failure cleanup, and workload-accounting requirements.
- [x] Entry criteria hold with recorded commit and a passing baseline gate. Evidence: the checked entry items above and the 2026-10-24 owner interview.
- [x] The four previously approved owner decisions are recorded in the [changelog](changelog.md). Evidence: 2026-10-23 entry.
- [x] The release-smoke decision is approved and recorded in the changelog and binding documents. Evidence: the 2026-10-24 owner interview, `owner-decisions.md`, the relay architecture, and Cloudflare research.
- [x] Harness scripts pass `node --test`, exercise their client logic against the real Worker in Workers Vitest, and pass the complete [contribution-guide gate](../contribution-guide.md#required-validation). No script accepts a secret as an argument, environment value, or file; output is redacted and bounded. Evidence: 21 Node tests, the M9 finite-smoke case among 26 Workers Vitest tests, and the 2026-10-24 complete gates recorded below.
- [x] `check:deploy-config` fail-closes on any unapproved top-level key, Preview/Version URL, observability, route or custom domain, extra binding, non-SQLite object, missing or extra required secret declaration, changed entry point or compatibility date, or changed/unpinned direct dependency. Wrangler itself validates the two declared required secrets before deployment. Evidence: `deployment.node-test.mjs` mutation cases and a passing `npm --prefix relay run check:deploy-config`.
- [x] `secrets:provision` derives the two authority digests from distinct canonical tokens read through hidden prompts, clears the pasteboard on prompt failure, sends both in one bounded standard-input operation, and never writes or exposes them through arguments, output, or environment values. Its digest-on-standard-input interface remains available for the future Mac setup path. Any provisioning command that creates or deploys a version is treated as a remote deployment step. Evidence: fixture digest derivation, mocked `wrangler secret bulk` process-boundary and output-bound tests, and the active runbook's post-mutation inspection requirement.
- [x] `deploy:remote`, `release:rollback`, and `teardown:worker` suppress and bound Wrangler output, expose no raw origin or Cloudflare identifier, and emit only fixed redacted success or failure summaries. Evidence: three process-boundary Node tests pin the reviewed arguments, environment, deletion confirmation, timeouts, output bound, and success and failure behavior; 21 Node tests and the complete gate passed before the next owner-run deployment.
- [x] Snapshot-read response hardening instructs the public Workers boundary to preserve the exact strong ETag by forbidding response transformation as well as caching. Evidence: Worker tests pin `Cache-Control: no-store, no-transform` on snapshot success, conditional, and error paths while leaving other no-store responses unchanged; a Node regression distinguishes header transformation from stored-body mutation; 26 Workers Vitest tests, 22 Node tests, and the complete gate passed before the next owner-run deployment. Actual public preservation remains part of the unchecked remote-smoke criterion.
- [x] The 30-minute soak gates each reader's next manual request on at least 60 seconds since that reader's prior accepted response, dispatches the three readers' requests before beginning bounded follow-up reads, and distinguishes a relay `requestRateLimited` response from a non-relay `429`. Evidence: three Node tests pin a 60,001 ms response-relative gate, request-before-follow-up ordering, relay/platform classification, and the unchanged 1,422-request accounting; 26 Workers Vitest tests, 25 Node tests, and the complete gate passed before another owner-run sample.
- [x] The approved cellular tooling has a deterministic Mac preparation command and a non-persistent Scriptable artifact. It self-tests exact AES-GCM with the public protocol vector before prompting, bounds and authenticates the cellular response, commits only after full validation, activates the pending reader only after that in-memory commit, clears the pasteboard, and exposes only pass/fail and byte counts. Evidence: `cellular-artifact.node-test.mjs` and the owner decision above.
- [x] Runbook matches the shipped scripts and the approved owner answers. Evidence: `npm --prefix relay run`, the active M8-native runbook, passing link check, and the 2026-10-24 owner interview.
- [x] Preflight proves the required metrics are observable. Preflight and every post-mutation billing check show Workers Free, no paid add-on, logs, traces, and Logpush off, and only the approved Worker, versions, secrets, and SQLite Durable Object. Evidence: the owner-present 2026-10-24 [strong-ETag smoke stop](../research/phase-1/spike-results.md#p1-m9-strong-etag-smoke-stop-and-teardown--2026-10-24) passed the plan, billing, resource, observability, active-deployment, request, CPU, Durable Object duration, row, and storage checks before the smoke failure and completed teardown afterward.
- [x] Remote smoke passes all ten operations, authority separation, and destruction with redacted output. Reader evidence includes preflight without activation, simulated local-save failure without an activation request, activation only after synthetic local commit, idempotent lost-response retry, wall-clock pending expiry, revocation, listing, and the three-reader cap; mailbox evidence includes bounded acceptance, non-consuming poll, matching encrypted result, acknowledgement, expiry, replay, rate limit, and revocation. Evidence: the owner-present 2026-10-24 [soak-rate stop](../research/phase-1/spike-results.md#p1-m9-soak-rate-stop-and-teardown--2026-10-24) reported the exact ten-operation pass after the public strong-ETag repair, followed by clean teardown after the later soak failure.
- [x] The soak's checked-in workload accounting matches every additive worst-case category in [Relay capacity](../architecture.md#relay-capacity), including 4,320 accepted manual requests, 43,200 bounded follow-up reads, 5,790 ordinary reads, 5,760 polls, 2,880 ordinary publications, 288 heartbeat publications, 2,880 separately counted manual-result publications, 4,320 acknowledgements, and seven setup requests. Tests pin the 69,445-request no-retry total and the 1,422-request 30-minute executable sample before deployment. The daily figure deliberately adds each architecture maximum; the sample has 60 results and acknowledgements because of the Mac's 30-second handling cadence. Evidence: `harness-core.node-test.mjs`.
- [ ] The 30-minute soak completes once without a restart; its planned and observed per-operation counts reconcile, and requests, Worker CPU, Durable Object duration, rows read and written, storage, response bytes, and per-operation and overall p50/p95 latency stay within the current Free limits. The result is explicitly a sample, not proof of 24-hour stability; daily capacity is supported by the separate checked-in workload calculation.
- [x] The safe quota-boundary simulation fails closed; the dated published platform limit form is recorded, represented by a regression fixture, and maps to `quotaLimited` without an upgrade or charge. Evidence: the 2026-10-24 [current-limit and local harness checkpoint](../research/phase-1/spike-results.md#p1-m9-current-limit-and-local-harness-checkpoint--2026-10-24), `Fixtures/Platform/cloudflare-free-limit.json`, and `structuredCloudflareFreeLimitMapsNarrowlyToQuotaLimited`, including altered-field and 4xx/5xx cases.
- [ ] Reproducible fault cases prove wall-clock pending-reader and refresh-request expiry, sleeping or offline synthetic Mac, revocation mid-request, source and publication failure, token replacement, and destroy-and-re-pair recovery.
- [ ] The stateful synthetic reader proves malformed ciphertext, wrong key, altered tag, replay, clock skew, incompatible version, rate limiting, quota failure, and relay outage preserve the last valid cache.
- [ ] Ciphertext published over Wi-Fi is fetched with bounded byte counts, authenticated, decrypted, and committed by the approved iPhone cellular artifact with Wi-Fi off and the Mac disconnected.
- [ ] A compatible candidate follows the approved release-smoke order and is promoted and rolled back; private owner evidence proves which version handled the smoke without placing its identifier in repository evidence, and storage remains coherent.
- [ ] Teardown runs after success or failure. Authenticated active state is empty; secrets, deployments, Worker, and removable Durable Object resources are gone; the documented provider-managed recovery-retention caveat remains explicit; billing stays US$0.
- [ ] A dated spike-results entry contains aggregate values and pass/fail evidence but no token, key, digest, ciphertext, relay or Cloudflare identifier, raw URL, or account identifier. The gate result is recorded in [phase-1.md](phase-1.md), the [docs index](../README.md), and the [changelog](changelog.md); the archived P1-M2 record is not edited.

## Checkpoints

- **A: Harness.** Entry criteria, owner answers, and the reviewed local harness with passing gate and pinned workload accounting.
- **B: Deploy and smoke.** Preflight, secrets, reviewed deployment, remote smoke, and billing recheck.
- **C: Soak and faults.** 30-minute measurement, then quota, fault, recovery, cellular, and release exercises.
- **D: Teardown and verdict.** Teardown, evidence entry, and status updates. A failure at any checkpoint stops later validation exercises and goes to the owner, but it never skips safe teardown.

## Risks

- **Stale harness.** The spike branch predates the M8 layout and uses `^` ranges. Pin and review it; do not assume it works.
- **Release exposure.** Durable Object Workers cannot use Version URLs. The owner-approved promote-then-smoke flow briefly exposes the synthetic-only candidate at 100%, so private active-version verification, immediate smoke, and rollback on failure are mandatory.
- **Under-driving the budget.** The old soak coalesces manual-result and scheduled publications while its prose counts them additively. A passing run is meaningful only after checked-in arithmetic makes the generated load match the architecture budget.
- **Shared quotas.** Other account workloads or a restarted soak invalidate the capacity calculation; a restart is not a continuous result.
- **Metric gaps.** The run cannot pass if a required Free-quota dimension is unavailable after the initial deployment with observability disabled; tear down immediately rather than enabling a forbidden feature.
- **Short sample.** The owner replaced the 24-hour measurement with a 30-minute sample. It exercises the intended cadence but cannot directly prove 24-hour stability or a UTC reset; report that limitation and retain the daily workload calculation.
- **Secret leakage.** The soak handles six secrets. Hidden prompts, clipboard clearing, and redacted output are binding.
- **Cellular tooling.** Scriptable's WebView WebCrypto availability is proven only when the embedded public-vector self-test passes on the owner's iPhone. Failure stops the exercise; no other app, hosted page, or dependency is authorized.
- **Verdict ambiguity.** Passing local tests is not passing the gate; only deployed evidence counts.

## Plan validation

On 2026-10-24, the `test_runner` ran the complete [contribution-guide gate](../contribution-guide.md#required-validation) on the reviewed plan. Project generation, Swift format lint, strict SwiftLint (zero violations across 198 files), import checks, the Mac scheme (39 Swift package tests plus the Mac smoke test), relay dependency installation, 23 Workers Vitest tests, TypeScript checking, and the non-deploying Wrangler dry run all passed. `git diff --check` and a relative Markdown-link check also passed. The initial Apple-side commands encountered only sandbox cache and CoreSimulator restrictions; approved host-cache retries passed. No Cloudflare activity, secret handling, provider access, or real usage occurred.

## Harness validation

On 2026-10-24, the delegated complete gate passed on the reviewed M9 harness worktree, including the approved cellular tooling and post-failure correctness fixes. A first relay run exposed a nondeterministic test assumption at the concurrent reader-cap boundary; the test now follows the actual three winners, and five consecutive complete relay-suite runs passed with 26 Workers Vitest and 18 Node harness tests each. The final complete gate passed project generation, Swift format lint, strict SwiftLint with zero violations across 198 files, import checks, 85 Swift package tests plus the Mac smoke test, dependency installation, TypeScript checking, the non-deploying Wrangler dry run, fail-closed deployment validation, `git diff --check`, and 61 tracked relative Markdown-link checks. Approved host-cache retries were required for Apple tooling; no repository change resulted from dependency installation or validation. No Cloudflare authentication, deployment, secret handling, provider access, or real usage occurred.

After the owner-run deployment-output stop on 2026-10-24, a delegated repair gate passed with the three Wrangler mutation paths behind bounded output-suppressing wrappers. The gate passed project generation, Swift format lint, strict SwiftLint with zero violations across 198 files, import checks, the Mac scheme, dependency installation, 26 Workers Vitest tests, 21 Node harness tests, TypeScript checking, the non-deploying Wrangler dry run, deployment-configuration validation, and `git diff --check`. The Apple-side commands required only the previously approved host-cache retry. No Cloudflare authentication, deployment, secret handling, or remote mutation occurred during repair validation.

After the owner-run strong-ETag smoke stop on 2026-10-24, a delegated repair gate passed with snapshot-read responses sending `Cache-Control: no-store, no-transform` and the smoke distinguishing ETag-header transformation from stored-body mutation. The gate passed project generation, Swift format lint, strict SwiftLint with zero violations across 198 files, import checks, 85 Swift package tests plus the Mac smoke test, dependency installation, 26 Workers Vitest tests, 22 Node harness tests, TypeScript checking, the non-deploying Wrangler dry run, deployment-configuration validation, and `git diff --check`. No Cloudflare authentication, deployment, secret handling, or remote mutation occurred during repair validation.

After the owner-run soak-rate stop on 2026-10-24, a delegated repair gate passed with response-relative per-reader cadence gates, concurrent manual-request dispatch before follow-up reads, and redacted relay-versus-platform `429` classification. The gate passed project generation, Swift format lint, strict SwiftLint with zero violations across 198 files, import checks, 85 Swift package tests plus the Mac smoke test, dependency installation, 26 Workers Vitest tests, 25 Node harness tests, TypeScript checking, the non-deploying Wrangler dry run, deployment-configuration validation, and `git diff --check`. No Cloudflare authentication, deployment, secret handling, or remote mutation occurred during repair validation.
