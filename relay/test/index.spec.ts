import { env, reset, runInDurableObject, SELF } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";

import envelope from "../../Fixtures/Protocol/envelope.json";
import errorAwaitingFirstPublish from "../../Fixtures/Protocol/error-awaiting-first-publish.json";
import errorBadRequest from "../../Fixtures/Protocol/error-bad-request.json";
import errorPayloadTooLarge from "../../Fixtures/Protocol/error-payload-too-large.json";
import errorReaderCapReached from "../../Fixtures/Protocol/error-reader-cap-reached.json";
import errorRequestAlreadyCompleted from "../../Fixtures/Protocol/error-request-already-completed.json";
import errorRequestRateLimited from "../../Fixtures/Protocol/error-request-rate-limited.json";
import errorSequenceConflict from "../../Fixtures/Protocol/error-sequence-conflict.json";
import errorUnauthorized from "../../Fixtures/Protocol/error-unauthorized.json";
import errorUnknownRoute from "../../Fixtures/Protocol/error-unknown-route.json";
import errorUnsupportedVersion from "../../Fixtures/Protocol/error-unsupported-version.json";
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
  writer: "ERERERERERERERERERERERERERERERERERERERERERE",
  wrong: "MzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzM",
};

const digests = {
  reader: "4c07be22f86c52fd94ac9b44b023583c4fd5180d193ff28491d2885653c2c81e",
  readerTwo: "bb391415c05e39d77ca17381d3be3f7d0cd5e5332e5a579311adaa0aa62106e9",
};

const readerOneID = "45454545454545454545454545454545";
const readerTwoID = "46464646464646464646464646464646";
const readerThreeID = "47474747474747474747474747474747";

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
  if (body !== undefined) requestHeaders.set("Content-Type", "application/json");
  return SELF.fetch(`https://relay.invalid${path}`, { body, headers: requestHeaders, method });
}

async function register(id = readerOneID, digest = digests.reader): Promise<Response> {
  return request(`/v1/readers/${id}`, "PUT", tokens.admin,
    JSON.stringify({ protocolVersion: 1, tokenDigest: digest }));
}

async function activateReader(token = tokens.reader): Promise<Response> {
  return request("/v1/readers/activate", "POST", token);
}

describe("Relay Worker v1", () => {
  it("consumes the snapshot, reader, and activation fixtures byte-for-byte", async () => {
    const registration = await request(registerReader.path, registerReader.method, tokens.admin, registerReader.requestBody);
    expect(registration.status).toBe(registerReader.status);
    expect(JSON.parse(await registration.text())).toMatchObject({ protocolVersion: 1 });

    const beforePublish = await request(getSnapshot.path, getSnapshot.method, tokens.reader);
    expect(beforePublish.status).toBe(errorAwaitingFirstPublish.status);
    expect(await beforePublish.text()).toBe(errorAwaitingFirstPublish.body);
    expect(beforePublish.headers.get("Cache-Control")).toBe("no-store");

    const publication = await request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody);
    expect(publication.status).toBe(putSnapshot.status);
    expect(await publication.text()).toBe(putSnapshot.responseBody);
    expect(publication.headers.get("ETag")).toBe(putSnapshot.etag);

    const read = await request(getSnapshot.path, getSnapshot.method, tokens.reader);
    expect(read.status).toBe(getSnapshot.status);
    expect(await read.text()).toBe(getSnapshot.responseBody);
    expect(read.headers.get("ETag")).toBe(getSnapshot.etag);
    expect(read.headers.get("Cache-Control")).toBe("no-store");

    const conditional = await request(getSnapshot.path, getSnapshot.method, tokens.reader, undefined, {
      "If-None-Match": envelope.etag,
    });
    expect(conditional.status).toBe(304);
    expect(await conditional.text()).toBe("");
    expect(conditional.headers.get("ETag")).toBe(envelope.etag);

    const activation = await request(activate.path, activate.method, tokens.reader);
    expect(activation.status).toBe(activate.status);
    expect(await activation.text()).toBe(activate.responseBody);
    const activationRetry = await request(activate.path, activate.method, tokens.reader);
    expect(await activationRetry.text()).toBe(activate.responseBody);
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
  });

  it("keeps registrations bounded, ordered, retryable, and revocable", async () => {
    const first = await register();
    expect(first.status).toBe(200);
    const retry = await register();
    expect(await retry.text()).toBe(await first.clone().text());

    const changedDigest = await register(readerOneID, digests.readerTwo);
    expect(changedDigest.status).toBe(errorBadRequest.status);
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

  it("implements the activated-reader refresh mailbox and completed-ID replay guard", async () => {
    expect((await register()).status).toBe(200);
    expect((await activateReader()).status).toBe(200);
    const posted = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(posted.status).toBe(postRefresh.status);
    expect(JSON.parse(await posted.text())).toMatchObject({ protocolVersion: 1 });

    const retry = await request(postRefresh.path, postRefresh.method, tokens.reader, postRefresh.requestBody);
    expect(retry.status).toBe(postRefresh.status);
    const rateLimited = await request(postRefresh.path, postRefresh.method, tokens.reader,
      postRefresh.requestBody.replaceAll("56565656565656565656565656565656", "57575757575757575757575757575757"));
    expect(rateLimited.status).toBe(errorRequestRateLimited.status);
    expect(await rateLimited.text()).toBe(errorRequestRateLimited.body);

    const requests = await request(listRefresh.path, listRefresh.method, tokens.writer);
    expect(requests.status).toBe(listRefresh.status);
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
    expect(completedReplay.status).toBe(errorRequestAlreadyCompleted.status);
    expect(await completedReplay.text()).toBe(errorRequestAlreadyCompleted.body);
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
    expect(completedReplayWhileNewerPending.status).toBe(errorRequestAlreadyCompleted.status);
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

  it("removes all state atomically and fails closed on an incompatible schema", async () => {
    expect((await register()).status).toBe(200);
    expect((await request(putSnapshot.path, putSnapshot.method, tokens.writer, putSnapshot.requestBody)).status).toBe(200);
    const destroyed = await request(destroyRelay.path, destroyRelay.method, tokens.admin);
    expect(destroyed.status).toBe(destroyRelay.status);
    expect(await destroyed.text()).toBe(destroyRelay.responseBody);
    expect((await request(getSnapshot.path, getSnapshot.method, tokens.reader)).status).toBe(401);
    expect((await request(destroyRelay.path, destroyRelay.method, tokens.admin)).status).toBe(204);

    await request("/v1/nope", "GET");
    const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
    await runInDurableObject(stub, (_instance, state) => {
      state.storage.sql.exec("UPDATE relay_schema SET version = 2 WHERE id = 1");
    });
    const unavailable = await request("/v1/nope", "GET");
    expect(unavailable.status).toBe(503);
    expect(await unavailable.text()).toBe("{\"code\":\"relayUnavailable\",\"protocolVersion\":1}");
  });
});
