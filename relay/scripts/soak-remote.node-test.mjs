import assert from "node:assert/strict";
import test from "node:test";

import {
  MANUAL_REQUEST_SPACING_MS,
  manualRequestWaitMilliseconds,
  parseManualRequestResponse,
  runManualRequestRound,
} from "./soak-remote.mjs";

const expiry = '{"expiresAt":"2023-11-14T22:18:20.000Z","protocolVersion":1}';

test("manual request response classification distinguishes relay and non-relay 429", () => {
  assert.equal(parseManualRequestResponse({ status: 202, text: expiry }).protocolVersion, 1);
  assert.throws(
    () => parseManualRequestResponse({
      status: 429,
      text: '{"code":"requestRateLimited","protocolVersion":1}',
    }),
    /Relay rate-limited a scheduled manual request/,
  );
  assert.throws(
    () => parseManualRequestResponse({
      status: 429,
      text: '{"cloudflare_error":true,"error_category":"rate_limit","error_code":1027,"status":429}',
    }),
    /Non-relay HTTP 429 stopped the scheduled sample/,
  );
  assert.throws(
    () => parseManualRequestResponse({ status: 503, text: "{}" }),
    /HTTP 503; expected 202/,
  );
});

test("manual request spacing is measured from the prior accepted response", () => {
  assert.equal(MANUAL_REQUEST_SPACING_MS, 60_001);
  assert.equal(manualRequestWaitMilliseconds(70_001, 10_000), 60_001);
  assert.equal(manualRequestWaitMilliseconds(70_001, 70_000), 1);
  assert.equal(manualRequestWaitMilliseconds(70_001, 70_001), 0);
  assert.equal(manualRequestWaitMilliseconds(70_001, 80_000), 0);
});

test("manual round posts every reader before any bounded follow-up read", async () => {
  const calls = [];
  const readTokens = ["reader-1", "reader-2", "reader-3"];
  const readyAt = [0, 0, 0];
  let identifier = 0;
  const pending = await runManualRequestRound({
    measured: async (category, path, options) => {
      calls.push({ category, options, path });
      return category === "manualRequests"
        ? { status: 202, text: expiry }
        : { status: 200, text: "snapshot" };
    },
    now: () => 1_000,
    readTokens,
    readyAt,
    requestIDFactory: () => `${identifier += 1}`.padStart(32, "0"),
    wait: async () => { throw new Error("initial round must not wait"); },
  });

  assert.deepEqual(calls.slice(0, 3).map((call) => call.category), [
    "manualRequests", "manualRequests", "manualRequests",
  ]);
  assert.deepEqual(calls.slice(0, 3).map((call) => call.options.token), readTokens);
  assert.equal(calls.slice(3).every((call) => call.category === "followUpReads"), true);
  assert.equal(calls.length, 33);
  assert.deepEqual(readyAt, [61_001, 61_001, 61_001]);
  assert.deepEqual(pending, [
    { requestID: "00000000000000000000000000000001" },
    { requestID: "00000000000000000000000000000002" },
    { requestID: "00000000000000000000000000000003" },
  ]);
});
