#!/usr/bin/env node

import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";

import { canonicalJSON, digest, HarnessFailure, parseErrorResponse, parseExpiryResponse, parseReaderList, parseRefreshList, parseRemoteOrigin, randomIdentifier, readHidden, relayRequest, validateDistinctSecrets, withPasteboardCleared } from "./harness-core.mjs";

export async function destroyRemote(originInput, { adminToken, writeToken }, fetchImplementation = fetch) {
  const origin = parseRemoteOrigin(originInput);
  validateDistinctSecrets([adminToken, writeToken]);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await relayRequest(fetchImplementation, origin, "/v1/relay", { expectedStatus: 204, label: "relay destruction", method: "DELETE", token: adminToken });
  }
  const requests = parseRefreshList((await relayRequest(fetchImplementation, origin, "/v2/refresh-requests", { expectedStatus: 200, label: "empty request state", token: writeToken })).text);
  if (requests.length !== 0) throw new HarnessFailure("Relay destruction left active requests.");
  const probeID = randomIdentifier();
  let probeToken;
  do { probeToken = randomBytes(32).toString("base64url"); }
  while ([adminToken, writeToken].includes(probeToken));
  parseExpiryResponse((await relayRequest(fetchImplementation, origin, `/v1/readers/${probeID}`, { body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(probeToken) }), expectedStatus: 200, label: "empty snapshot probe registration", method: "PUT", token: adminToken })).text);
  parseErrorResponse((await relayRequest(fetchImplementation, origin, "/v1/snapshot", { expectedStatus: 404, label: "empty snapshot probe", token: probeToken })).text, "awaitingFirstPublish");
  await relayRequest(fetchImplementation, origin, "/v1/relay", { expectedStatus: 204, label: "final probe cleanup", method: "DELETE", token: adminToken });
  const readers = parseReaderList((await relayRequest(fetchImplementation, origin, "/v1/readers", { expectedStatus: 200, label: "empty reader state", token: adminToken })).text);
  if (readers.length !== 0) throw new HarnessFailure("Relay destruction left active readers.");
  await relayRequest(fetchImplementation, origin, "/v1/relay", { expectedStatus: 204, label: "final storage deletion", method: "DELETE", token: adminToken });
  return { activeReaders: 0, activeRequests: 0, passed: true };
}

async function main() {
  if (process.argv.length !== 3) throw new HarnessFailure("Pass only the canonical workers.dev origin.");
  const { adminToken, writeToken } = await withPasteboardCleared(async () => ({
    adminToken: await readHidden("Synthetic administration token"),
    writeToken: await readHidden("Synthetic write token"),
  }));
  const result = await destroyRemote(process.argv[2], { adminToken, writeToken });
  process.stdout.write(`${JSON.stringify({ activeReaders: result.activeReaders, activeRequests: result.activeRequests, result: "pass" })}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof HarnessFailure ? error.message : "Remote destruction failed."}\n`);
    process.exitCode = 1;
  });
}
