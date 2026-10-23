import { expect, it } from "vitest";
import envelope from "../../Fixtures/Protocol/envelope.json";
import pairing from "../../Fixtures/Protocol/pairing.json";
import opSnapshotPut from "../../Fixtures/Protocol/operation-snapshot-put.json";
import opSnapshotGet from "../../Fixtures/Protocol/operation-snapshot-get.json";
import opReaderActivate from "../../Fixtures/Protocol/operation-reader-activate.json";
import opRefreshPost from "../../Fixtures/Protocol/operation-refresh-post.json";
import opRefreshList from "../../Fixtures/Protocol/operation-refresh-list.json";
import opRefreshDelete from "../../Fixtures/Protocol/operation-refresh-delete.json";
import opReaderRegister from "../../Fixtures/Protocol/operation-reader-register.json";
import opReaderList from "../../Fixtures/Protocol/operation-reader-list.json";
import opReaderRevoke from "../../Fixtures/Protocol/operation-reader-revoke.json";
import opRelayDestroy from "../../Fixtures/Protocol/operation-relay-destroy.json";
import errorBadRequest from "../../Fixtures/Protocol/error-bad-request.json";
import errorUnauthorized from "../../Fixtures/Protocol/error-unauthorized.json";
import errorAwaiting from "../../Fixtures/Protocol/error-awaiting-first-publish.json";
import errorUnknownRoute from "../../Fixtures/Protocol/error-unknown-route.json";
import errorPublisherMismatch from "../../Fixtures/Protocol/error-publisher-mismatch.json";
import errorSequenceConflict from "../../Fixtures/Protocol/error-sequence-conflict.json";
import errorReaderCap from "../../Fixtures/Protocol/error-reader-cap-reached.json";
import errorRequestCompleted from "../../Fixtures/Protocol/error-request-already-completed.json";
import errorPayloadTooLarge from "../../Fixtures/Protocol/error-payload-too-large.json";
import errorUnsupportedVersion from "../../Fixtures/Protocol/error-unsupported-version.json";
import errorRequestRate from "../../Fixtures/Protocol/error-request-rate-limited.json";
import errorQuota from "../../Fixtures/Protocol/error-quota-limited.json";
import scenarioReaderRetry from "../../Fixtures/Protocol/scenario-reader-retry.json";
import scenarioReaderChanged from "../../Fixtures/Protocol/scenario-reader-changed-digest.json";
import scenarioReaderReused from "../../Fixtures/Protocol/scenario-reader-reused-digest.json";
import scenarioReaderPrivileged from "../../Fixtures/Protocol/scenario-reader-privileged-digest.json";
import scenarioRefreshExpired from "../../Fixtures/Protocol/scenario-refresh-expired-id.json";
import scenarioRefreshCrossReader from "../../Fixtures/Protocol/scenario-refresh-cross-reader-id.json";
import scenarioRefreshCompleted from "../../Fixtures/Protocol/scenario-refresh-completed-id.json";
import scenarioSequenceOverflow from "../../Fixtures/Protocol/scenario-sequence-overflow.json";

const canonical = (value: unknown): string => JSON.stringify(value, function (_key, child) {
  if (child !== null && !Array.isArray(child) && typeof child === "object") {
    const record = child as Record<string, unknown>;
    return Object.fromEntries(Object.keys(record).sort().map((key) => [key, record[key]]));
  }
  return child;
});

const bytes = (value: string): Uint8Array => {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")),
    (character) => character.charCodeAt(0));
};

const hex = (value: ArrayBuffer): string => [...new Uint8Array(value)]
  .map((byte) => byte.toString(16).padStart(2, "0")).join("");

it("validates the shared outer envelope without a content key", async () => {
  const outer = JSON.parse(envelope.outerJSON) as Record<string, unknown>;
  expect(canonical(outer)).toBe(envelope.outerJSON);
  expect(Object.keys(outer).sort()).toEqual([
    "ciphertext", "envelopeVersion", "keyVersion", "nonce", "protocolVersion",
    "publisherID", "sequence", "tag",
  ]);
  const { nonce, ciphertext, tag, ...header } = outer;
  expect(canonical(header)).toBe(envelope.headerJSON);
  expect(header.protocolVersion).toBe(1);
  expect(header.envelopeVersion).toBe(1);
  expect(header.keyVersion).toBe(1);
  expect(Number.isSafeInteger(header.sequence)).toBe(true);
  expect(header.sequence).toBeGreaterThan(0);
  expect(header.publisherID).toMatch(/^[0-9a-f]{64}$/);
  expect(bytes(nonce as string)).toHaveLength(12);
  expect(bytes(tag as string)).toHaveLength(16);
  expect(bytes(ciphertext as string).length).toBeGreaterThan(0);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(envelope.outerJSON));
  expect(`"${hex(digest)}"`).toBe(envelope.etag);
});

