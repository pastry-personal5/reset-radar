#!/usr/bin/env node

import { performance } from "node:perf_hooks";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  canonicalJSON,
  createSyntheticEnvelope,
  digest,
  HarnessFailure,
  parseActivationResponse,
  parseErrorResponse,
  parseExpiryResponse,
  parsePublicationResponse,
  parseRefreshList,
  parseRemoteOrigin,
  percentile,
  randomIdentifier,
  readHidden,
  relayRequest,
  SAMPLE_SECONDS,
  sampleWorkload,
  SLOT_SECONDS,
  SNAPSHOT_BODY_LIMIT,
  totalWorkload,
  validateSecretSet,
  withPasteboardCleared,
} from "./harness-core.mjs";

const delay = (milliseconds) => new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));
export const MANUAL_REQUEST_SPACING_MS = 60_001;

export function manualRequestWaitMilliseconds(nextAllowedAt, now) {
  return Math.max(0, nextAllowedAt - now);
}

export function parseManualRequestResponse(response) {
  if (response.status === 202) return parseExpiryResponse(response.text);
  if (response.status === 429) {
    try {
      parseErrorResponse(response.text, "requestRateLimited");
    } catch {
      throw new HarnessFailure("Non-relay HTTP 429 stopped the scheduled sample.");
    }
    throw new HarnessFailure("Relay rate-limited a scheduled manual request.");
  }
  throw new HarnessFailure(`Manual request returned HTTP ${response.status}; expected 202.`);
}

export async function runManualRequestRound({
  measured,
  now = () => performance.now(),
  readTokens,
  readyAt,
  requestIDFactory = randomIdentifier,
  wait = delay,
}) {
  if (!Array.isArray(readTokens) || !Array.isArray(readyAt) || readTokens.length !== readyAt.length) {
    throw new HarnessFailure("Manual request schedule is invalid.");
  }
  const accepted = await Promise.all(readTokens.map(async (token, index) => {
    const remaining = manualRequestWaitMilliseconds(readyAt[index] ?? 0, now());
    if (remaining > 0) await wait(remaining);
    const requestID = requestIDFactory();
    const response = await measured("manualRequests", "/v1/refresh-requests", {
      body: canonicalJSON({ protocolVersion: 1, requestID }),
      label: "manual request",
      method: "POST",
      token,
    });
    parseManualRequestResponse(response);
    readyAt[index] = now() + MANUAL_REQUEST_SPACING_MS;
    return { requestID, token };
  }));
  for (const item of accepted) {
    for (let followUp = 0; followUp < 10; followUp += 1) {
      await measured("followUpReads", "/v1/snapshot", {
        bodyLimit: SNAPSHOT_BODY_LIMIT,
        expectedStatus: 200,
        label: "follow-up read",
        token: item.token,
      });
    }
  }
  return accepted.map(({ requestID }) => ({ requestID }));
}

