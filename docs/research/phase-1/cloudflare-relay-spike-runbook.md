# Cloudflare relay spike runbook

Status: Deferred

This owner-run procedure prepares and executes the P1-M2 synthetic-only Cloudflare relay validation on the `spike/cloudflare-relay` throwaway branch. It supplies repeatable local, secret-generation, deployment, measurement, and teardown commands without authorizing real usage data or provider adapters.

## Authority and stop conditions

This procedure is for the owner to run while present. Codex must not deploy the Worker, authenticate to Cloudflare, inspect Cloudflare billing, or handle a Cloudflare API token.

Only generated synthetic ciphertext and synthetic opaque request IDs may reach the Worker. Do not send a provider response, provider credential, provider account identifier, prompt, project path, or an envelope that can be decrypted into usage data. Stop immediately and record a failed or deferred result if any of these conditions occurs:

- The account is not on Workers Free, has Workers Paid, or has any paid add-on.
- The dashboard indicates Workers Logs, traces, Logpush, a custom domain, or an unapproved binding is enabled.
- A command asks to create a paid resource, upgrade a plan, or attach a payment method for the Worker.
- The harness would need a real provider adapter or a non-synthetic observation.
- A secret could be pasted into a command argument, file, source file, committed configuration, terminal transcript, or spike-results entry.

