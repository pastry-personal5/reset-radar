import { env, reset, runInDurableObject, SELF } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";

import worker, { type RelayObject } from "../src/index";
import { canonicalJSON } from "../src/domain/protocol";
import { runFiniteSmoke } from "../scripts/smoke-remote.mjs";

import envelope from "../../Fixtures/Protocol/envelope.json";
import errorAwaitingFirstPublish from "../../Fixtures/Protocol/error-awaiting-first-publish.json";
import errorBadRequest from "../../Fixtures/Protocol/error-bad-request.json";
import errorPayloadTooLarge from "../../Fixtures/Protocol/error-payload-too-large.json";
import errorReaderCapReached from "../../Fixtures/Protocol/error-reader-cap-reached.json";
import errorSequenceConflict from "../../Fixtures/Protocol/error-sequence-conflict.json";
import errorUnauthorized from "../../Fixtures/Protocol/error-unauthorized.json";
import errorUnknownRoute from "../../Fixtures/Protocol/error-unknown-route.json";
import errorUnsupportedVersion from "../../Fixtures/Protocol/error-unsupported-version.json";
import errorRefreshPayloadTooLarge from "../../Fixtures/Protocol/error-refresh-payload-too-large.json";
import errorRefreshRequestAlreadyCompleted from "../../Fixtures/Protocol/error-refresh-request-already-completed.json";
import errorRefreshRequestRateLimited from "../../Fixtures/Protocol/error-refresh-request-rate-limited.json";
import activate from "../../Fixtures/Protocol/operation-reader-activate.json";
import listReaders from "../../Fixtures/Protocol/operation-reader-list.json";
import registerReader from "../../Fixtures/Protocol/operation-reader-register.json";
import revokeReader from "../../Fixtures/Protocol/operation-reader-revoke.json";
import deleteRefresh from "../../Fixtures/Protocol/operation-refresh-delete.json";
import listRefresh from "../../Fixtures/Protocol/operation-refresh-list.json";
import postRefresh from "../../Fixtures/Protocol/operation-refresh-post.json";
import destroyRelay from "../../Fixtures/Protocol/operation-relay-destroy.json";
import getSnapshot from "../../Fixtures/Protocol/operation-snapshot-get.json";
import putSnapshot from "../../Fixtures/Protocol/operation-snapshot-put.json";
import overflowSequence from "../../Fixtures/Protocol/scenario-sequence-overflow.json";

const tokens = {
  admin: "IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI",
  reader: "iYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYk",
  readerTwo: "REREREREREREREREREREREREREREREREREREREREREQ",
  readerThree: "VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVU",
  writer: "ERERERERERERERERERERERERERERERERERERERERERE",
  wrong: "MzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzM",
};

const digests = {
  reader: "4c07be22f86c52fd94ac9b44b023583c4fd5180d193ff28491d2885653c2c81e",
  readerTwo: "bb391415c05e39d77ca17381d3be3f7d0cd5e5332e5a579311adaa0aa62106e9",
  readerThree: "84126d0dd850199be29021aadbaee68cb9199047b1cb7ec9894ddb1e3562783c",
  wrong: "deb0e38ced1e41de6f92e70e80c418d2d356afaaa99e26f5939dbc7d3ef4772a",
};

const readerOneID = "45454545454545454545454545454545";
const readerTwoID = "46464646464646464646464646464646";
const readerThreeID = "47474747474747474747474747474747";
const registrationStart = 1_700_000_000_000;
const refreshStart = 1_700_000_240_000;

afterEach(async () => { await reset(); });

function request(
  path: string,
  method: string,
  token?: string,
  body?: string,
  headers: HeadersInit = {},
): Promise<Response> {
  const requestHeaders = new Headers(headers);
  if (token !== undefined) requestHeaders.set("Authorization", `Bearer ${token}`);
  if (body !== undefined && !requestHeaders.has("Content-Type")) requestHeaders.set("Content-Type", "application/json");
  return SELF.fetch(`https://relay.invalid${path}`, { body, headers: requestHeaders, method });
}

async function register(id = readerOneID, digest = digests.reader): Promise<Response> {
  return request(`/v1/readers/${id}`, "PUT", tokens.admin,
    JSON.stringify({ protocolVersion: 1, tokenDigest: digest }));
}

async function activateReader(token = tokens.reader): Promise<Response> {
  return request("/v1/readers/activate", "POST", token);
}

async function setClock(milliseconds: number): Promise<void> {
  const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
  await runInDurableObject(stub, (instance: RelayObject) => {
    instance.setClockForTesting(milliseconds);
  });
}

async function objectStorage<T>(callback: (state: DurableObjectState) => T | Promise<T>): Promise<T> {
  const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
  return runInDurableObject(stub, (_instance, state) => callback(state));
}

function requestReplacingReaderOnBodyRead(path: string, body: string): Promise<Response> {
  const bytes = new TextEncoder().encode(body);
  const stream = new ReadableStream<Uint8Array>({
    async pull(controller) {
      expect((await request(`/v1/readers/${readerOneID}`, "DELETE", tokens.admin)).status).toBe(204);
      expect((await register(readerOneID, digests.readerTwo)).status).toBe(200);
      expect((await activateReader(tokens.readerTwo)).status).toBe(200);
      controller.enqueue(bytes);
      controller.close();
    },
  }, { highWaterMark: 0 });
  return SELF.fetch(new Request(`https://relay.invalid${path}`, {
    body: stream,
    headers: {
      Authorization: `Bearer ${tokens.reader}`,
      "Content-Type": "application/json",
    },
    method: path === "/v2/reader-profile" ? "PUT" : "POST",
  }));
}

