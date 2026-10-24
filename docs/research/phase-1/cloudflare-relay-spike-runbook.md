# Cloudflare relay synthetic-gate runbook

Status: Active

Owner-run procedure for P1-M9 against the shipped relay and synthetic data only. The agent prepares and validates the harness; the owner alone authenticates, handles secrets, inspects private Cloudflare identifiers and billing, deploys, runs remote commands, and tears the Worker down.

## Authority and stop conditions

Never send provider data, credentials, account identifiers, prompts, project paths, or real usage through this procedure. Stop and proceed to [teardown](#9-teardown) if any of these is true:

- the account is not Workers Free, has a paid add-on, or requests payment or an upgrade;
- an unrelated Worker or storage workload appears;
- Workers Logs, traces, Logpush, a custom domain, Version URL, or an unapproved binding is enabled;
- a required request, CPU, Durable Object duration, row, or storage metric is unavailable after deployment without enabling observability;
- a command requests a raw secret in an argument, environment value, file, or visible prompt;
- a reviewed wrapper emits raw Wrangler output or otherwise exposes a token, digest, content key, ciphertext, raw origin, account ID, Worker/version ID, reader/request/publisher ID, or Ray ID; or
- any command differs from the checked-in package scripts below.

Only the canonical non-secret `https://…workers.dev` origin may be a command argument. Keep terminal recording, screen sharing, shell tracing, Universal Clipboard, and Handoff off throughout. Do not paste private command output into repository evidence.

## 1. Preflight

In the Cloudflare dashboard, privately confirm:

1. Workers Free, US$0 current billing, no Workers Paid subscription or paid add-on.
2. No existing Worker or storage workload. If that has changed, stop and reassess account-wide quotas.
3. No custom error page or Custom Error Rule, no custom domain, and no logs, traces, or Logpush.
4. Current official limits still include 100,000 Worker requests/day, 100,000 Durable Object requests/day, 13,000 GB-s/day, SQLite-backed Durable Objects on Free, and fail-closed Error 1027 at the Worker daily limit.

The account has no Worker before this run, so per-Worker metrics are checked immediately after the first deployment. A missing required metric triggers immediate teardown rather than enabling observability.

From the repository root, run the complete local gate from the contribution guide, then:

```sh
npm --prefix relay run check:deploy-config
npm --prefix relay run deploy:dry-run
npm --prefix relay run
```

Confirm the script list includes `cellular:prepare`, `deploy:remote`, `destroy:remote`, `fault:remote`, `release:rollback`, `secrets:provision`, `smoke:remote`, `soak:remote`, and `teardown:worker`. A missing command is a stop condition.

## 2. Authenticate and prepare synthetic secrets

Authenticate with the pinned local Wrangler yourself:

```sh
cd /Volumes/Work_Volume/reset-radar/relay
npx --no-install wrangler --version
npx --no-install wrangler login
npx --no-install wrangler whoami
cd ..
```

Do not retain or share `whoami` output. Create six independent 32-byte random values—write token, administration token, content key, and three reader tokens—and store their unpadded Base64URL encodings as separate temporary password-manager items. Each encoding is exactly 43 characters. Generate one value at a time with this owner-run `zsh` helper:

```zsh
generate_m9_secret() {
  setopt local_options pipefail
  openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\n' | pbcopy || return 1
  if pbpaste | LC_ALL=C grep -Eq '^[A-Za-z0-9_-]{43}$'; then
    printf 'Copied one synthetic secret; store it privately now.\n'
  else
    pbcopy </dev/null
    return 1
  fi
}
```

Clear the pasteboard after each value:

```sh
pbcopy </dev/null
```

Provision both authority digests together. The reviewed command reads the write and administration tokens through hidden terminal prompts, validates their canonical encoding and distinctness, derives the lowercase SHA-256 digests from the decoded bytes, clears the pasteboard even if prompting fails, and sends only the two digests to Wrangler through standard input. It never prints a raw token or digest, exports an environment value, creates a file, or places a secret in an argument:

```sh
npm --prefix relay run secrets:provision
```

Secret bulk provisioning can create a deployable version. Treat it as the first remote mutation and immediately inspect plan, billing, versions, bindings, domains, observability, and resources. Stop and tear down on any discrepancy.

## 3. Deploy and metric check

Deploy only through the reviewed script:

```sh
npm --prefix relay run deploy:remote
```

The command must end with only `Remote Wrangler deploy completed with output suppressed.` after the safe deployment-configuration message. Any raw Wrangler output is a stop condition.

Privately verify that the active deployment is the candidate just created, `workers.dev` is the only route, Version URLs are disabled, the only binding is `RELAY`, storage is SQLite, and only `ADMIN_TOKEN_DIGEST` and `WRITE_TOKEN_DIGEST` exist as secrets. Confirm logs, traces, and Logpush remain disabled.

Confirm the dashboard exposes request count, Worker CPU, Durable Object duration, rows read and written, and storage without enabling a paid or observability feature. If any required metric is missing, run teardown immediately. Recheck Workers Free and US$0 billing.

## 4. Finite smoke

Confirm the origin is the isolated M9 Worker and may be destructively reset. Run:

```sh
npm --prefix relay run smoke:remote -- https://REPLACE.workers.dev
```

The command uses hidden prompts for six distinct canonical synthetic secrets and clears the pasteboard after the last prompt or a prompt failure. It first proves administration and write authority separately, then checks all ten operations, role separation, pending preflight without activation, simulated local-save failure, idempotent activation retry, the three-reader cap, wall-clock pending expiry, publication ordering and strong ETags, AES-GCM authentication, conditional reads, refresh acceptance and non-consuming polls, matching encrypted result, acknowledgement, replay/rate rejection, revocation, and repeated destruction. Pending expiry makes this smoke take slightly over five minutes.

Record only its final redacted pass/fail summary. Recheck resources, observability, usage, and billing.

## 5. Thirty-minute sample

The owner replaced the former 24-hour run with one uninterrupted 30-minute sample. This exercises the intended cadence but does not prove 24-hour stability or a UTC reset. Daily headroom is supported separately by the checked-in 69,445-request additive calculation.

Run once under `caffeinate`:

```sh
caffeinate -dimsu npm --prefix relay run soak:remote -- https://REPLACE.workers.dev
```

Do not restart and combine partial runs. The checked-in model expects 1,422 requests: seven setup operations, 90 accepted manual requests, 900 bounded follow-up reads, 120 ordinary reads, 119 request-list polls, 60 ordinary publications, six heartbeat publications, 60 separately counted manual-result publications, and 60 acknowledgements. Each reader is gated for 60,001 ms from its prior accepted response, and each round issues all three manual requests before any bounded follow-up read. The script must report exactly those observed counts plus response bytes and overall and per-operation p50/p95 latency. A relay `requestRateLimited` response and a non-relay `429` have distinct redacted failures; either invalidates the sample.

After completion, privately record dashboard request count, Worker CPU, Durable Object duration, rows read and written, and storage. Reconcile unexplained account activity before accepting the sample. Recheck observability and billing.

## 6. Quota and fault exercises

Do not exhaust the daily allowance. The checked-in platform fixture represents Cloudflare's documented structured JSON form requested with `Accept: application/json`: `cloudflare_error: true`, `error_category: rate_limit`, and `error_code: 1027`. The transport accepts that bounded combination for any matching 4xx/5xx status and maps it to `quotaLimited`; altered fields fail closed. Record the official documentation date and the local regression result.

Run the reviewed remote fault exercise:

```sh
npm --prefix relay run fault:remote -- https://REPLACE.workers.dev
```

It uses hidden prompts, resets to synthetic state, and checks client cache retention for malformed JSON/ciphertext, wrong key, altered tag, replay, clock skew, incompatible version, rate limit, quota failure, and outage. Remote cases cover revocation mid-request, an offline/sleeping synthetic Mac and wall-clock request expiry, source failure, publication failure, reader-token replacement, and destroy-and-re-pair recovery. Record only the redacted case counts, before/after cache sequence, and pass/fail result.

## 7. Cellular check

Install Scriptable temporarily on the iPhone. Import the unchanged checked-in `relay/scripts/cellular-scriptable.js` as a new script named `Reset Radar M9`; the file contains only code and a public protocol self-test vector. Do not place the origin, a token, or the content key in the script, its name, a file, or a Shortcut. Scriptable's documented secure alert fields hide the private inputs, and its WebView supplies the WebCrypto context after the script blocks WebView resource requests. The embedded public-vector self-test must pass before the input alert appears.

While the Mac is still online, prepare a fixed public publisher profile, one pending reader, and a fresh encrypted synthetic snapshot. This command destructively resets the current synthetic relay state and prompts only for the write token, administration token, content key, and reader 1 token:

```sh
npm --prefix relay run cellular:prepare -- https://REPLACE.workers.dev
```

On a pass, disconnect the Mac from every network and turn iPhone Wi-Fi off. Confirm the iPhone is using cellular data, run `Reset Radar M9` in Scriptable, and enter the canonical origin, reader 1 token, and content key into the alert. The script rejects redirects and noncanonical origins, uses a ten-second timeout and a 64 KiB response cap, validates the strong ETag and exact canonical envelope, authenticates AES-256-GCM with the canonical header as associated data, checks the fixed publisher, minimum sequence, synthetic schema, and clock, commits the validated result to memory, and only then activates the pending reader. It writes no file or Keychain item and reports only pass/fail, zero request-body bytes, and response bytes.

Record those displayed aggregate values only. Reconnect the Mac, delete the `Reset Radar M9` script, remove any transferred copy, clear the iPhone pasteboard, and delete Scriptable. If the self-test does not reach the secure input alert or the run shows `FAIL`, stop; no other app, hosted page, or crypto library is approved. The temporary-tool decision is recorded in [owner decisions](../../phase-1/owner-decisions.md). The relevant Scriptable APIs are its official [Alert](https://docs.scriptable.app/alert/), [Request](https://docs.scriptable.app/request/), [Data](https://docs.scriptable.app/data/), [Pasteboard](https://docs.scriptable.app/pasteboard/), and [WebView](https://docs.scriptable.app/webview/) documentation.

## 8. Release and rollback

The Durable Object Worker has no Version URL. On this isolated synthetic Worker:

1. Run `npm --prefix relay run deploy:remote` for the compatible candidate.
2. Privately verify in the dashboard that it is the active 100% deployment.
3. Immediately run `smoke:remote`; on failure, run `npm --prefix relay run release:rollback` and then teardown.
4. On success, run `npm --prefix relay run release:rollback` for the planned rollback exercise.
5. Privately verify the prior version is active, rerun `smoke:remote`, and confirm storage remains coherent.
6. Recheck observability, resources, usage, and billing after each deployment mutation.

The rollback wrapper accepts Wrangler's default prior deployment with `--yes`, suppresses its bounded output, and must emit only its fixed redacted summary. Never put a version identifier in a script argument or repository evidence.

## 9. Teardown

Run after success, failure, or an owner stop:

```sh
npm --prefix relay run destroy:remote -- https://REPLACE.workers.dev
npm --prefix relay run teardown:worker
```

`destroy:remote` performs authenticated destruction twice, proves the mailbox and snapshot are empty with synthetic probes, removes the probe, proves the reader list is empty, and deletes the verification schema once more. `teardown:worker` invokes the reviewed Wrangler deletion flow; approve only deletion of the isolated M9 Worker.

`teardown:worker` requires typing `DELETE` at its fixed local prompt, supplies the Wrangler confirmation through standard input, suppresses bounded Wrangler output, and emits only its fixed redacted summary.

In the dashboard, confirm the Worker, active deployments, secrets, route, and removable Durable Object resources are gone. Cloudflare may retain provider-managed point-in-time recovery data for its documented period; do not claim immediate physical erasure. Confirm Workers Free and US$0 billing, then delete exactly the six temporary password-manager items and clear the pasteboard.

## 10. Evidence handoff

Give the agent only redacted aggregate evidence:

- date and pass/fail for plan, billing, bindings, observability, and resource checks;
- smoke and fault final summaries;
- 30-minute planned/observed counts, response bytes, p50/p95 values, and dashboard aggregates;
- official quota-document date and regression pass;
- cellular request/response byte counts and pass/fail;
- promotion, active-version verification, rollback, and storage-coherence pass/fail without IDs; and
- teardown, recovery-retention acknowledgement, and final US$0 billing pass/fail.

Never provide a token, key, digest, ciphertext, raw origin, Cloudflare/account/Worker/version/Ray identifier, reader/request/publisher identifier, screenshot containing one, or raw command output. The agent records the dated aggregate verdict in `spike-results.md` and updates the M9 checklist only when each item has direct evidence.