The protocol and pass criteria remain binding in [Cloudflare synchronization](cloudflare-synchronization.md#10-required-validation-spike) and [Relay module](../../architecture/relay.md). This runbook is an execution aid, not a replacement for either document.

## Prepared branch and expected harness

```sh
git switch spike/cloudflare-relay
git status --short --branch
```

Keep all harness code and temporary configuration on this branch. Do not merge it into `main`; P1-M3 may promote reusable code or fixtures only after review. The harness must expose the local commands below before a remote deployment is attempted:

```sh
npm --prefix relay ci
npm --prefix relay test
npm --prefix relay run typecheck
npm --prefix relay run check:deploy-config
npm --prefix relay run dev
npm --prefix relay run smoke:local
npm --prefix relay run provision:spike -- WRITE_TOKEN_DIGEST
npm --prefix relay run provision:spike -- ADMINISTRATION_TOKEN_DIGEST
npm --prefix relay run deploy:spike
npm --prefix relay run smoke:remote
npm --prefix relay run soak:remote
npm --prefix relay run destroy:remote
```

Run `npm --prefix relay run` and confirm that it lists every named script. A missing `smoke:local`, `deploy:spike`, `smoke:remote`, or `destroy:remote` script is a stop condition, not permission to substitute an ad hoc `curl` or Wrangler command. `npm install` is only for the harness author when initially creating or intentionally updating the lockfile; the owner-run procedure uses `npm ci` and must not change dependency resolution.

`provision:spike` reads one digest through standard input. `smoke:remote`, `soak:remote`, and `destroy:remote` read raw relay tokens only through owner-present hidden prompts. They must never accept a relay, Cloudflare, reader, write, administration, or content-encryption secret as a command-line argument or environment variable echoed by the shell. A `wrangler.toml`, `wrangler.json`, `.dev.vars`, `.env`, test fixture, and source file must contain no secret values. The non-secret deployed origin is the only command-line value accepted by the remote commands.

The branch now includes the synthetic snapshot, reader lifecycle, manual-request, and authenticated-destruction protocol; a SQLite-backed Durable Object; local Workers conformance tests; fail-closed deployment validation; standard-input secret provisioning; a destructive full remote smoke; and idempotent remote state destruction. It contains no provider adapter or real usage fixture. Before running the commands above, the owner must approve installation of the declared npm development dependencies; the first `npm install` creates the lockfile, and subsequent clean installs use `npm ci`.

Before the next remote deployment, pin the tested npm, Wrangler, Workers Vitest, TypeScript, and compatibility-date versions in `relay/package.json`, its lockfile, and Wrangler configuration. Exact package versions, without `^`, `~`, `latest`, or another range, are required before the owner proceeds remotely. The current package manifest still uses dependency ranges, so this is a stop condition until the owner approves that dependency-manifest change. Use the current [Workers Vitest integration](https://developers.cloudflare.com/workers/testing/vitest-integration/), which runs Worker tests locally with isolated storage, and SQLite Durable Object exports as documented in [Cloudflare's Durable Object guide](https://developers.cloudflare.com/durable-objects/get-started/).

## 1. Owner preflight

In the Cloudflare dashboard, before logging in with Wrangler or deploying:

1. Select an otherwise-unused account, or inventory every existing Worker and storage workload that shares the account-wide Free quotas.
2. Record the date, account label (not account email), selected plan, enabled add-ons, Worker count, current request/storage usage, and observability settings in a private owner worksheet. Do not put account identifiers in the repository.
3. Confirm **Workers Free**, no Workers Paid subscription, no paid add-on, and no custom-domain purchase. Confirm the Worker will use only its assigned `workers.dev` hostname.
4. Confirm Workers Logs, traces, Logpush, Analytics Engine, D1, KV, R2, Queues, Workflows, Access, and Secrets Store are not enabled or bound. Per-Worker encrypted secrets and one SQLite-backed Durable Object are the allowed Cloudflare resources.
5. Recheck the published Free pricing, limits, `workers.dev`, logs, and observability pages on the deployment day. Pricing and product defaults can change after the research date.

If the preflight is clean, install the lockfile and authenticate with its local Wrangler in a normal terminal:

```sh
cd /Volumes/Work_Volume/reset-radar
npm --prefix relay ci
cd relay
npx --no-install wrangler --version
npx --no-install wrangler login
npx --no-install wrangler whoami
```

Confirm that the printed Wrangler version equals the exact version in `relay/package.json` and the lockfile. Complete browser authentication yourself. Do not paste an API token into this terminal or share it with an agent, and do not copy the `whoami` output into repository evidence because it may contain account identifiers.

## 2. Local validation

Run the finite checks before any Cloudflare deployment:

```sh
cd /Volumes/Work_Volume/reset-radar
npm --prefix relay ci
npm --prefix relay test
npm --prefix relay run typecheck
npm --prefix relay run check:deploy-config
```

Run the complete local protocol smoke in the Workers runtime with isolated SQLite storage and in-memory synthetic digest bindings:

```sh
cd /Volumes/Work_Volume/reset-radar
npm --prefix relay run smoke:local
```

`smoke:local` does not read an owner secret, create a secret file, or contact Cloudflare. `npm --prefix relay run dev` remains available for optional unauthenticated health-route inspection, but authenticated routes intentionally fail closed because no `.dev.vars`, environment-secret, or command-line-secret fallback exists. Do not try to make authenticated `wrangler dev` work by writing a real or synthetic relay token to a local configuration file.

The unit/integration tests and local smoke suite together cover:

- write/read authority crossover, strict publisher and sequence binding, body and version bounds, ETags, authenticated `404`, and conditional `304`;
- three-reader registration, preflight-without-activation, activation retry, expiry, revocation, and fourth-reader rejection;
- manual request authentication, one-per-reader pending request, duplicate/replayed IDs, rate limit, expiry, Mac poll-without-consumption, acknowledgement, and relay destruction;
- generic bounded error responses, no intentional redirects, and no secrets/ciphertext in test output; and
- incompatible outer versions, oversized input, strict replay rejection, and empty state after destruction.

The relay intentionally treats ciphertext as opaque. AES-GCM wrong-key and altered-tag behavior is checked by the remote smoke's synthetic client; clock-skew, quota, outage, and platform cache-retention outcomes remain in the later fault exercises.

Local success is not spike success. It is only the prerequisite for owner-present remote deployment.

## 3. Secret-safe remote setup

Generate three independent synthetic relay secrets locally: a write token, an administration token, and a content-encryption key. The content key never goes to Cloudflare. Generate reader tokens separately when registering each synthetic reader.

For this spike, encode each 32-byte random value as unpadded base64url. The result is exactly 43 ASCII characters and still contains 256 bits of randomness. This is a storage encoding, not a password-strength setting and not an instruction to generate 43 random characters.

### 3.1 Check the local tools

Run these commands in the macOS default `zsh`. They print versions and paths, never secret values:

```sh
command -v openssl pbcopy pbpaste xxd
openssl version
cd /Volumes/Work_Volume/reset-radar/relay
npx --no-install wrangler --version
```

Every required tool must resolve successfully. Stop if one is missing. Do not replace one with an online generator.

### 3.2 Generate and retain independent values

Temporarily disable Universal Clipboard/Handoff, close screen-sharing and terminal-recording software, and make sure no shell debugging such as `set -x` is active. Define this helper exactly as shown:

```zsh
generate_spike_secret() {
  setopt local_options pipefail
  openssl rand -base64 32 |
    tr '/+' '_-' |
    tr -d '=\n' |
    pbcopy || return 1

  if pbpaste | LC_ALL=C grep -Eq '^[A-Za-z0-9_-]{43}$'; then
    printf 'Copied one valid 256-bit spike secret; save it now.\n'
  else
    pbcopy </dev/null
    printf 'Generation failed; the clipboard was cleared.\n' >&2
    return 1
  fi
}
```

Run `generate_spike_secret` once for each row below. After each invocation, immediately paste the value into a new password-manager item or another owner-controlled secure store, using the suggested label. Do not invoke the helper again until the preceding value is saved because every invocation replaces the clipboard.

| Value | Suggested private label | Remote handling |
|---|---|---|
| Write token | `reset-radar-spike/write-token` | Only its SHA-256 digest becomes a Worker secret. |
| Administration token | `reset-radar-spike/administration-token` | Only its SHA-256 digest becomes a Worker secret. |
| Content-encryption key | `reset-radar-spike/content-key` | Never sent to Cloudflare; the harness decodes it to exactly 32 bytes for AES-GCM. |
| Reader 1 token | `reset-radar-spike/reader-1-token` | Only its digest is registered through the authenticated harness. |
| Reader 2 token | `reset-radar-spike/reader-2-token` | Only its digest is registered through the authenticated harness. |
| Reader 3 token | `reset-radar-spike/reader-3-token` | Only its digest is registered through the authenticated harness. |

Use these commands after saving each value and at any interruption:

```zsh
pbcopy </dev/null
if pbpaste | grep -q .; then
  printf 'Clipboard is not empty; stop and clear it.\n' >&2
else
  printf 'Clipboard is empty.\n'
fi
```

The generator never prints the value or puts it in shell history, a file, an environment variable, or a command argument. The short-lived pasteboard handoff is why Universal Clipboard and recording must be disabled and why the clipboard is cleared after every save. Never put the raw values in source, `.dev.vars`, `.env`, fixtures, documents, screenshots, or spike evidence.

### 3.3 Derive and upload the Worker-secret digests

The spike represents a SHA-256 digest as 64 lowercase hexadecimal characters. The Worker validates that exact binding format before comparing it, and the conformance tests cover malformed authority and token crossover. Define this second helper in the same `zsh` session:

```zsh
digest_spike_token() {
  setopt local_options pipefail
  local spike_token

  printf 'Paste one raw token from the password manager, then press Return: '
  IFS= read -r -s spike_token || return 1
  printf '\n'

  if ! printf '%s' "$spike_token" |
    openssl dgst -sha256 -binary |
    xxd -p -c 256 |
    tr -d '\n' |
    pbcopy; then
    unset spike_token
    pbcopy </dev/null
    printf 'Digest generation failed; the clipboard was cleared.\n' >&2
    return 1
  fi
  unset spike_token

  if pbpaste | LC_ALL=C grep -Eq '^[0-9a-f]{64}$'; then
    printf 'Digest copied; the raw token is no longer on the clipboard.\n'
  else
    pbcopy </dev/null
    printf 'Digest validation failed; the clipboard was cleared.\n' >&2
    return 1
  fi
}
```

From `relay/`, copy the raw write token from the password manager, run the first block, and paste the token only into the hidden prompt. Then pipe the clipboard-held digest to the reviewed provisioning script. Do the same with the administration token and the second binding:

```zsh
digest_spike_token &&
  pbpaste | npm run provision:spike -- WRITE_TOKEN_DIGEST
pbcopy </dev/null
```

```zsh
digest_spike_token &&
  pbpaste | npm run provision:spike -- ADMINISTRATION_TOKEN_DIGEST
pbcopy </dev/null
```

The pipeline gives the script one digest through standard input. The script validates the binding name and digest encoding, then gives the digest to the repository-local Wrangler through standard input; neither the raw token nor its digest is a command-line argument. Wrangler's `secret put` creates a Worker version and deploys it immediately, so each block is a remote mutation and may be the first deployment of the Worker. Run it only after the owner preflight and local validation pass. Do not use `--yes`, `--env-file`, a bulk-secret file, or a shell environment variable.

Verify only secret metadata:

```zsh
npx --no-install wrangler secret list
pbcopy </dev/null
unset spike_token
unfunction generate_spike_secret digest_spike_token
```

The list must contain exactly `WRITE_TOKEN_DIGEST` and `ADMINISTRATION_TOKEN_DIGEST`, both as secret-text bindings; Wrangler does not reveal their values. Stop on any additional or missing binding. The content key must not appear. [Cloudflare's secret commands](https://developers.cloudflare.com/workers/wrangler/commands/workers/#secret) document standard-input upload, metadata-only listing, and the fact that `secret put` deploys a new version.

The reader-token digests belong in the Durable Object only through authenticated synthetic `PUT /v1/readers/{id}` requests. They are not Worker secrets and must not be written to a local configuration file. The full remote smoke generates four temporary reader tokens and IDs in process memory, registers only their digests, exercises the three-reader cap, and destroys the state before exit. The separately saved reader tokens remain reserved for the longer owner-run and device exercises; do not pass them to `smoke:remote`.

## 4. Reviewed deployment and initial remote smoke test

Reinspect the dashboard after secret setup, including the versions that `wrangler secret put` deployed. Then deploy the reviewed harness only to the configured `workers.dev` Worker:

```sh
cd /Volumes/Work_Volume/reset-radar
npm --prefix relay run deploy:spike
npm --prefix relay run smoke:remote -- https://worker-name.account-label.workers.dev
```

`deploy:spike` first runs `check:deploy-config`. It must refuse configuration that enables Preview URLs, observability, Logpush, an additional binding, a route/custom domain, or a non-SQLite Durable Object. Wrangler must show the expected `workers.dev` trigger without a Preview URLs warning. If a prior checkpoint deployment enabled Preview URLs by default, this reviewed deployment must explicitly disable them; confirm that the dashboard no longer offers a Preview URL before continuing.

`smoke:remote` requires the non-secret deployed origin shown by Wrangler and then prompts invisibly for the raw write and administration tokens. It accepts only a canonical HTTPS `workers.dev` origin, refuses redirects, bounds every response, and prints only a redacted pass/fail result. It first destroys prior synthetic object state, then verifies health and closed routes; token-role separation; three-reader registration, preflight, activation, retry, list, cap, and revocation; AES-GCM synthetic ciphertext round trip, wrong-key and altered-tag rejection in the client, publisher/sequence rejection, ETags and `304`; three simultaneous manual requests, duplicate, rate-limit, non-consuming poll, idempotent acknowledgement, completed-ID replay, and revocation cleanup; and two final `DELETE /v1/relay` calls.

This command is intentionally destructive to this isolated synthetic spike Worker. Do not run it against state that must be retained. A pass ends with empty active Durable Object state; it does not remove the Worker or its secret bindings.

Pass the origin as the only command-line value, then paste each token only at its named hidden prompt:

```sh
npm --prefix relay run smoke:remote -- https://worker-name.account-label.workers.dev
```

The command proves the finite protocol cases, not pending-reader or manual-request wall-clock expiry, platform quota behavior, 24-hour capacity, sleeping/offline Mac behavior, cellular retrieval, or deployment promotion and rollback. Those remain separate owner-run exercises below.

The owner must review the Cloudflare dashboard immediately after the smoke test: billing remains US$0; no upgrade/add-on appeared; Preview URLs and observability remain off; and the expected single Worker and SQLite Durable Object are the only new resources.

Workers versions do not version Durable Object storage. When testing a version upgrade or rollback, verify protocol compatibility and stored state explicitly; a Worker rollback is not a storage rollback.

## 5. 24-hour measurement

Start only after the initial remote smoke test and the post-smoke Free-plan/dashboard check pass. The smoke destroys its own state; `soak:remote` registers and activates three new synthetic readers. It prompts invisibly for the saved write token, administration token, content-encryption key, and three separately saved reader tokens from section 3.2. Do not put any value in an argument, environment variable, or file.

From the repository root, run the reviewed client in an interactive macOS terminal, ideally just after 00:00 UTC (09:00 in Korea). Keep the Mac awake with its lid open and network available for the entire run:

```sh
cd /Volumes/Work_Volume/reset-radar
npm --prefix relay run check:deploy-config
date -u '+%Y-%m-%dT%H:%M:%SZ'
caffeinate -i npm --prefix relay run soak:remote -- https://worker-name.account-label.workers.dev
pbcopy </dev/null
```

The command takes about **24 hours 14 minutes**. It uses 17,280 paced five-second slots, with a small margin above the relay's 60-second per-reader manual-request limit. It sends 1,440 accepted manual requests per reader, ten snapshot reads per manual request, 1,930 ordinary snapshot reads per reader, 5,760 Mac request-list polls, 2,880 ordinary publications, 288 heartbeat publications, and up to 2,880 synthetic manual results and acknowledgements under the Mac's 30-second read cap: about 68,005 total Worker requests including setup. It prints only hourly aggregate progress and a final JSON summary with UTC start/end, request counts, client p50/p95 latency, response bytes, and matched/unmatched synthetic manual results. The conservative architecture budget also allows 4,320 acknowledgements; the runnable 30-second Mac cap permits at most 2,880 completions during this schedule. A command failure means the 24-hour measurement is incomplete. The script leaves state in place on success or failure; do not rerun the destructive `smoke:remote` during the measurement. The script clears the clipboard immediately after the last hidden prompt; also clear it manually at any interruption.

After it finishes, record the final UTC time and the pinned versions privately. Cloudflare Free daily counters reset at 00:00 UTC, so record the dashboard totals by UTC calendar day as well as over the run. If you need to restart after a failure, first inspect the partial result and use the authenticated `destroy:remote` command in section 7 to clear the synthetic state; then begin a fresh run. Do not treat a restarted interval as one continuous 24-hour result.

For each measurement interval, record:

| Measure | Required evidence |
|---|---|
| Worker and Durable Object requests | Dashboard aggregate count and calculated daily total |
| Worker CPU and Durable Object duration | Dashboard aggregate values and margin to Free allocation |
| SQLite rows read/written and stored bytes | Dashboard/storage values, including auxiliary-row overhead |
| Latency | Synthetic request timestamps and p50/p95 round trips |
| Cellular path | iPhone on cellular only; Mac disconnected after Wi-Fi publication; successful synthetic decrypt/read |
| Billing and configuration | Before/after Free-plan, no-add-on, disabled-observability confirmation |

Never capture HTTP headers, bodies, opaque ciphertext, reader IDs, tokens, account ID, or raw dashboard URLs in the evidence. Summarize measured totals and redacted pass/fail results in [spike results](spike-results.md) only after the run is complete.

## 6. Fault, recovery, and release exercises

After the 24-hour measurement, run the harness's remote cases with synthetic data only:

1. Free-quota boundary where safe, manual-request rate limit, Worker failure, and network loss; verify failure is closed and the client would retain an honest stale cache.
2. Wrong key, malformed ciphertext, replay, clock skew, unsupported version, oversized body, unexpected publisher, equal/lower sequence, and wrong authority token.
3. Mac awake, asleep, and offline manual-refresh completion/timeout; revocation before a request completes; source failure; and publication failure.
4. Token replacement plus full destroy-and-re-pair recovery. Confirm that `DELETE /v1/relay` is idempotent and clears active object state.
5. Compatible version deployment, version-URL smoke test, promotion, and rollback. Confirm the data remains coherent after each step.

Record the exact result and measured values, not secrets or request contents. A failed condition remains an unchecked P1-M2 item and must be returned to the owner for a decision.

## 7. Teardown

After all remote checks and before leaving the branch, destroy the synthetic relay while the owner is present:

```sh
cd /Volumes/Work_Volume/reset-radar
npm --prefix relay run destroy:remote -- https://worker-name.account-label.workers.dev
cd relay
npx --no-install wrangler secret delete WRITE_TOKEN_DIGEST
npx --no-install wrangler secret delete ADMINISTRATION_TOKEN_DIGEST
npx --no-install wrangler secret list
npx --no-install wrangler delete
```

The harness destroy command invisibly prompts for the administration token, calls `DELETE /v1/relay` twice, rejects redirects and nonempty responses, and prints no token or relay identifier. Delete the two Worker-secret bindings only after that authenticated destruction succeeds. Confirm both deletions interactively; `secret list` must then return no bindings. Wrangler's final interactive delete confirmation removes the Worker deployment; complete it manually. Do not add a skip-confirmation flag. Confirm in the dashboard that the Worker, Durable Object namespace/resources, test versions, and any temporary deployment are gone.

Clear the pasteboard again, remove only the six `reset-radar-spike/*` items from the private secure store, and re-enable Handoff only if desired. Finally, revisit billing and usage. Record the US$0 result, disabled observability, teardown completion, and any provider-managed recovery-retention caveat in the spike-results entry. Do not claim the Cloudflare gate passes until every criterion in the canonical research and relay-conformance list has evidence.

## Evidence handoff

Create one dated [spike results](spike-results.md) entry after the work. It must state whether the run was owner-present, the harness/Cloudflare/Wrangler versions, methods, aggregate measured values, each pass/fail/deferred condition, and blockers. It must never include a raw provider response, credential, account identifier, prompt, project path, token, content key, ciphertext, reader ID, or request ID.
