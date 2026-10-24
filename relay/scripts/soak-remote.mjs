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
export const FOLLOW_UP_READ_COUNT = 10;
export const MANUAL_REQUEST_SPACING_MS = 60_001;
export const MAX_SLOT_LAG_MS = SLOT_SECONDS * 1000;

export function manualRequestWaitMilliseconds(nextAllowedAt, now) {
  if (!Number.isFinite(nextAllowedAt) || nextAllowedAt < 0 || !Number.isFinite(now) || now < 0) {
    throw new HarnessFailure("Manual request schedule is invalid.");
  }
  return Math.max(0, nextAllowedAt - now);
}

export function sampleSlotDelayMilliseconds(target, now) {
  if (!Number.isFinite(target) || !Number.isFinite(now)) {
    throw new HarnessFailure("Sample schedule timing was invalid.");
  }
  if (now - target > MAX_SLOT_LAG_MS) {
    throw new HarnessFailure("Sample fell more than one slot behind schedule.");
  }
  return Math.max(0, target - now);
}

export function observedElapsedMilliseconds(startedAt, completedAt) {
  if (!Number.isFinite(startedAt) || !Number.isFinite(completedAt) || completedAt < startedAt) {
    throw new HarnessFailure("Observed sample duration was invalid.");
  }
  return Math.round(completedAt - startedAt);
}

export function sampleCompletionTarget(startedAt, finalFollowUpSlot) {
  if (!Number.isFinite(startedAt) || startedAt < 0 ||
      !Number.isSafeInteger(finalFollowUpSlot) || finalFollowUpSlot < 0) {
    throw new HarnessFailure("Sample completion schedule was invalid.");
  }
  const deadline = startedAt + SAMPLE_SECONDS * 1000;
  if (finalFollowUpSlot === 0) return deadline;
  return Math.max(deadline, startedAt + (finalFollowUpSlot - 1) * SLOT_SECONDS * 1000);
}

export function validateSoakAccounting(planned, counts, latencies, responseBytes) {
  const plannedKeys = Object.keys(planned).filter((key) => key !== "slots").sort();
  const countKeys = Object.keys(counts).sort();
  if (JSON.stringify(plannedKeys) !== JSON.stringify(countKeys) || plannedKeys.some((key) =>
    !Number.isSafeInteger(planned[key]) || planned[key] < 0 || counts[key] !== planned[key])) {
    throw new HarnessFailure("Observed operation counts did not reconcile with the checked-in workload.");
  }
  if (!(latencies instanceof Map) || JSON.stringify([...latencies.keys()].sort()) !== JSON.stringify(plannedKeys) ||
      plannedKeys.some((key) => {
        const values = latencies.get(key);
        return !Array.isArray(values) || values.length !== counts[key] ||
          values.some((value) => !Number.isFinite(value) || value < 0);
      })) {
    throw new HarnessFailure("Observed latency measurements were invalid.");
  }
  if (!Number.isSafeInteger(responseBytes) || responseBytes < 0) {
    throw new HarnessFailure("Observed response bytes were invalid.");
  }
}

