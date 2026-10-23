# P1-M9: Relay synthetic-data gate overview

Status: Planned

Prove, on an owner-present Cloudflare Free deployment and with synthetic data only, that the P1-M8 relay satisfies every criterion in [Relay conformance](../architecture.md#relay-conformance) and the [Cloudflare validation spike](../research/phase-1/cloudflare-synchronization.md#10-required-validation-spike). The [sequence](milestone-09-relay-synthetic-gate-sequence.md) orders the harness work, owner-run exercises, and evidence. Real usage stays blocked until this gate passes; P1-M14 does not start until it does.

## Goal

The relay runs on Workers Free at US$0 with no paid subscription or add-on, and a finite remote smoke, a 24-hour capacity and latency measurement, fault and release exercises, a cellular read, and teardown all have recorded evidence. If any criterion fails, the failed condition and the owner's decision are recorded instead, per the [phase risks](phase-1.md).

## Authority

- The agent builds and locally tests the harness only. The owner runs everything that authenticates to Cloudflare, handles a token or content key, inspects billing, or deploys; see [runbook authority](../research/phase-1/cloudflare-relay-spike-runbook.md#authority-and-stop-conditions). The owner authorization in [owner decisions](owner-decisions.md) covers a synthetic-only deployment on an existing Free account.
- Only generated synthetic ciphertext, IDs, and tokens reach Cloudflare. No provider adapter, credential, or real snapshot is involved.

## Entry criteria

- [ ] P1-M8 is `Done` and its open review-hardening item (atomic reader revalidation after an asynchronous body read) is checked with evidence, or the owner explicitly defers it. Today it is unchecked in the [M8 overview](milestone-08-relay-implementation-overview.md#m8-implementation-checklist) with the fix uncommitted in the worktree.
- [ ] Record the starting commit and worktree state; the M9 baseline gate passes.
- [ ] Owner inventories the existing Free account's other workloads (account-wide quotas); the [owner decisions](#owner-decisions) below are recorded.

## In scope

- Porting the harness from the unmerged `spike/cloudflare-relay` branch (`77d8001`) onto the M8 layered relay: `check:deploy-config`, `smoke:remote`, `soak:remote`, `destroy:remote`, and a Node script test suite. That branch targets an earlier relay layout and uses dependency ranges; reuse by review, not by merge. `secrets:provision` from M8 replaces `provision:spike`.
- Harness safety rules from the runbook: tokens and the content key only through hidden prompts, only a canonical HTTPS `workers.dev` origin on the command line, no redirects, bounded responses, redacted output.
- Owner-run deployment, finite remote smoke, 24-hour soak, quota-boundary, fault, recovery, promotion and rollback exercises, iPhone cellular read, and teardown.
- Reconciling the [runbook](../research/phase-1/cloudflare-relay-spike-runbook.md) with the shipped scripts, then recording results in [spike results](../research/phase-1/spike-results.md).

## Out of scope

- Any real usage, provider adapter, or composition-root wiring; changing the v1 wire contract; a new dependency or build tool; a paid Cloudflare service, custom domain, or log stream.
- The Sideloadly re-sign check in the spike list; it belongs to P1-M14, which owns the first installable iOS build.
- Merging `spike/cloudflare-relay`.

## Owner decisions

Approved by the owner on 2026-10-23:

1. **M8 hardening.** Finish the reader-revalidation item (test, verify, commit) before M9 Task 1; it is not deferred.
2. **Cellular read client.** A synthetic-only Shortcut or script on the iPhone that fetches and decrypts a synthetic envelope and shows only pass or fail. No iOS app or web page.
3. **Script tests.** Node's built-in `node --test` is acceptable; it adds no dependency or build tool.
4. **Account and quota.** Use the existing Free account after inventorying its other workloads. Do not exhaust the daily limit; record Cloudflare's published limit response plus a safe lower-bound simulation, which must map to `quotaLimited`.

## Completion checklist

- [ ] Entry criteria hold with recorded commit and a passing baseline gate.
- [x] Owner decisions recorded in the [changelog](changelog.md). Evidence: 2026-10-23 entry.
- [ ] Ported harness scripts pass `node --test` and the complete [contribution-guide gate](../contribution-guide.md#required-validation); no script accepts a secret as an argument or environment value, and `check:deploy-config` rejects Preview URLs, observability, routes, extra bindings, and non-SQLite objects.
- [ ] Runbook matches the shipped scripts and the approved owner answers.
- [ ] Preflight and post-deploy billing show Workers Free, no paid add-on, logs, traces, and Logpush off, and only the single Worker and SQLite Durable Object.
- [ ] Remote smoke passes all ten operations, authority separation, three-reader lifecycle, refresh mailbox, and destruction with redacted output.
- [ ] 24-hour soak completes in one continuous run; requests, CPU, Durable Object duration, rows read and written, storage, and p50/p95 latency are within Free quotas at the [worst-case cadence](../architecture.md#relay-capacity).
- [ ] The simulated quota boundary fails closed, the published limit response is recorded, and it maps to `quotaLimited` without an upgrade or charge.
- [ ] Wall-clock pending-reader and refresh-request expiry, sleeping or offline Mac, revocation mid-request, source and publication failure, token replacement, and destroy-and-re-pair recover as specified.
- [ ] Malformed ciphertext, wrong key, replay, clock skew, and incompatible version preserve the last valid cache.
- [ ] Ciphertext published over Wi-Fi is read and decrypted on iPhone cellular with the Mac disconnected.
- [ ] A compatible new version is smoke-tested on its version URL, promoted, and rolled back with coherent storage.
- [ ] Teardown leaves no state, secrets, Worker, or Durable Object; billing stays US$0.
- [ ] A dated spike-results entry exists with no token, key, ciphertext, ID, or account identifier, and the gate is recorded as passed or failed in [phase-1.md](phase-1.md), the [changelog](changelog.md), and the [P1-M2 open work](../archive/p1-m2-open-work.md) row owner.

## Checkpoints

- **A: Harness.** Entry criteria, owner answers, and the ported local harness with passing gate.
- **B: Deploy and smoke.** Preflight, secrets, reviewed deployment, remote smoke, and billing recheck.
- **C: Soak and faults.** 24-hour measurement, then quota, fault, recovery, cellular, and release exercises.
- **D: Teardown and verdict.** Teardown, evidence entry, and status updates. A failure at any checkpoint stops the later ones and goes to the owner.

## Risks

- **Stale harness.** The spike branch predates the M8 layout and uses `^` ranges. Pin and review it; do not assume it works.
- **Shared quotas.** Other account workloads or a restarted soak invalidate the capacity calculation; a restart is not a continuous result.
- **Secret leakage.** The soak handles seven secrets over 24 hours. Hidden prompts, clipboard clearing, and redacted output are binding.
- **Verdict ambiguity.** Passing local tests is not passing the gate; only deployed evidence counts.
