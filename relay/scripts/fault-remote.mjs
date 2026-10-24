#!/usr/bin/env node

import { randomBytes } from "node:crypto";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  canonicalJSON,
  createSyntheticEnvelope,
  digest,
  HarnessFailure,
  parseActivationResponse,
  parseCanonicalResponse,
  parseErrorResponse,
  parseExpiryResponse,
  parsePublicationResponse,
  parseRefreshList,
  parseRemoteOrigin,
  randomIdentifier,
  readHidden,
  relayRequest,
  SNAPSHOT_BODY_LIMIT,
  StatefulSyntheticReader,
  validateSecretSet,
  withPasteboardCleared,
} from "./harness-core.mjs";

const sleep = (milliseconds) => new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

export function runClientFaultCases() {
  const now = Date.now();
  const key = randomBytes(32);
  const publisherID = randomIdentifier(32);
  const reader = new StatefulSyntheticReader({ key, now: () => now, publisherID });
  const baseline = createSyntheticEnvelope(1, { key, observedAt: new Date(now).toISOString(), publisherID });
  reader.ingest({ kind: "snapshot", text: canonicalJSON(baseline.envelope) });
  const original = structuredClone(reader.cache);
  const validNext = createSyntheticEnvelope(2, { key, observedAt: new Date(now).toISOString(), publisherID });
  const candidates = [
    canonicalJSON({ ...validNext.envelope, ciphertext: "not_base64url!" }),
    canonicalJSON(createSyntheticEnvelope(2, { key: randomBytes(32), observedAt: new Date(now).toISOString(), publisherID }).envelope),
    canonicalJSON({ ...validNext.envelope, tag: `${validNext.envelope.tag.startsWith("A") ? "B" : "A"}${validNext.envelope.tag.slice(1)}` }),
    canonicalJSON(baseline.envelope),
    canonicalJSON(createSyntheticEnvelope(2, { key, observedAt: new Date(now + 5 * 60 * 1000 + 1).toISOString(), publisherID }).envelope),
    canonicalJSON({ ...validNext.envelope, protocolVersion: 2 }),
  ];
  for (const candidate of candidates) {
    try { reader.ingest({ kind: "snapshot", text: candidate }); } catch { /* expected */ }
    if (JSON.stringify(reader.cache) !== JSON.stringify(original)) throw new HarnessFailure("A client fault replaced the last valid cache.");
  }
  for (const outcome of ["rateLimited", "quotaLimited", "offline"]) {
    reader.ingest({ kind: "failure", outcome });
    if (JSON.stringify(reader.cache) !== JSON.stringify(original)) throw new HarnessFailure("A relay failure replaced the last valid cache.");
  }
  return {
    cacheSequenceAfter: reader.cache.sequence,
    cacheSequenceBefore: original.sequence,
    cases: 9,
    passed: true,
  };
}