export function parseManualRequestResponse(response) {
  if (response.status === 202) return parseExpiryResponse(response.text, 2);
  if (response.status === 429) {
    try {
      parseErrorResponse(response.text, "requestRateLimited", 2);
    } catch {
      throw new HarnessFailure("Unrecognized HTTP 429 stopped the scheduled sample.");
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
  if (!Array.isArray(readTokens) || !Array.isArray(readyAt) || readTokens.length !== 3 || readyAt.length !== 3) {
    throw new HarnessFailure("Manual request schedule is invalid.");
  }
  const preflightNow = now();
  for (const nextAllowedAt of readyAt) manualRequestWaitMilliseconds(nextAllowedAt, preflightNow);
  let requestIDs;
  try { requestIDs = readTokens.map(() => requestIDFactory()); } catch {
    throw new HarnessFailure("Manual request identifiers are invalid.");
  }
  if (requestIDs.some((requestID) => !/^[0-9a-f]{32}$/.test(requestID)) ||
      new Set(requestIDs).size !== requestIDs.length) {
    throw new HarnessFailure("Manual request identifiers are invalid.");
  }
  const settled = await Promise.allSettled(readTokens.map(async (token, index) => {
    const remaining = manualRequestWaitMilliseconds(readyAt[index] ?? 0, now());
    if (remaining > 0) await wait(remaining);
    const requestID = requestIDs[index];
    const response = await measured("manualRequests", "/v2/refresh-requests", {
      body: canonicalJSON({ protocolVersion: 2, requestID, target: "allCodex" }),
      label: "manual request",
      method: "POST",
      token,
    });
    parseManualRequestResponse(response);
    readyAt[index] = now() + MANUAL_REQUEST_SPACING_MS;
    return { requestID, token };
  }));
  const rejection = settled.find((result) => result.status === "rejected");
  if (rejection !== undefined) {
    if (rejection.reason instanceof HarnessFailure) throw rejection.reason;
    throw new HarnessFailure("Manual request round failed.");
  }
  return settled.map((result) => result.value);
}

export function enqueueFollowUpReads(schedule, startSlot, accepted) {
  if (!(schedule instanceof Map) || !Number.isSafeInteger(startSlot) || startSlot < 1 ||
      !Array.isArray(accepted) || accepted.length !== 3 ||
      accepted.some((item) => item === null || typeof item !== "object" ||
        !/^[0-9a-f]{32}$/.test(item.requestID) || typeof item.token !== "string" || item.token.length === 0) ||
      new Set(accepted.map((item) => item.requestID)).size !== accepted.length ||
      new Set(accepted.map((item) => item.token)).size !== accepted.length) {
    throw new HarnessFailure("Follow-up read schedule is invalid.");
  }
  const slots = Array.from({ length: FOLLOW_UP_READ_COUNT }, (_value, offset) => startSlot + offset);
  if (slots.some((slot) => schedule.has(slot))) {
    throw new HarnessFailure("Follow-up read schedule overlapped an existing slot.");
  }
  const tokens = accepted.map((item) => item.token);
  for (const slot of slots) schedule.set(slot, [...tokens]);
  return slots.at(-1);
}

export async function runFollowUpReadsForSlot({ measured, schedule, slot }) {
  if (typeof measured !== "function" || !(schedule instanceof Map) ||
      !Number.isSafeInteger(slot) || slot < 1) {
    throw new HarnessFailure("Follow-up read schedule is invalid.");
  }
  const tokens = schedule.get(slot);
  if (tokens === undefined) return 0;
  if (!Array.isArray(tokens) || tokens.length !== 3 ||
      tokens.some((token) => typeof token !== "string" || token.length === 0) ||
      new Set(tokens).size !== tokens.length) {
    throw new HarnessFailure("Follow-up read schedule is invalid.");
  }
  const settled = await Promise.allSettled(tokens.map((token) => measured(
    "followUpReads",
    "/v1/snapshot",
    {
      bodyLimit: SNAPSHOT_BODY_LIMIT,
      expectedStatus: 200,
      label: "follow-up read",
      token,
    },
  )));
  schedule.delete(slot);
  const rejection = settled.find((result) => result.status === "rejected");
  if (rejection !== undefined) {
    if (rejection.reason instanceof HarnessFailure) throw rejection.reason;
    throw new HarnessFailure("Follow-up read round failed.");
  }
  return settled.length;
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
  const followUpSchedule = new Map();
  let finalFollowUpSlot = 0;
  let pending = [];
  let liveRequestIDs = new Set();

  const measured = async (category, path, options) => {
    if (!Object.hasOwn(counts, category)) throw new HarnessFailure("Unreviewed sample operation category.");
    const started = performance.now();
    const result = await relayRequest(fetchImplementation, origin, path, options);
    const elapsed = performance.now() - started;
    if (!Number.isFinite(elapsed) || elapsed < 0) throw new HarnessFailure("Sample latency measurement was invalid.");
    const values = latencies.get(category) ?? [];
    values.push(elapsed);
    latencies.set(category, values);
    if (!Number.isSafeInteger(result.bytes) || result.bytes < 0 ||
        !Number.isSafeInteger(responseBytes + result.bytes)) {
      throw new HarnessFailure("Sample response byte measurement was invalid.");
    }
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

  const waitForSlot = async (slot) => {
    const target = startedAt + (slot - 1) * SLOT_SECONDS * 1000;
    let remaining = sampleSlotDelayMilliseconds(target, performance.now());
    while (remaining > 0) {
      await delay(remaining);
      remaining = sampleSlotDelayMilliseconds(target, performance.now());
    }
  };

  for (let index = 0; index < 3; index += 1) {
    parseExpiryResponse((await measured("setupRequests", `/v1/readers/${readerIDs[index]}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(secrets.readTokens[index]) }), expectedStatus: 200, label: "soak reader registration", method: "PUT", token: secrets.adminToken })).text);
    parseActivationResponse((await measured("setupRequests", "/v1/readers/activate", { expectedStatus: 200, label: "soak reader activation", method: "POST", token: secrets.readTokens[index] })).text);
  }
  await publish("setupRequests");

  const startedAt = performance.now();
  for (let slot = 1; slot <= planned.slots; slot += 1) {
    await waitForSlot(slot);

    if ((slot - 1) % 12 === 0) {
      const accepted = await runManualRequestRound({
        measured,
        readTokens: secrets.readTokens,
        readyAt: manualRequestReadyAt,
      });
      pending.push(...accepted.map(({ requestID }) => ({ requestID })));
      finalFollowUpSlot = Math.max(
        finalFollowUpSlot,
        enqueueFollowUpReads(followUpSchedule, slot, accepted),
      );
    }
    await runFollowUpReadsForSlot({ measured, schedule: followUpSchedule, slot });
    if ((slot - 1) % 3 === 0) {
      const listed = parseRefreshList((await measured("requestListPolls", "/v2/refresh-requests", {
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
      await measured("acknowledgements", `/v2/refresh-requests/${completion.requestID}`, { expectedStatus: 204, label: "manual acknowledgement", method: "DELETE", token: secrets.writeToken });
    }
    if ((slot - 1) % 60 === 0) await publish("heartbeatPublications");
  }
  for (let slot = planned.slots + 1; slot <= finalFollowUpSlot; slot += 1) {
    await waitForSlot(slot);
    await runFollowUpReadsForSlot({ measured, schedule: followUpSchedule, slot });
  }
  if (followUpSchedule.size !== 0) throw new HarnessFailure("Follow-up read schedule did not drain.");
  const completionTarget = sampleCompletionTarget(startedAt, finalFollowUpSlot);
  let remaining = sampleSlotDelayMilliseconds(completionTarget, performance.now());
  while (remaining > 0) {
    await delay(remaining);
    remaining = sampleSlotDelayMilliseconds(completionTarget, performance.now());
  }
  const elapsedMilliseconds = observedElapsedMilliseconds(startedAt, performance.now());

  validateSoakAccounting(planned, counts, latencies, responseBytes);
  const perOperation = Object.fromEntries([...latencies].map(([name, values]) => [name, { p50Milliseconds: percentile(values, 0.5), p95Milliseconds: percentile(values, 0.95) }]));
  const all = [...latencies.values()].flat();
  return {
    durationSeconds: SAMPLE_SECONDS,
    elapsedMilliseconds,
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
