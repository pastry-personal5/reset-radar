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
  parseErrorResponse,
  parseExpiryResponse,
  parsePublicationResponse,
  parseReaderList,
  parseRefreshList,
  parseRemoteOrigin,
  randomIdentifier,
  readHidden,
  relayRequest,
  SNAPSHOT_BODY_LIMIT,
  StatefulSyntheticReader,
  strongETag,
  validateSecretSet,
  validateSnapshotReadETag,
  withPasteboardCleared,
} from "./harness-core.mjs";

const sleep = (milliseconds) => new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

export async function runFiniteSmoke(originInput, secrets, fetchImplementation = fetch, advanceTime = sleep) {
  const origin = parseRemoteOrigin(originInput);
  const key = validateSecretSet(secrets);
  const ids = Array.from({ length: 4 }, () => randomIdentifier());
  let fourthToken;
  do { fourthToken = randomBytes(32).toString("base64url"); }
  while ([secrets.writeToken, secrets.adminToken, secrets.contentKey, ...secrets.readTokens].includes(fourthToken));
  const requestID = randomIdentifier();
  const publisherID = randomIdentifier(32);
  const call = (path, options) => relayRequest(fetchImplementation, origin, path, options);
  const callError = async (path, options, code) => {
    const response = await call(path, options);
    parseErrorResponse(response.text, code);
    return response;
  };

  await call("/v1/relay", { expectedStatus: 204, label: "initial destruction", method: "DELETE", token: secrets.adminToken });
  await call("/v1/readers", { expectedStatus: 200, label: "administration authority preflight", token: secrets.adminToken });
  await call("/v1/refresh-requests", { expectedStatus: 200, label: "write authority preflight", token: secrets.writeToken });
  const crossoverEnvelope = canonicalJSON(createSyntheticEnvelope(1, { key, publisherID }).envelope);
  await callError("/v1/snapshot", { body: crossoverEnvelope, expectedStatus: 401, label: "admin-to-write crossover", method: "PUT", token: secrets.adminToken }, "unauthorized");
  await callError("/v1/readers", { expectedStatus: 401, label: "write-to-admin crossover", token: secrets.writeToken }, "unauthorized");
  await callError("/v1/snapshot", { body: crossoverEnvelope, expectedStatus: 401, label: "read-to-write crossover", method: "PUT", token: secrets.readTokens[0] }, "unauthorized");

  for (let index = 0; index < 3; index += 1) {
    parseExpiryResponse((await call(`/v1/readers/${ids[index]}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(secrets.readTokens[index]) }), expectedStatus: 200, label: "reader registration", method: "PUT", token: secrets.adminToken })).text);
  }
  await callError(`/v1/readers/${ids[3]}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(fourthToken) }), expectedStatus: 409, label: "reader cap", method: "PUT", token: secrets.adminToken }, "readerCapReached");
  await callError("/v1/snapshot", { expectedStatus: 404, label: "preflight read", token: secrets.readTokens[0] }, "awaitingFirstPublish");
  let readers = parseReaderList((await call("/v1/readers", { expectedStatus: 200, label: "pending readers", token: secrets.adminToken })).text);
  if (readers.length !== 3 || readers.some((reader) => reader.activated) ||
      readers.some((reader) => !ids.slice(0, 3).includes(reader.readerID))) {
    throw new HarnessFailure("Preflight or simulated local-save failure produced invalid pending readers.");
  }

  parseActivationResponse((await call("/v1/readers/activate", { expectedStatus: 200, label: "reader activation", method: "POST", token: secrets.readTokens[0] })).text);
  parseActivationResponse((await call("/v1/readers/activate", { expectedStatus: 200, label: "lost-response activation retry", method: "POST", token: secrets.readTokens[0] })).text);
  parseActivationResponse((await call("/v1/readers/activate", { expectedStatus: 200, label: "reader activation", method: "POST", token: secrets.readTokens[1] })).text);
  await advanceTime(5 * 60 * 1000 + 1);
  readers = parseReaderList((await call("/v1/readers", { expectedStatus: 200, label: "pending expiry", token: secrets.adminToken })).text);
  if (readers.length !== 2 || readers.some((reader) => !reader.activated) ||
      readers.some((reader) => !ids.slice(0, 2).includes(reader.readerID))) {
    throw new HarnessFailure("Pending reader did not expire by wall clock.");
  }
  await callError("/v1/readers/activate", { expectedStatus: 401, label: "expired reader", method: "POST", token: secrets.readTokens[2] }, "unauthorized");
  parseExpiryResponse((await call(`/v1/readers/${ids[2]}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(secrets.readTokens[2]) }), expectedStatus: 200, label: "reader re-registration", method: "PUT", token: secrets.adminToken })).text);
  parseActivationResponse((await call("/v1/readers/activate", { expectedStatus: 200, label: "reader activation", method: "POST", token: secrets.readTokens[2] })).text);

  const first = createSyntheticEnvelope(1, { key, publisherID });
  const firstText = canonicalJSON(first.envelope);
  const publication = await call("/v1/snapshot", { body: firstText, expectedStatus: 200, label: "snapshot publication", method: "PUT", token: secrets.writeToken });
  parsePublicationResponse(publication.text, 1);
  const etag = publication.headers.get("ETag");
  if (etag !== strongETag(firstText)) throw new HarnessFailure("Snapshot publication lacked the expected strong ETag.");
  const read = await call("/v1/snapshot", { bodyLimit: SNAPSHOT_BODY_LIMIT, expectedStatus: 200, label: "snapshot read", token: secrets.readTokens[0] });
  validateSnapshotReadETag(read.text, read.headers.get("ETag"), etag);
  const reader = new StatefulSyntheticReader({ key, publisherID });
  reader.commit(read.text);
  await call("/v1/snapshot", { expectedStatus: 304, headers: { "If-None-Match": etag }, label: "conditional read", token: secrets.readTokens[0] });
  await callError("/v1/snapshot", { body: firstText, expectedStatus: 409, label: "sequence replay", method: "PUT", token: secrets.writeToken }, "sequenceConflict");
  await callError("/v1/snapshot", { body: canonicalJSON(createSyntheticEnvelope(2, { key, publisherID: randomIdentifier(32) }).envelope), expectedStatus: 409, label: "publisher mismatch", method: "PUT", token: secrets.writeToken }, "publisherMismatch");

  const refreshBody = canonicalJSON({ protocolVersion: 1, requestID });
  parseExpiryResponse((await call("/v1/refresh-requests", { body: refreshBody, expectedStatus: 202, label: "refresh request", method: "POST", token: secrets.readTokens[0] })).text);
  const listedOnce = (await call("/v1/refresh-requests", { expectedStatus: 200, label: "refresh poll", token: secrets.writeToken })).text;
  const listedTwice = (await call("/v1/refresh-requests", { expectedStatus: 200, label: "non-consuming refresh poll", token: secrets.writeToken })).text;
  const requests = parseRefreshList(listedOnce);
  parseRefreshList(listedTwice);
  if (listedOnce !== listedTwice || requests.length !== 1 || requests[0].requestID !== requestID) {
    throw new HarnessFailure("Refresh poll consumed or mismatched the request.");
  }
  const result = createSyntheticEnvelope(2, { key, publisherID, requestID });
  parsePublicationResponse((await call("/v1/snapshot", { body: canonicalJSON(result.envelope), expectedStatus: 200, label: "manual result publication", method: "PUT", token: secrets.writeToken })).text, 2);
  const resultRead = await call("/v1/snapshot", { bodyLimit: SNAPSHOT_BODY_LIMIT, expectedStatus: 200, label: "manual result read", token: secrets.readTokens[0] });
  reader.commit(resultRead.text);
  if (reader.cache?.requestID !== requestID) throw new HarnessFailure("Manual result did not match its request.");
  await call(`/v1/refresh-requests/${requestID}`, { expectedStatus: 204, label: "refresh acknowledgement", method: "DELETE", token: secrets.writeToken });
  await callError("/v1/refresh-requests", { body: refreshBody, expectedStatus: 409, label: "completed request replay", method: "POST", token: secrets.readTokens[0] }, "requestAlreadyCompleted");
  await callError("/v1/refresh-requests", { body: canonicalJSON({ protocolVersion: 1, requestID: randomIdentifier() }), expectedStatus: 429, label: "refresh rate limit", method: "POST", token: secrets.readTokens[0] }, "requestRateLimited");

  await call(`/v1/readers/${ids[0]}`, { expectedStatus: 204, label: "reader revocation", method: "DELETE", token: secrets.adminToken });
  await callError("/v1/snapshot", { expectedStatus: 401, label: "revoked reader", token: secrets.readTokens[0] }, "unauthorized");
  await call("/v1/relay", { expectedStatus: 204, label: "destruction", method: "DELETE", token: secrets.adminToken });
  await call("/v1/relay", { expectedStatus: 204, label: "idempotent destruction", method: "DELETE", token: secrets.adminToken });
  const emptyReaders = parseReaderList((await call("/v1/readers", { expectedStatus: 200, label: "empty state", token: secrets.adminToken })).text);
  if (emptyReaders.length !== 0) throw new HarnessFailure("Relay destruction left active readers.");
  return { operations: 10, passed: true };
}

async function main() {
  if (process.argv.length !== 3) throw new HarnessFailure("Pass only the canonical workers.dev origin.");
  const secrets = await withPasteboardCleared(async () => ({
    writeToken: await readHidden("Synthetic write token"),
    adminToken: await readHidden("Synthetic administration token"),
    contentKey: await readHidden("Synthetic content key"),
    readTokens: [
      await readHidden("Synthetic reader 1 token"),
      await readHidden("Synthetic reader 2 token"),
      await readHidden("Synthetic reader 3 token"),
    ],
  }));
  await runFiniteSmoke(process.argv[2], secrets);
  process.stdout.write('{"operationCount":10,"result":"pass"}\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof HarnessFailure ? error.message : "Remote smoke failed."}\n`);
    process.exitCode = 1;
  });
}
