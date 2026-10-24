import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  HarnessFailure,
  canonicalJSON,
  createSyntheticEnvelope,
  digest,
  parseExpiryResponse,
  parsePublicationResponse,
  parseRemoteOrigin,
  readHidden,
  relayRequest,
  validateSecretSet,
  withPasteboardCleared,
} from "./harness-core.mjs";

export const CELLULAR_PUBLISHER_ID = "2323232323232323232323232323232323232323232323232323232323232323";
export const CELLULAR_READER_ID = "45454545454545454545454545454545";

export async function prepareCellular(originInput, secrets, fetchImplementation = fetch) {
  const origin = parseRemoteOrigin(originInput);
  const key = validateSecretSet({ ...secrets, readTokens: [secrets.readToken] }, 1);
  const call = (path, options) => relayRequest(fetchImplementation, origin, path, options);
  await call("/v1/relay", {
    expectedStatus: 204,
    label: "cellular reset",
    method: "DELETE",
    token: secrets.adminToken,
  });
  parseExpiryResponse((await call(`/v1/readers/${CELLULAR_READER_ID}`, {
    body: canonicalJSON({ protocolVersion: 1, tokenDigest: digest(secrets.readToken) }),
    expectedStatus: 200,
    label: "cellular reader registration",
    method: "PUT",
    token: secrets.adminToken,
  })).text);
  const synthetic = createSyntheticEnvelope(1, {
    key,
    publisherID: CELLULAR_PUBLISHER_ID,
  });
  parsePublicationResponse((await call("/v1/snapshot", {
    body: canonicalJSON(synthetic.envelope),
    expectedStatus: 200,
    label: "cellular snapshot publication",
    method: "PUT",
    token: secrets.writeToken,
  })).text, 1);
  return { result: "pass" };
}

async function main() {
  if (process.argv.length !== 3) throw new HarnessFailure("Pass only the canonical workers.dev origin.");
  const secrets = await withPasteboardCleared(async () => ({
    writeToken: await readHidden("Synthetic write token"),
    adminToken: await readHidden("Synthetic administration token"),
    contentKey: await readHidden("Synthetic content key"),
    readToken: await readHidden("Synthetic reader 1 token"),
  }));
  await prepareCellular(process.argv[2], secrets);
  process.stdout.write('{"result":"pass"}\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof HarnessFailure ? error.message : "Cellular preparation failed."}\n`);
    process.exitCode = 1;
  });
}
