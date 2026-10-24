import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import test from "node:test";

import {
  canonicalJSON,
  clearPasteboard,
  createSyntheticEnvelope,
  DAILY_SLOTS,
  dailyWorkload,
  HarnessFailure,
  parseActivationResponse,
  parseErrorResponse,
  parseExpiryResponse,
  parsePublicationResponse,
  parseReaderList,
  parseRefreshList,
  parseRemoteOrigin,
  relayRequest,
  sampleWorkload,
  StatefulSyntheticReader,
  SLOT_SECONDS,
  strongETag,
  totalWorkload,
  validateSecretSet,
  validateSnapshotReadETag,
  withPasteboardCleared,
} from "./harness-core.mjs";
import { runClientFaultCases } from "./fault-remote.mjs";

test("remote origins are exact non-secret workers.dev HTTPS origins", () => {
  assert.equal(parseRemoteOrigin("https://relay.owner.workers.dev"), "https://relay.owner.workers.dev");
  for (const value of [
    "http://relay.owner.workers.dev", "https://user@relay.owner.workers.dev",
    "https://relay.owner.workers.dev:8443", "https://relay.owner.workers.dev/path",
    "https://relay.owner.workers.dev/?query=1", "https://relay.owner.workers.dev/#fragment",
    "https://example.com", "not a URL",
  ]) assert.throws(() => parseRemoteOrigin(value), HarnessFailure);
});

test("pasteboard clearing invokes pbcopy without arguments", async () => {
  let invocation;
  const spawnMock = (command, arguments_, options) => {
    invocation = { arguments_, command, options };
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdin.on("finish", () => queueMicrotask(() => child.emit("close", 0)));
    return child;
  };
  await clearPasteboard(spawnMock);
  assert.deepEqual(invocation.arguments_, []);
  assert.equal(invocation.command, "pbcopy");
  assert.deepEqual(invocation.options.stdio, ["pipe", "ignore", "ignore"]);
});

test("secret prompting clears the pasteboard on success and failure", async () => {
  let clears = 0;
  assert.equal(await withPasteboardCleared(async () => "ok", async () => { clears += 1; }), "ok");
  await assert.rejects(
    () => withPasteboardCleared(async () => { throw new Error("prompt failed"); }, async () => { clears += 1; }),
    /prompt failed/,
  );
  assert.equal(clears, 2);
});

test("canonical JSON recursively sorts object keys inside arrays", () => {
  assert.equal(canonicalJSON({ values: [{ z: 1, a: 2 }] }), '{"values":[{"a":2,"z":1}]}');
});

test("remote response parsers require exact canonical v1 shapes", () => {
  assert.deepEqual(parseActivationResponse('{"activated":true,"protocolVersion":1}'), {
    activated: true,
    protocolVersion: 1,
  });
  assert.equal(parsePublicationResponse('{"protocolVersion":1,"sequence":7}', 7).sequence, 7);
  assert.equal(parseExpiryResponse('{"expiresAt":"2023-11-14T22:18:20.000Z","protocolVersion":1}').protocolVersion, 1);
  assert.equal(parseErrorResponse('{"code":"unauthorized","protocolVersion":1}', "unauthorized").code, "unauthorized");
  assert.deepEqual(parseReaderList('{"protocolVersion":1,"readers":[]}'), []);
  assert.deepEqual(parseRefreshList('{"protocolVersion":1,"requests":[]}'), []);
  for (const action of [
    () => parseActivationResponse('{"activated":false,"protocolVersion":1}'),
    () => parsePublicationResponse('{"protocolVersion":1,"sequence":8}', 7),
    () => parseExpiryResponse('{"expiresAt":"2023-11-14T22:18:20Z","protocolVersion":1}'),
    () => parseErrorResponse('{"code":"badRequest","protocolVersion":1}', "unauthorized"),
    () => parseReaderList('{"protocolVersion":1,"readers":[{"activated":true,"readerID":"45454545454545454545454545454545"},{"activated":false,"readerID":"45454545454545454545454545454545"}]}'),
    () => parseRefreshList('{"protocolVersion":1,"requests":[{"expiresAt":"2023-11-14T22:18:20.000Z","readerID":"45454545454545454545454545454545","requestID":"56565656565656565656565656565656"},{"expiresAt":"2023-11-14T22:18:20.000Z","readerID":"45454545454545454545454545454545","requestID":"57575757575757575757575757575757"}]}'),
  ]) assert.throws(action, HarnessFailure);
});