describe("Relay Worker v1 snapshots and v2 refresh", () => {
  it("canonicalizes nested response objects recursively", () => {
    expect(canonicalJSON({ values: [{ z: 1, a: 2 }] })).toBe('{"values":[{"a":2,"z":1}]}');
  });

  it("treats destruction of fresh state as idempotent without creating a schema", async () => {
    const destroyed = await request(destroyRelay.path, destroyRelay.method, tokens.admin);
    expect(destroyed.status).toBe(204);
    expect(await destroyed.text()).toBe("");
    const tables = await objectStorage((state) => state.storage.sql.exec(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE '_cf_%'",
    ).toArray());
    expect(tables).toEqual([]);
  });

  it("runs the M9 finite smoke through the shipped Worker", async () => {
    await setClock(registrationStart);
    const result = await runFiniteSmoke(
      "https://relay.synthetic.workers.dev",
      {
        adminToken: tokens.admin,
        contentKey: "q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s",
        readTokens: [tokens.reader, tokens.readerTwo, tokens.readerThree],
        writeToken: tokens.writer,
      },
      (input, init) => SELF.fetch(input, init),
      async (milliseconds) => { await setClock(registrationStart + milliseconds); },
    );
    await setClock(registrationStart);
    expect(result).toEqual({ operations: 10, passed: true });
  });

  it("consumes the snapshot, reader, and activation fixtures byte-for-byte", async () => {
    await setClock(registrationStart);
    const registration = await request(registerReader.path, registerReader.method, tokens.admin, registerReader.requestBody);
    expect(registration.status).toBe(registerReader.status);
    expect(await registration.text()).toBe(registerReader.responseBody);

    const beforePublish = await request(getSnapshot.path, getSnapshot.method, tokens.reader);
    expect(beforePublish.status).toBe(errorAwaitingFirstPublish.status);
    expect(await beforePublish.text()).toBe(errorAwaitingFirstPublish.body);
    expect(beforePublish.headers.get("Cache-Control")).toBe("no-store, no-transform");
    const pending = JSON.parse(await (await request(listReaders.path, listReaders.method, tokens.admin)).text()) as {
      readers: Array<{ activated: boolean; readerID: string }>;
    };
    expect(pending.readers).toEqual([{ activated: false, readerID: readerOneID }]);

    const publication = await request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody);
    expect(publication.status).toBe(putSnapshot.status);
    expect(await publication.text()).toBe(putSnapshot.responseBody);
    expect(publication.headers.get("ETag")).toBe(putSnapshot.etag);

    const read = await request(getSnapshot.path, getSnapshot.method, tokens.reader);
    expect(read.status).toBe(getSnapshot.status);
    expect(await read.text()).toBe(getSnapshot.responseBody);
    expect(read.headers.get("ETag")).toBe(getSnapshot.etag);
    expect(read.headers.get("Cache-Control")).toBe("no-store, no-transform");

    const conditional = await request(getSnapshot.path, getSnapshot.method, tokens.reader, undefined, {
      "If-None-Match": envelope.etag,
    });
    expect(conditional.status).toBe(304);
    expect(await conditional.text()).toBe("");
    expect(conditional.headers.get("ETag")).toBe(envelope.etag);
    expect(conditional.headers.get("Cache-Control")).toBe("no-store, no-transform");

    const activation = await request(activate.path, activate.method, tokens.reader);
    expect(activation.status).toBe(activate.status);
    expect(await activation.text()).toBe(activate.responseBody);
    const activationRetry = await request(activate.path, activate.method, tokens.reader);
    expect(await activationRetry.text()).toBe(activate.responseBody);
    const readers = await request(listReaders.path, listReaders.method, tokens.admin);
    expect(readers.status).toBe(listReaders.status);
    expect(await readers.text()).toBe(listReaders.responseBody);
  });

  it("authenticates write and administration routes before accepting malformed data", async () => {
    const malformed = await request(putSnapshot.path, putSnapshot.method, tokens.wrong, "not-json");
    expect(malformed.status).toBe(errorUnauthorized.status);
    expect(await malformed.text()).toBe(errorUnauthorized.body);

    const writerAsAdmin = await request(registerReader.path, registerReader.method, tokens.writer, registerReader.requestBody);
    expect(writerAsAdmin.status).toBe(errorUnauthorized.status);
    const readerAsWriter = await request(putSnapshot.path, putSnapshot.method, tokens.reader, putSnapshot.requestBody);
    expect(readerAsWriter.status).toBe(errorUnauthorized.status);

    const unknown = await request("/v1/nope", "GET", tokens.writer);
    expect(unknown.status).toBe(errorUnknownRoute.status);
    expect(await unknown.text()).toBe(errorUnknownRoute.body);
  });

  it("does not materialize storage for an invalid reader token", async () => {
    const invalidRead = await request(getSnapshot.path, getSnapshot.method, tokens.wrong);
    expect(invalidRead.status).toBe(errorUnauthorized.status);
    expect(invalidRead.headers.get("Cache-Control")).toBe("no-store, no-transform");

    const tables = await objectStorage((state) => state.storage.sql.exec(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('relay_schema', 'relay_state', 'readers', 'refresh_requests')",
    ).toArray());
    expect(tables).toEqual([]);
  });

  it("revalidates a reader after the body read so a concurrent revocation cannot activate or enqueue", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    expect((await register(readerTwoID, digests.readerTwo)).status).toBe(200);

    const stalled = (token: string, path: string, body: string) => {
      let release!: () => void;
      const gate = new Promise<void>((resolve) => { release = resolve; });
      const stream = new ReadableStream<Uint8Array>({
        async pull(controller) {
          await gate;
          if (body.length > 0) controller.enqueue(new TextEncoder().encode(body));
          controller.close();
        },
      });
      const pending = SELF.fetch(`https://relay.invalid${path}`, {
        body: stream,
        duplex: "half",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        method: "POST",
      } as RequestInit);
      return { pending, release };
    };

    const activation = stalled(tokens.readerTwo, "/v1/readers/activate", "");
    const refresh = stalled(
      tokens.reader,
      postRefresh.path,
      JSON.stringify({
        protocolVersion: 2,
        requestID: "59595959595959595959595959595959",
        target: "allCodex",
      }),
    );
    await new Promise((resolve) => setTimeout(resolve, 50));
    for (const id of [readerOneID, readerTwoID]) {
      expect((await request(`/v1/readers/${id}`, "DELETE", tokens.admin)).status).toBe(204);
    }
    activation.release();
    refresh.release();

    expect((await activation.pending).status).toBe(401);
    expect((await refresh.pending).status).toBe(401);
    const rows = await objectStorage((state) => ({
      readers: state.storage.sql.exec("SELECT COUNT(*) AS n FROM readers").one().n,
      requests: state.storage.sql.exec("SELECT COUNT(*) AS n FROM refresh_requests").one().n,
    }));
    expect(rows).toEqual({ readers: 0, requests: 0 });
  });

  it("fails closed when Worker-secret digests are absent, malformed, or equal", async () => {
    const requestValue = new Request("https://relay.invalid/v1/snapshot", {
      body: putSnapshot.requestBody,
      headers: {
        Authorization: `Bearer ${tokens.writer}`,
        "Content-Type": "application/json",
      },
      method: "PUT",
    });
    for (const bindings of [
      {},
      { ADMIN_TOKEN_DIGEST: "invalid", WRITE_TOKEN_DIGEST: "invalid" },
      {
        ADMIN_TOKEN_DIGEST: "02d449a31fbb267c8f352e9968a79e3e5fc95c1bbeaa502fd6454ebde5a4bedc",
        WRITE_TOKEN_DIGEST: "02d449a31fbb267c8f352e9968a79e3e5fc95c1bbeaa502fd6454ebde5a4bedc",
      },
    ]) {
      const response = await worker.fetch(requestValue.clone(), bindings as Env);
      expect(response.status).toBe(errorUnauthorized.status);
      expect(await response.text()).toBe(errorUnauthorized.body);
    }
  });

  it("enforces canonical envelopes, size bounds, ordering, and publisher binding", async () => {
    const whitespace = await request(putSnapshot.path, putSnapshot.method, tokens.writer, ` ${putSnapshot.requestBody}`);
    expect(whitespace.status).toBe(errorBadRequest.status);
    expect(await whitespace.text()).toBe(errorBadRequest.body);

    const unsupported = await request(putSnapshot.path, putSnapshot.method, tokens.writer,
      putSnapshot.requestBody.replace("\"protocolVersion\":1", "\"protocolVersion\":2"));
    expect(unsupported.status).toBe(errorUnsupportedVersion.status);
    expect(await unsupported.text()).toBe(errorUnsupportedVersion.body);

    const overflow = await request(putSnapshot.path, putSnapshot.method, tokens.writer, overflowSequence.requestBody);
    expect(overflow.status).toBe(errorBadRequest.status);
    expect(await overflow.text()).toBe(errorBadRequest.body);

    const tooLarge = await request(putSnapshot.path, putSnapshot.method, tokens.writer, "x".repeat(64 * 1024 + 1));
    expect(tooLarge.status).toBe(errorPayloadTooLarge.status);
    expect(await tooLarge.text()).toBe(errorPayloadTooLarge.body);

    expect((await request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody)).status).toBe(200);
    const sameSequence = await request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody);
    expect(sameSequence.status).toBe(errorSequenceConflict.status);
    expect(await sameSequence.text()).toBe(errorSequenceConflict.body);

    const otherPublisher = await request(putSnapshot.path, putSnapshot.method, tokens.writer,
      putSnapshot.requestBody.replaceAll("2323232323232323232323232323232323232323232323232323232323232323", "2424242424242424242424242424242424242424242424242424242424242424").replace("\"sequence\":7", "\"sequence\":8"));
    expect(otherPublisher.status).toBe(409);
    expect(await otherPublisher.text()).toBe("{\"code\":\"publisherMismatch\",\"protocolVersion\":1}");
    const retained = await objectStorage((state) => state.storage.sql.exec(
      "SELECT envelope, last_sequence FROM relay_state WHERE id = 1",
    ).toArray());
    expect(retained).toEqual([{ envelope: putSnapshot.requestBody, last_sequence: 7 }]);
  });

  it("accepts the maximum safe sequence and the largest valid canonical envelope below the byte cap", async () => {
    const maximumSequence = putSnapshot.requestBody.replace("\"sequence\":7", "\"sequence\":9007199254740991");
    const maximum = await request(putSnapshot.path, putSnapshot.method, tokens.writer, maximumSequence);
    expect(maximum.status).toBe(200);
    expect(await maximum.text()).toBe("{\"protocolVersion\":1,\"sequence\":9007199254740991}");

    await reset();
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    const outer = JSON.parse(putSnapshot.requestBody) as Record<string, unknown>;
    const emptyCiphertext = JSON.stringify({ ...outer, ciphertext: "" });
    let ciphertextLength = 64 * 1024 - new TextEncoder().encode(emptyCiphertext).byteLength;
    if (ciphertextLength % 4 === 1) ciphertextLength -= 1;
    const largestValid = JSON.stringify({ ...outer, ciphertext: "A".repeat(ciphertextLength) });
    expect(new TextEncoder().encode(largestValid).byteLength).toBeGreaterThanOrEqual(64 * 1024 - 1);
    expect(new TextEncoder().encode(largestValid).byteLength).toBeLessThanOrEqual(64 * 1024);
    expect((await request(putSnapshot.path, putSnapshot.method, tokens.writer, largestValid)).status).toBe(200);
    const readLargest = await request(getSnapshot.path, getSnapshot.method, tokens.reader);
    expect(readLargest.status).toBe(200);
    expect(await readLargest.text()).toBe(largestValid);
  });

  it("enforces streamed limits before media-type validation and rejects noncanonical JSON", async () => {
    const oversizedRefresh = await request(postRefresh.path, postRefresh.method, tokens.reader, "x".repeat(193), {
      "Content-Length": "1",
      "Content-Type": "text/plain",
    });
    expect(oversizedRefresh.status).toBe(errorUnauthorized.status);

    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    const oversizedAuthenticatedRefresh = await request(postRefresh.path, postRefresh.method, tokens.reader, "x".repeat(193), {
      "Content-Length": "1",
      "Content-Type": "text/plain",
    });
    expect(oversizedAuthenticatedRefresh.status).toBe(errorRefreshPayloadTooLarge.status);
    expect(await oversizedAuthenticatedRefresh.text()).toBe(errorRefreshPayloadTooLarge.body);

    const wrongMediaType = await SELF.fetch("https://relay.invalid/v2/refresh-requests", {
      body: postRefresh.requestBody,
      headers: { Authorization: `Bearer ${tokens.reader}`, "Content-Type": "text/plain" },
      method: "POST",
    });
    expect(wrongMediaType.status).toBe(errorBadRequest.status);

    const duplicateKey = await request(putSnapshot.path, putSnapshot.method, tokens.writer,
      putSnapshot.requestBody.replace("\"protocolVersion\":1", "\"protocolVersion\":1,\"protocolVersion\":1"));
    expect(duplicateKey.status).toBe(errorBadRequest.status);
    const invalidUTF8 = await SELF.fetch("https://relay.invalid/v1/snapshot", {
      body: new Uint8Array([0xff]),
      headers: { Authorization: `Bearer ${tokens.writer}`, "Content-Type": "application/json" },
      method: "PUT",
    });
    expect(invalidUTF8.status).toBe(errorBadRequest.status);
  });

  it("counts actual request bytes one below, at, and above every route limit", async () => {
    const snapshotBodies = [64 * 1024 - 1, 64 * 1024, 64 * 1024 + 1];
    for (const size of snapshotBodies) {
      const response = await request(putSnapshot.path, putSnapshot.method, tokens.writer, "x".repeat(size));
      expect(response.status).toBe(size > 64 * 1024 ? 413 : 400);
    }

    const registrationBodies = [255, 256, 257];
    for (const size of registrationBodies) {
      const response = await request(registerReader.path, registerReader.method, tokens.admin, "x".repeat(size));
      expect(response.status).toBe(size > 256 ? 413 : 400);
    }

    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    for (const size of [191, 192, 193]) {
      const response = await request(postRefresh.path, postRefresh.method, tokens.reader, "x".repeat(size));
      expect(response.status).toBe(size > 192 ? 413 : 400);
    }
  });

  it("keeps registrations bounded, ordered, retryable, and revocable", async () => {
    const first = await register();
    expect(first.status).toBe(200);
    const retry = await register();
    expect(await retry.text()).toBe(await first.clone().text());

    const changedDigest = await register(readerOneID, digests.readerTwo);
    expect(changedDigest.status).toBe(errorBadRequest.status);
    const reusedDigest = await register(readerTwoID, digests.reader);
    expect(reusedDigest.status).toBe(errorBadRequest.status);
    const preservedReader = await objectStorage((state) => state.storage.sql.exec(
      "SELECT activated, reader_id, token_digest FROM readers WHERE reader_id = ?",
      readerOneID,
    ).toArray());
    expect(preservedReader).toEqual([{
      activated: 0,
      reader_id: readerOneID,
      token_digest: digests.reader,
    }]);
    const privilegedDigest = await register(readerTwoID, "02d449a31fbb267c8f352e9968a79e3e5fc95c1bbeaa502fd6454ebde5a4bedc");
    expect(privilegedDigest.status).toBe(errorBadRequest.status);

    expect((await register(readerTwoID, digests.readerTwo)).status).toBe(200);
    expect((await register(readerThreeID, "84126d0dd850199be29021aadbaee68cb9199047b1cb7ec9894ddb1e3562783c")).status).toBe(200);
    const fourth = await register("48484848484848484848484848484848", "deb0e38ced1e41de6f92e70e80c418d2d356afaaa99e26f5939dbc7d3ef4772a");
    expect(fourth.status).toBe(errorReaderCapReached.status);
    expect(await fourth.text()).toBe(errorReaderCapReached.body);

    expect((await activateReader()).status).toBe(200);
    const listing = await request(listReaders.path, listReaders.method, tokens.admin);
    expect(listing.status).toBe(listReaders.status);
    const listed = JSON.parse(await listing.text()) as { readers: Array<{ readerID: string; activated: boolean }> };
    expect(listed.readers.map((reader) => reader.readerID)).toEqual([readerOneID, readerTwoID, readerThreeID]);
    expect(listed.readers[0]?.activated).toBe(true);

    const revoke = await request(revokeReader.path, revokeReader.method, tokens.admin);
    expect(revoke.status).toBe(revokeReader.status);
    expect(await revoke.text()).toBe(revokeReader.responseBody);
    expect((await request(getSnapshot.path, getSnapshot.method, tokens.reader)).status).toBe(errorUnauthorized.status);
  });

  it("stores encrypted reader profiles monotonically and reports activation provenance", async () => {
    await setClock(registrationStart);
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    const profile = (revision: number, ciphertext = "AQID") => canonicalJSON({
      ciphertext,
      keyVersion: 1,
      nonce: "q6urq6urq6urq6ur",
      profileVersion: 1,
      protocolVersion: 2,
      publisherID: "2323232323232323232323232323232323232323232323232323232323232323",
      readerID: readerOneID,
      revision,
      tag: "u7u7u7u7u7u7u7u7u7u7uw",
    });

    const firstBody = profile(1);
    const first = await request("/v2/reader-profile", "PUT", tokens.reader, firstBody);
    expect(first.status).toBe(200);
    expect(await first.text()).toBe('{"protocolVersion":2,"revision":1}');
    expect((await request("/v2/reader-profile", "PUT", tokens.reader, firstBody)).status).toBe(200);
    expect((await request("/v2/reader-profile", "PUT", tokens.reader, profile(1, "BAUG"))).status).toBe(409);
    expect((await request("/v2/reader-profile", "PUT", tokens.reader, profile(2))).status).toBe(200);
    expect((await request("/v2/reader-profile", "PUT", tokens.reader, firstBody)).status).toBe(409);

    const listing = await request("/v2/readers", "GET", tokens.admin);
    expect(listing.status).toBe(200);
    const body = JSON.parse(await listing.text()) as {
      readers: Array<{ activatedAt?: string; profile?: { revision: number }; readerID: string }>;
    };
    expect(body.readers[0]?.readerID).toBe(readerOneID);
    expect(body.readers[0]?.activatedAt).toBe("2023-11-14T22:13:20.000Z");
    expect(body.readers[0]?.profile?.revision).toBe(2);
    expect((await request("/v2/readers", "GET", tokens.reader)).status).toBe(401);
  });

  it("rejects a profile write when the reader token changes during body receipt", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    const profile = canonicalJSON({
      ciphertext: "AQID", keyVersion: 1, nonce: "q6urq6urq6urq6ur",
      profileVersion: 1, protocolVersion: 2,
      publisherID: "2323232323232323232323232323232323232323232323232323232323232323",
      readerID: readerOneID, revision: 1, tag: "u7u7u7u7u7u7u7u7u7u7uw",
    });
    expect((await requestReplacingReaderOnBodyRead("/v2/reader-profile", profile)).status).toBe(401);
    const readers = JSON.parse(await (await request("/v2/readers", "GET", tokens.admin)).text()) as {
      readers: Array<{ profile?: unknown; readerID: string }>;
    };
    expect(readers.readers).toEqual([{ activated: true, activatedAt: expect.any(String), readerID: readerOneID }]);
  });

  it("rejects a refresh request when the reader token changes during body receipt", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    expect((await requestReplacingReaderOnBodyRead("/v2/refresh-requests", postRefresh.requestBody)).status).toBe(401);
    expect(await (await request("/v2/refresh-requests", "GET", tokens.writer)).text())
      .toBe('{"protocolVersion":2,"requests":[]}');
  });

  it("keeps concurrent snapshot, registration, and mailbox transitions atomic", async () => {
    const concurrentPublications = await Promise.all([
      request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody),
      request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody),
    ]);
    expect(concurrentPublications.map((response) => response.status).sort()).toEqual([200, 409]);

    const candidates = [
      { digest: digests.reader, id: readerOneID, token: tokens.reader },
      { digest: digests.readerTwo, id: readerTwoID, token: tokens.readerTwo },
      { digest: digests.readerThree, id: readerThreeID, token: tokens.readerThree },
      { digest: digests.wrong, id: "48484848484848484848484848484848", token: tokens.wrong },
    ];
    const registrations = await Promise.all(candidates.map((candidate) =>
      register(candidate.id, candidate.digest)));
    expect(registrations.filter((response) => response.status === 200)).toHaveLength(3);
    expect(registrations.filter((response) => response.status === 409)).toHaveLength(1);
    const winners = candidates.filter((_candidate, index) => registrations[index]?.status === 200);

    for (const winner of winners) expect((await activateReader(winner.token)).status).toBe(200);
    const requestIDs = [
      "56565656565656565656565656565656",
      "57575757575757575757575757575757",
      "58585858585858585858585858585858",
    ];
    const mailbox = await Promise.all(winners.map((winner, index) =>
      request(postRefresh.path, postRefresh.method, winner.token,
        JSON.stringify({
          protocolVersion: 2,
          requestID: requestIDs[index],
          target: "allCodex",
        }))));
    expect(mailbox.map((response) => response.status)).toEqual([202, 202, 202]);
    const listed = JSON.parse(await (await request(listRefresh.path, listRefresh.method, tokens.writer)).text()) as {
      requests: Array<{ readerID: string; requestID: string }>;
    };
    const expectedRequests = winners.map((winner, index) => ({
      readerID: winner.id,
      requestID: requestIDs[index],
    })).sort((left, right) => left.readerID.localeCompare(right.readerID));
    expect(listed.requests.map(({ readerID, requestID }) => ({ readerID, requestID })))
      .toEqual(expectedRequests);
  });

  it("implements the activated-reader refresh mailbox and completed-ID replay guard", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    await setClock(refreshStart);
    const posted = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(posted.status).toBe(postRefresh.status);
    expect(await posted.text()).toBe(postRefresh.responseBody);

    const retry = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(retry.status).toBe(postRefresh.status);
    expect(await retry.text()).toBe(postRefresh.responseBody);
    const rateLimited = await request(postRefresh.path, postRefresh.method, tokens.reader,
      postRefresh.requestBody.replaceAll("56565656565656565656565656565656", "57575757575757575757575757575757"));
    expect(rateLimited.status).toBe(errorRefreshRequestRateLimited.status);
    expect(await rateLimited.text()).toBe(errorRefreshRequestRateLimited.body);

    const requests = await request(listRefresh.path, listRefresh.method, tokens.writer);
    expect(requests.status).toBe(listRefresh.status);
    expect(await requests.clone().text()).toBe(listRefresh.responseBody);
    const requestList = JSON.parse(await requests.text()) as {
      requests: Array<{ expiresAt: string; readerID: string; requestID: string }>;
    };
    expect(requestList.requests).toHaveLength(1);
    expect(requestList.requests[0]).toMatchObject({
      readerID: readerOneID,
      requestID: "56565656565656565656565656565656",
    });
    expect(requestList.requests[0]?.expiresAt).toMatch(/^\d{4}-\d{2}-\d{2}T.*\.\d{3}Z$/);
    expect(requests.headers.get("Cache-Control")).toBe("no-store");

    const acknowledged = await request(deleteRefresh.path, deleteRefresh.method, tokens.writer);
    expect(acknowledged.status).toBe(deleteRefresh.status);
    expect(await acknowledged.text()).toBe(deleteRefresh.responseBody);
    expect((await request(deleteRefresh.path, deleteRefresh.method, tokens.writer)).status).toBe(204);
    const completedReplay = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(completedReplay.status).toBe(errorRefreshRequestAlreadyCompleted.status);
    expect(await completedReplay.text()).toBe(errorRefreshRequestAlreadyCompleted.body);
  });

  it("stores strict account targets and keeps the rate limit reader-global", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    await setClock(refreshStart);
    const requestID = "60606060606060606060606060606060";
    const accountID = "61616161616161616161616161616161";
    const accountBody = JSON.stringify({ accountID, protocolVersion: 2, requestID, target: "account" });
    const posted = await request(postRefresh.path, postRefresh.method, tokens.reader, accountBody);
    expect(posted.status).toBe(202);
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, accountBody)).status).toBe(202);

    const listed = await request(listRefresh.path, listRefresh.method, tokens.writer);
    expect(JSON.parse(await listed.text()).requests).toEqual([{
      accountID,
      expiresAt: "2023-11-14T22:18:20.000Z",
      readerID: readerOneID,
      requestID,
      target: "account",
    }]);

    const changedTarget = JSON.stringify({ protocolVersion: 2, requestID, target: "allCodex" });
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, changedTarget)).status).toBe(400);
    const differentID = JSON.stringify({
      protocolVersion: 2,
      requestID: "62626262626262626262626262626262",
      target: "allCodex",
    });
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, differentID)).status).toBe(429);

    const malformedBodies = [
      JSON.stringify({ accountID, protocolVersion: 2, requestID, target: "allCodex" }),
      JSON.stringify({ protocolVersion: 2, requestID, target: "account" }),
      JSON.stringify({ protocolVersion: 2, requestID, target: "codex" }),
      JSON.stringify({ extra: true, protocolVersion: 2, requestID, target: "allCodex" }),
      JSON.stringify({ accountID: "A".repeat(32), protocolVersion: 2, requestID, target: "account" }),
    ];
    for (const body of malformedBodies) {
      expect((await request(postRefresh.path, postRefresh.method, tokens.reader, body)).status).toBe(400);
    }
    const oldVersion = JSON.stringify({ protocolVersion: 1, requestID, target: "allCodex" });
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, oldVersion)).status).toBe(422);
  });

  it("migrates schema 1 in place while preserving readers and the stored snapshot", async () => {
    const storedEnvelope = JSON.parse(envelope.outerJSON) as {
      publisherID: string;
      sequence: number;
    };
    await objectStorage((state) => {
      state.storage.sql.exec("CREATE TABLE relay_schema (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL)");
      state.storage.sql.exec("CREATE TABLE relay_state (id INTEGER PRIMARY KEY CHECK (id = 1), publisher_id TEXT NOT NULL, last_sequence INTEGER NOT NULL, envelope TEXT NOT NULL, etag TEXT NOT NULL, accepted_at INTEGER NOT NULL)");
      state.storage.sql.exec("CREATE TABLE readers (reader_id TEXT PRIMARY KEY, token_digest TEXT NOT NULL UNIQUE, activated INTEGER NOT NULL, pending_expires_at INTEGER NOT NULL, last_accepted_at INTEGER, last_accepted_id TEXT, last_completed_id TEXT)");
      state.storage.sql.exec("CREATE TABLE refresh_requests (request_id TEXT PRIMARY KEY, reader_id TEXT NOT NULL UNIQUE, accepted_at INTEGER NOT NULL, expires_at INTEGER NOT NULL)");
      state.storage.sql.exec("INSERT INTO relay_schema (id, version) VALUES (1, 1)");
      state.storage.sql.exec(
        "INSERT INTO relay_state (id, publisher_id, last_sequence, envelope, etag, accepted_at) VALUES (1, ?, ?, ?, ?, ?)",
        storedEnvelope.publisherID, storedEnvelope.sequence, envelope.outerJSON, envelope.etag,
        refreshStart,
      );
      state.storage.sql.exec(
        "INSERT INTO readers (reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id) VALUES (?, ?, 1, ?, NULL, NULL, NULL)",
        readerOneID, digests.reader, registrationStart + 300_000,
      );
      state.storage.sql.exec(
        "INSERT INTO refresh_requests (request_id, reader_id, accepted_at, expires_at) VALUES (?, ?, ?, ?)",
        "63636363636363636363636363636363", readerOneID, refreshStart, refreshStart + 60_000,
      );
    });

    const migrated = await request(listRefresh.path, listRefresh.method, tokens.writer);
    expect(migrated.status).toBe(200);
    expect(await migrated.text()).toBe('{"protocolVersion":2,"requests":[]}');
    const stored = await objectStorage((state) => ({
      columns: state.storage.sql.exec("PRAGMA table_info(refresh_requests)").toArray().map((row) => row.name),
      reader: state.storage.sql.exec("SELECT reader_id, token_digest, activated FROM readers").toArray(),
      refreshCount: state.storage.sql.exec("SELECT COUNT(*) AS n FROM refresh_requests").one().n,
      schema: state.storage.sql.exec("SELECT version FROM relay_schema WHERE id = 1").one().version,
      snapshot: state.storage.sql.exec("SELECT publisher_id, last_sequence, envelope, etag FROM relay_state WHERE id = 1").one(),
    }));
    expect(stored.schema).toBe(3);
    expect(stored.columns).toEqual([
      "request_id", "reader_id", "target", "account_id", "accepted_at", "expires_at",
    ]);
    expect(stored.refreshCount).toBe(0);
    expect(stored.reader).toEqual([{ activated: 1, reader_id: readerOneID, token_digest: digests.reader }]);
    expect(stored.snapshot).toEqual({
      envelope: envelope.outerJSON,
      etag: envelope.etag,
      last_sequence: storedEnvelope.sequence,
      publisher_id: storedEnvelope.publisherID,
    });
    const snapshot = await request(getSnapshot.path, getSnapshot.method, tokens.reader);
    expect(snapshot.status).toBe(200);
    expect(await snapshot.text()).toBe(envelope.outerJSON);
  });

  it("uses relay time at registration and refresh expiry boundaries", async () => {
    await setClock(registrationStart);
    expect(await (await request(registerReader.path, registerReader.method, tokens.admin, registerReader.requestBody)).text())
      .toBe(registerReader.responseBody);

    await setClock(registrationStart + 299_999);
    expect((await activateReader()).status).toBe(200);
    await setClock(registrationStart + 300_000);
    expect(await (await activateReader()).text()).toBe(activate.responseBody);

    await setClock(refreshStart);
    const first = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(await first.text()).toBe(postRefresh.responseBody);
    await setClock(refreshStart + 59_999);
    expect(await (await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody)).text())
      .toBe(postRefresh.responseBody);
    await setClock(refreshStart + 60_000);
    const expiredRetry = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(expiredRetry.status).toBe(errorBadRequest.status);
    const differentAfterLimit = await request(postRefresh.path, postRefresh.method, tokens.reader,
      postRefresh.requestBody.replaceAll("56565656565656565656565656565656", "57575757575757575757575757575757"));
    expect(differentAfterLimit.status).toBe(202);
  });

  it("rejects cross-reader live IDs and retains completed IDs while a newer request is pending", async () => {
    expect((await register()).status).toBe(200);
    expect((await register(readerTwoID, digests.readerTwo)).status).toBe(200);
    expect((await activateReader(tokens.reader)).status).toBe(200);
    expect((await activateReader(tokens.readerTwo)).status).toBe(200);
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody)).status).toBe(202);
    const sameIDFromSecondReader = await request(postRefresh.path, postRefresh.method, tokens.readerTwo, postRefresh.requestBody);
    expect(sameIDFromSecondReader.status).toBe(errorBadRequest.status);

    expect((await request(deleteRefresh.path, deleteRefresh.method, tokens.writer)).status).toBe(204);
    const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
    await runInDurableObject(stub, (_instance, state) => {
      state.storage.sql.exec("UPDATE readers SET last_accepted_at = 0 WHERE reader_id = ?", readerOneID);
    });
    const newerID = postRefresh.requestBody.replaceAll("56565656565656565656565656565656", "57575757575757575757575757575757");
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, newerID)).status).toBe(202);
    const completedReplayWhileNewerPending = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(completedReplayWhileNewerPending.status)
      .toBe(errorRefreshRequestAlreadyCompleted.status);
  });

  it("expires pending readers before a registration cap check without expiring activated readers", async () => {
    expect((await register()).status).toBe(200);
    const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
    await runInDurableObject(stub, (_instance, state) => {
      state.storage.sql.exec("UPDATE readers SET pending_expires_at = 0 WHERE reader_id = ?", readerOneID);
    });
    expect((await request(getSnapshot.path, getSnapshot.method, tokens.reader)).status).toBe(401);
    expect((await register(readerTwoID, digests.readerTwo)).status).toBe(200);

    expect((await activateReader(tokens.readerTwo)).status).toBe(200);
    await runInDurableObject(stub, (_instance, state) => {
      state.storage.sql.exec("UPDATE readers SET pending_expires_at = 0 WHERE reader_id = ?", readerTwoID);
    });
    expect((await request(getSnapshot.path, getSnapshot.method, tokens.readerTwo)).status).toBe(404);
  });

  it("does not mutate expired-reader rows for an invalid read token", async () => {
    await setClock(registrationStart);
    expect((await register()).status).toBe(200);
    await setClock(registrationStart + 300_000);
    const invalidRead = await request(getSnapshot.path, getSnapshot.method, tokens.wrong);
    expect(invalidRead.status).toBe(errorUnauthorized.status);
    const stored = await objectStorage((state) => state.storage.sql.exec(
      "SELECT activated, pending_expires_at FROM readers WHERE reader_id = ?",
      readerOneID,
    ).toArray());
    expect(stored).toEqual([{ activated: 0, pending_expires_at: registrationStart + 300_000 }]);

    expect((await request(getSnapshot.path, getSnapshot.method, tokens.reader)).status).toBe(401);
    expect((await activateReader()).status).toBe(401);
  });

  it("removes revoked-reader requests and stores no plaintext or raw token bytes", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    expect((await request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody)).status).toBe(200);
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody)).status).toBe(202);
    const persisted = await objectStorage((state) => [
      ...state.storage.sql.exec("SELECT * FROM relay_state").toArray(),
      ...state.storage.sql.exec("SELECT * FROM readers").toArray(),
      ...state.storage.sql.exec("SELECT * FROM refresh_requests").toArray(),
    ]);
    const persistedText = JSON.stringify(persisted);
    for (const token of Object.values(tokens)) {
      expect(persistedText).not.toContain(token);
    }
    expect(persistedText).not.toContain("plaintext");
    expect(persistedText).not.toContain("contentKey");

    expect((await request(revokeReader.path, revokeReader.method, tokens.admin)).status).toBe(204);
    const requests = await request(listRefresh.path, listRefresh.method, tokens.writer);
    expect(await requests.text()).toBe("{\"protocolVersion\":2,\"requests\":[]}");
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody)).status).toBe(401);
  });

  it("removes all state atomically and fails closed on an incompatible schema", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    expect((await request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody)).status).toBe(200);
    expect((await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody)).status).toBe(202);
    const destroyed = await request(destroyRelay.path, destroyRelay.method, tokens.admin);
    expect(destroyed.status).toBe(destroyRelay.status);
    expect(await destroyed.text()).toBe(destroyRelay.responseBody);
    expect((await request(getSnapshot.path, getSnapshot.method, tokens.reader)).status).toBe(401);
    expect(await (await request(listRefresh.path, listRefresh.method, tokens.writer)).text())
      .toBe("{\"protocolVersion\":2,\"requests\":[]}");
    const newPublisher = putSnapshot.requestBody
      .replaceAll("2323232323232323232323232323232323232323232323232323232323232323", "2424242424242424242424242424242424242424242424242424242424242424")
      .replace("\"sequence\":7", "\"sequence\":1");
    expect((await request(putSnapshot.path, putSnapshot.method, tokens.writer, newPublisher)).status).toBe(200);
    expect((await request(destroyRelay.path, destroyRelay.method, tokens.admin)).status).toBe(204);

    expect((await register()).status).toBe(200);
    const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
    await runInDurableObject(stub, (_instance, state) => {
      state.storage.sql.exec("UPDATE relay_schema SET version = 4 WHERE id = 1");
    });
    const unavailable = await request("/v1/nope", "GET");
    expect(unavailable.status).toBe(503);
    expect(await unavailable.text()).toBe("{\"code\":\"relayUnavailable\",\"protocolVersion\":1}");
  });
});
