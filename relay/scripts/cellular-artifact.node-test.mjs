import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { CELLULAR_PUBLISHER_ID, CELLULAR_READER_ID, prepareCellular } from "./cellular-prepare.mjs";
import { decryptSyntheticEnvelope, parseCanonicalResponse } from "./harness-core.mjs";

test("Scriptable cellular artifact is synthetic, bounded, and non-persistent", async () => {
  const source = await readFile(new URL("cellular-scriptable.js", import.meta.url), "utf8");
  for (const required of [
    "window.crypto.subtle",
    "value.map(canonical)",
    "encode(bytes) !== value",
    "decode(envelope.nonce, 12)",
    "decode(envelope.tag, 16)",
    'const plaintextKeys = ["observedAt", "synthetic", "value"]',
    "request.onRedirect = () => null",
    "bytes > 65_536",
    'Pasteboard.copyString("")',
    'addSecureTextField("Reader token")',
    'addSecureTextField("Content key")',
    "commitSyntheticCache",
    'request.method = "POST"',
    'data.toRawString() !== "{\\"activated\\":true,\\"protocolVersion\\":1}"',
    'result.title = "PASS"',
    'result.title = "FAIL"',
  ]) assert.ok(source.includes(required), `missing cellular safeguard: ${required}`);
  for (const forbidden of ["Keychain.set", "FileManager", "console.log", "log(", "http://"]) {
    assert.equal(source.includes(forbidden), false, `forbidden cellular behavior: ${forbidden}`);
  }
});

test("cellular preparation resets, registers, and publishes the fixed synthetic profile", async () => {
  const encoded = (byte) => Buffer.alloc(32, byte).toString("base64url");
  const secrets = {
    adminToken: encoded(1),
    contentKey: encoded(2),
    readToken: encoded(3),
    writeToken: encoded(4),
  };
  const requests = [];
  const mockFetch = async (url, init) => {
    requests.push({
      authorization: new Headers(init.headers).get("Authorization"),
      body: init.body,
      method: init.method,
      path: new URL(url).pathname,
    });
    const responseBodies = {
      "/v1/snapshot": '{"protocolVersion":1,"sequence":1}',
      [`/v1/readers/${CELLULAR_READER_ID}`]: '{"expiresAt":"2023-11-14T22:18:20.000Z","protocolVersion":1}',
    };
    const body = init.method === "DELETE" ? null : responseBodies[new URL(url).pathname];
    return new Response(body, {
      headers: body ? { "Content-Type": "application/json" } : undefined,
      status: init.method === "DELETE" ? 204 : 200,
    });
  };

  assert.deepEqual(await prepareCellular("https://reset.example.workers.dev", secrets, mockFetch), { result: "pass" });
  assert.deepEqual(requests.map(({ method, path }) => ({ method, path })), [
    { method: "DELETE", path: "/v1/relay" },
    { method: "PUT", path: `/v1/readers/${CELLULAR_READER_ID}` },
    { method: "PUT", path: "/v1/snapshot" },
  ]);
  assert.deepEqual(requests.map(({ authorization }) => authorization), [
    `Bearer ${secrets.adminToken}`,
    `Bearer ${secrets.adminToken}`,
    `Bearer ${secrets.writeToken}`,
  ]);
  const envelope = parseCanonicalResponse(requests[2].body);
  const plaintext = parseCanonicalResponse(
    decryptSyntheticEnvelope(envelope, Buffer.from(secrets.contentKey, "base64url")),
  );
  assert.equal(envelope.publisherID, CELLULAR_PUBLISHER_ID);
  assert.equal(envelope.sequence, 1);
  assert.equal(plaintext.synthetic, true);
  assert.equal(plaintext.value, 1);
});
