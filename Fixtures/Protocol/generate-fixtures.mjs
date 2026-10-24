// Synthetic golden bytes for the Swift Transport and TypeScript relay suites.
// Run with `node Fixtures/Protocol/generate-fixtures.mjs` after an approved wire change.
import { createCipheriv, createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
const canonical = (value) => JSON.stringify(value, function (_key, child) {
  if (child !== null && !Array.isArray(child) && typeof child === "object") {
    return Object.fromEntries(Object.keys(child).sort().map((key) => [key, child[key]]));
  }
  return child;
});
const hex = (byte, count) => Buffer.alloc(count, byte).toString("hex");
const key = Buffer.alloc(32, 0x67);
const nonce = Buffer.alloc(12, 0xab);
const header = {
  protocolVersion: 1, envelopeVersion: 1, publisherID: hex(0x23, 32),
  sequence: 7, keyVersion: 1,
};
const snapshot = {
  schemaVersion: 2, publisherID: header.publisherID,
  generatedAt: "2023-11-14T22:13:20.000Z", heartbeatSeconds: 60,
  accounts: [], sources: [], windows: [], diagnostics: [], manualRefreshResults: [],
};
const headerJSON = canonical(header);
const plaintextJSON = canonical(snapshot);
const cipher = createCipheriv("aes-256-gcm", key, nonce);
cipher.setAAD(Buffer.from(headerJSON));
const ciphertext = Buffer.concat([cipher.update(plaintextJSON, "utf8"), cipher.final()]);
const outerJSON = canonical({
  ...header, nonce: nonce.toString("base64url"),
  ciphertext: ciphertext.toString("base64url"), tag: cipher.getAuthTag().toString("base64url"),
});
const etag = `"${createHash("sha256").update(outerJSON).digest("hex")}"`;
const packageJSON = canonical({
  schemaVersion: 1, relayEndpoint: "https://reset.example.workers.dev",
  readerID: hex(0x45, 16), readToken: Buffer.alloc(32, 0x89).toString("base64"),
  contentKey: key.toString("base64"), publisherID: header.publisherID,
  keyVersion: 1, minimumSequence: 7,
  registrationExpiresAt: "2023-11-14T22:18:20.000Z",
});
const encoded = Buffer.from(packageJSON).toString("base64url");
const confirmationHex = createHash("sha256").update(encoded).digest("hex").slice(0, 16);
const confirmationCode = confirmationHex.match(/.{4}/g).join("-");
const output = (filename, value) => {
  writeFileSync(join(root, filename), `${JSON.stringify(value, null, 2)}\n`);
};
output("envelope.json", {
  keyHex: key.toString("hex"), nonceHex: nonce.toString("hex"), headerJSON,
  plaintextJSON, outerJSON, etag,
});
output("pairing.json", { packageJSON, encoded, confirmationCode });

const requestID = hex(0x56, 16);
const readerID = hex(0x45, 16);
const expiry = "2023-11-14T22:18:20.000Z";
const digest = createHash("sha256").update(Buffer.alloc(32, 0x89)).digest("hex");
const operations = [
  ["snapshot-put", "PUT", "/v1/snapshot", "write", outerJSON, 200,
    canonical({ protocolVersion: 1, sequence: 7 }), etag],
  ["snapshot-get", "GET", "/v1/snapshot", "read", "", 200, outerJSON, etag],
  ["reader-activate", "POST", "/v1/readers/activate", "read", "", 200,
    canonical({ activated: true, protocolVersion: 1 }), null],
  ["refresh-post", "POST", "/v2/refresh-requests", "read",
    canonical({ protocolVersion: 2, requestID, target: "allCodex" }), 202,
    canonical({ expiresAt: expiry, protocolVersion: 2 }), null],
  ["refresh-list", "GET", "/v2/refresh-requests", "write", "", 200,
    canonical({ protocolVersion: 2,
      requests: [{ expiresAt: expiry, readerID, requestID, target: "allCodex" }] }), null],
  ["refresh-delete", "DELETE", `/v2/refresh-requests/${requestID}`, "write", "", 204, "", null],
  ["reader-register", "PUT", `/v1/readers/${readerID}`, "admin",
    canonical({ protocolVersion: 1, tokenDigest: digest }), 200,
    canonical({ expiresAt: expiry, protocolVersion: 1 }), null],
  ["reader-list", "GET", "/v1/readers", "admin", "", 200,
    canonical({ protocolVersion: 1, readers: [{ activated: true, readerID }] }), null],
  ["reader-revoke", "DELETE", `/v1/readers/${readerID}`, "admin", "", 204, "", null],
  ["relay-destroy", "DELETE", "/v1/relay", "admin", "", 204, "", null],
];
for (const [name, method, path, authority, requestBody, status, responseBody, responseETag]
  of operations) {
  output(`operation-${name}.json`, {
    method, path, authority, requestBody, status, responseBody, etag: responseETag,
  });
}

const errors = [
  [400, "badRequest"], [401, "unauthorized"], [404, "awaitingFirstPublish"],
  [404, "unknownRoute"], [409, "publisherMismatch"], [409, "sequenceConflict"],
  [409, "readerCapReached"], [409, "requestAlreadyCompleted"],
  [413, "payloadTooLarge"], [422, "unsupportedVersion"],
  [429, "requestRateLimited"], [429, "quotaLimited"],
];
for (const [status, code] of errors) {
  const filename = code.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
  output(`error-${filename}.json`, {
    status, code, body: canonical({ code, protocolVersion: 1 }),
  });
  output(`error-refresh-${filename}.json`, {
    status, code, body: canonical({ code, protocolVersion: 2 }),
  });
}

const badRequestBody = canonical({ code: "badRequest", protocolVersion: 1 });
const refreshBadRequestBody = canonical({ code: "badRequest", protocolVersion: 2 });
const completedBody = canonical({ code: "requestAlreadyCompleted", protocolVersion: 2 });
const registration = canonical({ protocolVersion: 1, tokenDigest: digest });
const refresh = canonical({ protocolVersion: 2, requestID, target: "allCodex" });
const scenarios = {
  "reader-retry": ["registerReader", 200, registration,
    canonical({ expiresAt: expiry, protocolVersion: 1 })],
  "reader-changed-digest": ["registerReader", 400,
    canonical({ protocolVersion: 1,
      tokenDigest: createHash("sha256").update(Buffer.alloc(32, 0x88)).digest("hex") }),
    badRequestBody],
  "reader-reused-digest": ["registerReader", 400, registration, badRequestBody],
  "reader-privileged-digest": ["registerReader", 400,
    canonical({ protocolVersion: 1,
      tokenDigest: createHash("sha256").update(Buffer.alloc(32, 0x11)).digest("hex") }),
    badRequestBody],
  "refresh-expired-id": ["postRefreshRequest", 400, refresh, refreshBadRequestBody],
  "refresh-cross-reader-id": ["postRefreshRequest", 400, refresh, refreshBadRequestBody],
  "refresh-completed-id": ["postRefreshRequest", 409, refresh, completedBody],
  "sequence-overflow": ["putSnapshot", 400,
    outerJSON.replace('"sequence":7', '"sequence":9007199254740992'), badRequestBody],
};
for (const [name, [operation, status, requestBody, responseBody]] of Object.entries(scenarios)) {
  output(`scenario-${name}.json`, { operation, status, requestBody, responseBody });
}