it("validates the shared canonical pairing package and confirmation code", async () => {
  const packageText = new TextDecoder().decode(bytes(pairing.encoded));
  expect(packageText).toBe(pairing.packageJSON);
  const fields = JSON.parse(packageText) as Record<string, unknown>;
  expect(canonical(fields)).toBe(pairing.packageJSON);
  expect(Object.keys(fields).sort()).toEqual([
    "contentKey", "keyVersion", "minimumSequence", "publisherID", "readToken",
    "readerID", "registrationExpiresAt", "relayEndpoint", "schemaVersion",
  ]);
  expect(bytes(fields.contentKey as string)).toHaveLength(32);
  expect(bytes(fields.readToken as string)).toHaveLength(32);
  expect(fields.minimumSequence).toBe(7);
  expect(Number.isSafeInteger(fields.minimumSequence)).toBe(true);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(pairing.encoded));
  expect(hex(digest).slice(0, 16).match(/.{4}/g)?.join("-")).toBe(pairing.confirmationCode);
});

const operations = [
  opSnapshotPut, opSnapshotGet, opReaderActivate, opRefreshPost, opRefreshList,
  opRefreshDelete, opReaderRegister, opReaderList, opReaderRevoke, opRelayDestroy,
];

it("validates every shared operation body and route fixture", () => {
  expect(operations).toHaveLength(10);
  for (const fixture of operations) {
    expect(fixture.path).toMatch(/^\/v1\//);
    expect(["GET", "PUT", "POST", "DELETE"]).toContain(fixture.method);
    expect(["read", "write", "admin"]).toContain(fixture.authority);
    for (const body of [fixture.requestBody, fixture.responseBody]) {
      if (body === "") { continue; }
      const parsed = JSON.parse(body) as Record<string, unknown>;
      expect(canonical(parsed)).toBe(body);
      expect(parsed.protocolVersion).toBe(1);
    }
    if (fixture.status === 204) { expect(fixture.responseBody).toBe(""); }
  }
  expect(opSnapshotPut.requestBody).toBe(envelope.outerJSON);
  expect(opSnapshotGet.responseBody).toBe(envelope.outerJSON);
  expect(opSnapshotPut.etag).toBe(envelope.etag);
  expect(opSnapshotGet.etag).toBe(envelope.etag);
});

const errors = [
  errorBadRequest, errorUnauthorized, errorAwaiting, errorUnknownRoute,
  errorPublisherMismatch, errorSequenceConflict, errorReaderCap, errorRequestCompleted,
  errorPayloadTooLarge, errorUnsupportedVersion, errorRequestRate, errorQuota,
];

it("validates every shared error body fixture", () => {
  expect(errors).toHaveLength(12);
  for (const fixture of errors) {
    const body = JSON.parse(fixture.body) as Record<string, unknown>;
    expect(canonical(body)).toBe(fixture.body);
    expect(body).toEqual({ code: fixture.code, protocolVersion: 1 });
    expect([400, 401, 404, 409, 413, 422, 429]).toContain(fixture.status);
  }
});

const scenarios = [
  scenarioReaderRetry, scenarioReaderChanged, scenarioReaderReused,
  scenarioReaderPrivileged, scenarioRefreshExpired, scenarioRefreshCrossReader,
  scenarioRefreshCompleted, scenarioSequenceOverflow,
];

it("pins registration, refresh-ID, and sequence-boundary decisions", () => {
  expect(scenarios).toHaveLength(8);
  for (const scenario of scenarios) {
    expect(["registerReader", "postRefreshRequest", "putSnapshot"])
      .toContain(scenario.operation);
    expect(canonical(JSON.parse(scenario.requestBody))).toBe(scenario.requestBody);
    expect(canonical(JSON.parse(scenario.responseBody))).toBe(scenario.responseBody);
  }
  expect(scenarioReaderRetry.status).toBe(200);
  expect(scenarioReaderRetry.responseBody).toBe(opReaderRegister.responseBody);
  for (const scenario of [
    scenarioReaderChanged, scenarioReaderReused, scenarioReaderPrivileged,
    scenarioRefreshExpired, scenarioRefreshCrossReader, scenarioSequenceOverflow,
  ]) {
    expect(scenario.status).toBe(400);
    expect(scenario.responseBody).toBe(errorBadRequest.body);
  }
  expect(scenarioRefreshCompleted.status).toBe(409);
  expect(scenarioRefreshCompleted.responseBody).toBe(errorRequestCompleted.body);
  const overflow = JSON.parse(scenarioSequenceOverflow.requestBody) as Record<string, unknown>;
  expect(Number.isSafeInteger(overflow.sequence)).toBe(false);
  expect(overflow.sequence).toBe(9_007_199_254_740_992);
});