test("bounded request rejects redirects, bad media, oversized and failing streams", async () => {
  const origin = "https://relay.owner.workers.dev";
  await assert.rejects(() => relayRequest(async () => new Response("", { status: 302 }), origin, "/v1/snapshot"), /redirect/);
  await assert.rejects(() => relayRequest(async () => new Response("{}", { status: 200 }), origin, "/v1/snapshot"), /media type/);
  await assert.rejects(() => relayRequest(async () => new Response("x".repeat(4097), { headers: { "Content-Type": "application/json" } }), origin, "/v1/snapshot"), /byte limit/);
  const failed = new ReadableStream({ pull(controller) { controller.error(new Error("secret shaped failure")); } });
  await assert.rejects(() => relayRequest(async () => new Response(failed, { headers: { "Content-Type": "application/json" } }), origin, "/v1/snapshot"), /stream failed/);
  await assert.rejects(
    () => relayRequest(
      async () => new Response(new Uint8Array([0xC3, 0x28]), { headers: { "Content-Type": "application/json" } }),
      origin,
      "/v1/snapshot",
    ),
    /invalid UTF-8/,
  );
  await assert.rejects(
    () => relayRequest(
      async () => new Response(new ReadableStream({ pull() {} })),
      origin,
      "/v1/snapshot",
      { timeoutMs: 5 },
    ),
    /timed out/,
  );
  await assert.rejects(() => relayRequest(async () => new Response(), origin, "/v1/unreviewed"), /Unreviewed/);
  const accepted = await relayRequest(async (_url, init) => {
    const headers = new Headers(init.headers);
    assert.equal(headers.get("Accept"), "application/json");
    assert.equal(headers.get("Authorization"), null);
    return new Response("{}", { headers: { "Content-Type": "application/json; charset=utf-8" } });
  }, origin, "/v1/snapshot", { expectedStatus: 200, headers: { Authorization: "Bearer unreviewed" } });
  assert.equal(accepted.text, "{}");
});

test("unexpected status reports only safe numeric status metadata", async () => {
  const privateBody = '{"code":"unauthorized","private":"must-not-escape"}';
  await assert.rejects(
    () => relayRequest(
      async () => new Response(privateBody, { headers: { "Content-Type": "text/html" }, status: 401 }),
      "https://relay.owner.workers.dev",
      "/v1/relay",
      { expectedStatus: 204, label: "relay destruction", method: "DELETE" },
    ),
    (error) => {
      assert.equal(error.message, "relay destruction returned HTTP 401; expected 204.");
      assert.equal(error.message.includes(privateBody), false);
      assert.equal(error.message.includes("must-not-escape"), false);
      return true;
    },
  );
});

test("snapshot ETag validation distinguishes header transformation from body mutation", () => {
  const body = '{"protocolVersion":1}';
  const etag = strongETag(body);
  assert.doesNotThrow(() => validateSnapshotReadETag(body, etag, etag));
  assert.throws(
    () => validateSnapshotReadETag(body, `W/${etag}`, etag),
    /ETag header was transformed/,
  );
  assert.throws(
    () => validateSnapshotReadETag(`${body} `, etag, etag),
    /body changed under its strong ETag/,
  );
});

