import assert from "node:assert/strict";
import test from "node:test";

import {
  MAX_SLOT_LAG_MS,
  MANUAL_REQUEST_SPACING_MS,
  manualRequestWaitMilliseconds,
  observedElapsedMilliseconds,
  parseManualRequestResponse,
  runManualRequestRound,
  sampleSlotDelayMilliseconds,
  validateSoakAccounting,
} from "./soak-remote.mjs";

const expiry = '{"expiresAt":"2023-11-14T22:18:20.000Z","protocolVersion":1}';

test("manual request response classification distinguishes relay and unrecognized 429", () => {
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
    /Unrecognized HTTP 429 stopped the scheduled sample/,
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
  assert.throws(() => manualRequestWaitMilliseconds(Number.NaN, 80_000), /invalid/);
  assert.throws(() => manualRequestWaitMilliseconds(70_001, Number.POSITIVE_INFINITY), /invalid/);
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

test("manual round settles every concurrent submission before surfacing failure", async () => {
  const controls = [];
  let identifier = 0;
  const round = runManualRequestRound({
    measured: async (category) => {
      if (category !== "manualRequests") return { status: 200, text: "snapshot" };
      return new Promise((resolve, reject) => { controls.push({ reject, resolve }); });
    },
    now: () => 1_000,
    readTokens: ["reader-1", "reader-2", "reader-3"],
    readyAt: [0, 0, 0],
    requestIDFactory: () => `${identifier += 1}`.padStart(32, "0"),
    wait: async () => {},
  });
  let settled = false;
  const observed = round.then(
    () => { settled = true; },
    (error) => { settled = true; throw error; },
  );
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(controls.length, 3);
  controls[0].reject(new Error("private failure"));
  await new Promise((resolve) => setImmediate(resolve));
  const settledEarly = settled;
  controls[1].resolve({ status: 202, text: expiry });
  controls[2].resolve({ status: 202, text: expiry });
  await assert.rejects(observed, /Manual request round failed/);
  assert.equal(settledEarly, false);
});

test("manual round rejects invalid schedule state and request IDs before any request", async () => {
  let calls = 0;
  const base = {
    measured: async () => { calls += 1; return { status: 202, text: expiry }; },
    now: () => 1_000,
    readTokens: ["reader-1", "reader-2", "reader-3"],
    readyAt: [0, 0, 0],
    wait: async () => {},
  };
  await assert.rejects(
    () => runManualRequestRound({ ...base, readyAt: [0, Number.NaN, 0] }),
    /schedule is invalid/,
  );
  await assert.rejects(
    () => runManualRequestRound({ ...base, requestIDFactory: () => "invalid" }),
    /identifiers are invalid/,
  );
  await assert.rejects(
    () => runManualRequestRound({ ...base, requestIDFactory: () => "1".repeat(32) }),
    /identifiers are invalid/,
  );
  assert.equal(calls, 0);
});

test("sample scheduling rejects compressed catch-up and invalid elapsed time", () => {
  assert.equal(MAX_SLOT_LAG_MS, 5_050);
  assert.equal(sampleSlotDelayMilliseconds(10_000, 9_750), 250);
  assert.equal(sampleSlotDelayMilliseconds(10_000, 10_000 + MAX_SLOT_LAG_MS), 0);
  assert.throws(
    () => sampleSlotDelayMilliseconds(10_000, 10_000 + MAX_SLOT_LAG_MS + 1),
    /fell more than one slot behind/,
  );
  assert.throws(() => sampleSlotDelayMilliseconds(Number.NaN, 10_000), /invalid/);
  assert.equal(observedElapsedMilliseconds(1_000, 1_801_000), 1_800_000);
  assert.throws(() => observedElapsedMilliseconds(2_000, 1_000), /invalid/);
});

test("sample accounting is order-independent and rejects invalid measurements", () => {
  const planned = { alpha: 2, beta: 1, slots: 3 };
  const counts = { beta: 1, alpha: 2 };
  const latencies = new Map([["beta", [3]], ["alpha", [1, 2]]]);
  assert.doesNotThrow(() => validateSoakAccounting(planned, counts, latencies, 42));
  assert.throws(
    () => validateSoakAccounting(planned, { ...counts, alpha: 1 }, latencies, 42),
    /counts did not reconcile/,
  );
  assert.throws(
    () => validateSoakAccounting(planned, counts, new Map([["alpha", [1, Number.NaN]], ["beta", [3]]]), 42),
    /latency measurements were invalid/,
  );
  assert.throws(() => validateSoakAccounting(planned, counts, latencies, -1), /response bytes were invalid/);
});