export async function runRemoteFaultCases(originInput, secrets, fetchImplementation = fetch, wait = sleep) {
  const origin = parseRemoteOrigin(originInput);
  const key = validateSecretSet(secrets);
  const call = (path, options) => relayRequest(fetchImplementation, origin, path, options);
  const callError = async (path, options, code) => {
    const response = await call(path, options);
    parseErrorResponse(response.text, code);
    return response;
  };
  const readerIDs = secrets.readTokens.map(() => randomIdentifier());
  await call("/v1/relay", { expectedStatus: 204, label: "fault reset", method: "DELETE", token: secrets.adminToken });
  for (let index = 0; index < 3; index += 1) {
    parseExpiryResponse((await call(`/v1/readers/${readerIDs[index]}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(secrets.readTokens[index]) }), expectedStatus: 200, label: "fault reader registration", method: "PUT", token: secrets.adminToken })).text);
    parseActivationResponse((await call("/v1/readers/activate", { expectedStatus: 200, label: "fault reader activation", method: "POST", token: secrets.readTokens[index] })).text);
  }
  const baseline = createSyntheticEnvelope(1, { key, publisherID: randomIdentifier(32) });
  parsePublicationResponse((await call("/v1/snapshot", { body: canonicalJSON(baseline.envelope), expectedStatus: 200, label: "fault baseline publication", method: "PUT", token: secrets.writeToken })).text, 1);
  const initialRead = await call("/v1/snapshot", { bodyLimit: SNAPSHOT_BODY_LIMIT, expectedStatus: 200, label: "fault baseline", token: secrets.readTokens[0] });
  const initialEnvelope = parseCanonicalResponse(initialRead.text);
  const baselineSequence = initialEnvelope.sequence;

  const requestID = randomIdentifier();
  parseExpiryResponse((await call("/v2/refresh-requests", { body: canonicalJSON({ protocolVersion: 2, requestID, target: "allCodex" }), expectedStatus: 202, label: "mid-request revocation setup", method: "POST", token: secrets.readTokens[0] })).text, 2);
  await call(`/v1/readers/${readerIDs[0]}`, { expectedStatus: 204, label: "mid-request revocation", method: "DELETE", token: secrets.adminToken });
  await callError("/v1/snapshot", { expectedStatus: 401, label: "revoked read", token: secrets.readTokens[0] }, "unauthorized");
  const afterRevocation = parseRefreshList((await call("/v2/refresh-requests", { expectedStatus: 200, label: "revoked request cleanup", token: secrets.writeToken })).text);
  if (afterRevocation.some((request) => request.requestID === requestID)) throw new HarnessFailure("Reader revocation left its request live.");

  await wait(61_000);
  const offlineRequestID = randomIdentifier();
  parseExpiryResponse((await call("/v2/refresh-requests", { body: canonicalJSON({ protocolVersion: 2, requestID: offlineRequestID, target: "allCodex" }), expectedStatus: 202, label: "offline Mac request", method: "POST", token: secrets.readTokens[1] })).text, 2);
  await wait(61_000);
  const afterExpiry = parseRefreshList((await call("/v2/refresh-requests", { expectedStatus: 200, label: "request expiry", token: secrets.writeToken })).text);
  if (afterExpiry.some((request) => request.requestID === offlineRequestID)) throw new HarnessFailure("Expired offline-Mac request remained live.");

  const sourceFailureID = randomIdentifier();
  parseExpiryResponse((await call("/v2/refresh-requests", { body: canonicalJSON({ protocolVersion: 2, requestID: sourceFailureID, target: "allCodex" }), expectedStatus: 202, label: "source failure request", method: "POST", token: secrets.readTokens[2] })).text, 2);
  await wait(61_000);
  const afterSourceFailure = parseRefreshList((await call("/v2/refresh-requests", { expectedStatus: 200, label: "source failure expiry", token: secrets.writeToken })).text);
  if (afterSourceFailure.some((request) => request.requestID === sourceFailureID)) throw new HarnessFailure("Source failure request did not expire.");

  await callError("/v1/snapshot", { body: initialRead.text, expectedStatus: 409, label: "publication failure", method: "PUT", token: secrets.writeToken }, "sequenceConflict");
  const afterFailure = parseCanonicalResponse((await call("/v1/snapshot", { bodyLimit: SNAPSHOT_BODY_LIMIT, expectedStatus: 200, label: "cache after publication failure", token: secrets.readTokens[1] })).text);
  if (afterFailure.sequence !== baselineSequence) throw new HarnessFailure("Publication failure changed the snapshot.");

  const replacementID = randomIdentifier();
  let replacementToken;
  do { replacementToken = randomBytes(32).toString("base64url"); }
  while ([secrets.writeToken, secrets.adminToken, secrets.contentKey, ...secrets.readTokens].includes(replacementToken));
  parseExpiryResponse((await call(`/v1/readers/${replacementID}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(replacementToken) }), expectedStatus: 200, label: "replacement token registration", method: "PUT", token: secrets.adminToken })).text);
  parseActivationResponse((await call("/v1/readers/activate", { expectedStatus: 200, label: "replacement token activation", method: "POST", token: replacementToken })).text);
  await call("/v1/snapshot", { bodyLimit: SNAPSHOT_BODY_LIMIT, expectedStatus: 200, label: "replacement token read", token: replacementToken });

  await call("/v1/relay", { expectedStatus: 204, label: "destroy for re-pair", method: "DELETE", token: secrets.adminToken });
  const repairedID = randomIdentifier();
  parseExpiryResponse((await call(`/v1/readers/${repairedID}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(secrets.readTokens[2]) }), expectedStatus: 200, label: "re-pair registration", method: "PUT", token: secrets.adminToken })).text);
  parseActivationResponse((await call("/v1/readers/activate", { expectedStatus: 200, label: "re-pair activation", method: "POST", token: secrets.readTokens[2] })).text);
  const repaired = createSyntheticEnvelope(1, { key, publisherID: randomIdentifier(32) });
  parsePublicationResponse((await call("/v1/snapshot", { body: canonicalJSON(repaired.envelope), expectedStatus: 200, label: "re-pair publication", method: "PUT", token: secrets.writeToken })).text, 1);
  await call("/v1/snapshot", { bodyLimit: SNAPSHOT_BODY_LIMIT, expectedStatus: 200, label: "re-pair read", token: secrets.readTokens[2] });
  return { baselineSequence, passed: true, remoteCases: 7 };
}

async function main() {
  if (process.argv.length !== 3) throw new HarnessFailure("Pass only the canonical workers.dev origin.");
  const secrets = await withPasteboardCleared(async () => ({
    writeToken: await readHidden("Synthetic write token"), adminToken: await readHidden("Synthetic administration token"),
    contentKey: await readHidden("Synthetic content key"),
    readTokens: [await readHidden("Synthetic reader 1 token"), await readHidden("Synthetic reader 2 token"), await readHidden("Synthetic reader 3 token")],
  }));
  const local = runClientFaultCases();
  const remote = await runRemoteFaultCases(process.argv[2], secrets);
  process.stdout.write(`${JSON.stringify({
    cacheSequenceAfter: local.cacheSequenceAfter,
    cacheSequenceBefore: local.cacheSequenceBefore,
    clientCases: local.cases,
    remoteCases: remote.remoteCases,
    result: "pass",
  })}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof HarnessFailure ? error.message : "Fault exercise failed."}\n`);
    process.exitCode = 1;
  });
}