export async function runSoak(originInput, secrets, fetchImplementation = fetch) {
  const origin = parseRemoteOrigin(originInput);
  const planned = sampleWorkload();
  const counts = Object.fromEntries(Object.keys(planned).filter((key) => key !== "slots").map((key) => [key, 0]));
  const latencies = new Map();
  let responseBytes = 0;
  let sequence = 0;
  const publisherID = randomIdentifier(32);
  const key = validateSecretSet(secrets);
  const readerIDs = secrets.readTokens.map(() => randomIdentifier());
  const manualRequestReadyAt = secrets.readTokens.map(() => 0);
  let pending = [];
  let liveRequestIDs = new Set();

  const measured = async (category, path, options) => {
    const started = performance.now();
    const result = await relayRequest(fetchImplementation, origin, path, options);
    const values = latencies.get(category) ?? [];
    values.push(performance.now() - started);
    latencies.set(category, values);
    responseBytes += result.bytes;
    counts[category] += 1;
    return result;
  };
  const publish = async (category, requestID) => {
    sequence += 1;
    const synthetic = createSyntheticEnvelope(sequence, { key, publisherID, requestID });
    const response = await measured(category, "/v1/snapshot", { body: canonicalJSON(synthetic.envelope), expectedStatus: 200, label: category, method: "PUT", token: secrets.writeToken });
    parsePublicationResponse(response.text, sequence);
  };

  for (let index = 0; index < 3; index += 1) {
    parseExpiryResponse((await measured("setupRequests", `/v1/readers/${readerIDs[index]}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(secrets.readTokens[index]) }), expectedStatus: 200, label: "soak reader registration", method: "PUT", token: secrets.adminToken })).text);
    parseActivationResponse((await measured("setupRequests", "/v1/readers/activate", { expectedStatus: 200, label: "soak reader activation", method: "POST", token: secrets.readTokens[index] })).text);
  }
  await publish("setupRequests");

  const startedAt = performance.now();
  for (let slot = 1; slot <= planned.slots; slot += 1) {
    const target = startedAt + (slot - 1) * SLOT_SECONDS * 1000;
    if (performance.now() < target) await delay(target - performance.now());

    if ((slot - 1) % 12 === 0) {
      pending.push(...await runManualRequestRound({
        measured,
        readTokens: secrets.readTokens,
        readyAt: manualRequestReadyAt,
      }));
    }
    if ((slot - 1) % 3 === 0) {
      const listed = parseRefreshList((await measured("requestListPolls", "/v1/refresh-requests", {
        expectedStatus: 200,
        label: "request-list poll",
        token: secrets.writeToken,
      })).text);
      liveRequestIDs = new Set(listed.map((item) => item.requestID));
    }
    if ((slot - 1) % 9 === 0) {
      for (const token of secrets.readTokens) await measured("ordinaryReads", "/v1/snapshot", { bodyLimit: SNAPSHOT_BODY_LIMIT, expectedStatus: 200, label: "ordinary read", token });
    }
    if ((slot - 1) % 6 === 0) {
      await publish("ordinaryPublications");
      pending = pending.filter((item) => liveRequestIDs.has(item.requestID));
      const completion = pending.shift();
      if (completion === undefined) throw new HarnessFailure("No live manual request was available for the planned result.");
      await publish("manualResultPublications", completion.requestID);
      await measured("acknowledgements", `/v1/refresh-requests/${completion.requestID}`, { expectedStatus: 204, label: "manual acknowledgement", method: "DELETE", token: secrets.writeToken });
    }
    if ((slot - 1) % 60 === 0) await publish("heartbeatPublications");
  }
  const remaining = startedAt + SAMPLE_SECONDS * 1000 - performance.now();
  if (remaining > 0) await delay(remaining);

  if (JSON.stringify(counts) !== JSON.stringify(Object.fromEntries(Object.entries(planned).filter(([key]) => key !== "slots")))) throw new HarnessFailure("Observed operation counts did not reconcile with the checked-in workload.");
  const perOperation = Object.fromEntries([...latencies].map(([name, values]) => [name, { p50Milliseconds: percentile(values, 0.5), p95Milliseconds: percentile(values, 0.95) }]));
  const all = [...latencies.values()].flat();
  return {
    durationSeconds: SAMPLE_SECONDS,
    observed: counts,
    overall: { p50Milliseconds: percentile(all, 0.5), p95Milliseconds: percentile(all, 0.95) },
    perOperation,
    plannedRequestCount: totalWorkload(planned),
    responseBytes,
    result: "pass",
  };
}

async function main() {
  if (process.argv.length !== 3) throw new HarnessFailure("Pass only the canonical workers.dev origin.");
  const secrets = await withPasteboardCleared(async () => ({
    writeToken: await readHidden("Synthetic write token"),
    adminToken: await readHidden("Synthetic administration token"),
    contentKey: await readHidden("Synthetic content key"),
    readTokens: [await readHidden("Synthetic reader 1 token"), await readHidden("Synthetic reader 2 token"), await readHidden("Synthetic reader 3 token")],
  }));
  process.stdout.write(`${JSON.stringify(await runSoak(process.argv[2], secrets))}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof HarnessFailure ? error.message : "Remote soak failed."}\n`);
    process.exitCode = 1;
  });
}