test("stateful reader commits only authenticated newer compatible envelopes", () => {
  const key = randomBytes(32);
  const publisherID = "23".repeat(32);
  const first = createSyntheticEnvelope(1, { key, publisherID });
  const second = createSyntheticEnvelope(2, { key, publisherID });
  const reader = new StatefulSyntheticReader({ key, publisherID });
  reader.commit(canonicalJSON(first.envelope));
  const cache = reader.cache;
  const failures = [
    canonicalJSON(first.envelope),
    canonicalJSON({ ...second.envelope, publisherID: "45".repeat(32) }),
    canonicalJSON({ ...second.envelope, protocolVersion: 2 }),
    canonicalJSON({ ...second.envelope, tag: `${second.envelope.tag.startsWith("A") ? "B" : "A"}${second.envelope.tag.slice(1)}` }),
    canonicalJSON({ ...second.envelope, extra: true }),
    canonicalJSON({ ...second.envelope, nonce: `${second.envelope.nonce}=` }),
    "{malformed",
  ];
  for (const candidate of failures) {
    assert.throws(() => reader.commit(candidate), HarnessFailure);
    assert.deepEqual(reader.cache, cache);
  }
  const wrongKeyReader = new StatefulSyntheticReader({ key: randomBytes(32), publisherID });
  assert.throws(() => wrongKeyReader.commit(canonicalJSON(second.envelope)), /authentication/);
  assert.equal(wrongKeyReader.cache, undefined);
  assert.throws(
    () => createSyntheticEnvelope(3, { key, observedAt: "2023-11-14T22:13:20Z", publisherID }),
    /input is invalid/,
  );
  reader.commit(canonicalJSON(second.envelope));
  assert.equal(reader.cache.sequence, 2);
  assert.equal(reader.ingest({ kind: "failure", outcome: "offline" }).sequence, 2);
  assert.equal(reader.cache.sequence, 2);
  assert.throws(() => reader.ingest({ kind: "failure", outcome: "unknown" }), HarnessFailure);
  assert.throws(() => reader.ingest({ kind: "snapshot", text: 42 }), HarnessFailure);
});

test("synthetic secret sets require the exact count, encoding, and uniqueness", () => {
  const value = (byte) => Buffer.alloc(32, byte).toString("base64url");
  const valid = {
    adminToken: value(1),
    contentKey: value(2),
    readTokens: [value(3), value(4), value(5)],
    writeToken: value(6),
  };
  assert.equal(validateSecretSet(valid).toString("base64url"), valid.contentKey);
  assert.throws(() => validateSecretSet({ ...valid, readTokens: valid.readTokens.slice(0, 2) }), /incomplete/);
  assert.throws(() => validateSecretSet({ ...valid, writeToken: valid.adminToken }), /distinct/);
  assert.throws(() => validateSecretSet({ ...valid, contentKey: "invalid" }), /valid/);
});

test("daily and 30-minute workload accounting is additive and pinned", () => {
  const daily = dailyWorkload();
  assert.deepEqual(daily, {
    acknowledgements: 4320,
    followUpReads: 43200,
    heartbeatPublications: 288,
    manualRequests: 4320,
    manualResultPublications: 2880,
    ordinaryPublications: 2880,
    ordinaryReads: 5790,
    requestListPolls: 5760,
    setupRequests: 7,
  });
  assert.equal(totalWorkload(daily), 69445);
  const sample = sampleWorkload();
  assert.deepEqual(sample, {
    acknowledgements: 60,
    followUpReads: 900,
    heartbeatPublications: 6,
    manualRequests: 90,
    manualResultPublications: 60,
    ordinaryPublications: 60,
    ordinaryReads: 120,
    requestListPolls: 119,
    setupRequests: 7,
    slots: 356,
  });
  assert.equal(totalWorkload(sample), 1422);
  assert.equal(DAILY_SLOTS, 17_280);
  assert.equal(SLOT_SECONDS, 5.05);
  assert.ok(12 * SLOT_SECONDS > 60);
});

test("all planned client faults preserve the last valid cache", () => {
  assert.deepEqual(runClientFaultCases(), {
    cacheSequenceAfter: 1,
    cacheSequenceBefore: 1,
    cases: 9,
    passed: true,
  });
});
