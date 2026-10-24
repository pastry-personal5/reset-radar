import assert from "node:assert/strict";
import test from "node:test";

import {
  enqueueFollowUpReads,
  FOLLOW_UP_READ_COUNT,
  MAX_SLOT_LAG_MS,
  MANUAL_REQUEST_SPACING_MS,
  manualRequestWaitMilliseconds,
  observedElapsedMilliseconds,
  parseManualRequestResponse,
  runFollowUpReadsForSlot,
  runManualRequestRound,
  sampleCompletionTarget,
  sampleSlotDelayMilliseconds,
  validateSoakAccounting,
} from "./soak-remote.mjs";
import { SAMPLE_SECONDS, sampleWorkload, SLOT_SECONDS } from "./harness-core.mjs";

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

test("manual round returns every accepted reader before follow-up scheduling", async () => {
  const calls = [];
  const readTokens = ["reader-1", "reader-2", "reader-3"];
  const readyAt = [0, 0, 0];
  let identifier = 0;
  const pending = await runManualRequestRound({
    measured: async (category, path, options) => {
      calls.push({ category, options, path });
      return { status: 202, text: expiry };
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
  assert.equal(calls.length, 3);
  assert.deepEqual(readyAt, [61_001, 61_001, 61_001]);
  assert.deepEqual(pending, [
    { requestID: "00000000000000000000000000000001", token: "reader-1" },
    { requestID: "00000000000000000000000000000002", token: "reader-2" },
    { requestID: "00000000000000000000000000000003", token: "reader-3" },
  ]);
});

test("follow-up schedule spreads each reader across ten slots and includes the sample tail", () => {
  const schedule = new Map();
  const accepted = [
    { requestID: "1".repeat(32), token: "reader-1" },
    { requestID: "2".repeat(32), token: "reader-2" },
    { requestID: "3".repeat(32), token: "reader-3" },
  ];
  const planned = sampleWorkload();
  const finalManualSlot = planned.slots - ((planned.slots - 1) % 12);
  let finalFollowUpSlot = 0;
  for (let slot = 1; slot <= planned.slots; slot += 1) {
    if ((slot - 1) % 12 === 0) {
      finalFollowUpSlot = enqueueFollowUpReads(schedule, slot, accepted);
    }
  }

  assert.equal(FOLLOW_UP_READ_COUNT, 10);
  assert.equal([...schedule.values()].reduce((total, tokens) => total + tokens.length, 0), planned.followUpReads);
  assert.equal(finalFollowUpSlot, finalManualSlot + FOLLOW_UP_READ_COUNT - 1);
  assert.ok(finalFollowUpSlot > planned.slots);
  assert.ok((finalFollowUpSlot - 1) * SLOT_SECONDS * 1000 > SAMPLE_SECONDS * 1000);
  assert.ok((finalFollowUpSlot - 1) * SLOT_SECONDS * 1000 <= SAMPLE_SECONDS * 1000 + MAX_SLOT_LAG_MS);
  assert.equal(sampleCompletionTarget(0, finalFollowUpSlot), 1_802_850);
  assert.throws(() => sampleCompletionTarget(0, Number.NaN), /completion schedule was invalid/);
  for (let offset = 0; offset < FOLLOW_UP_READ_COUNT; offset += 1) {
    assert.deepEqual(schedule.get(finalManualSlot + offset), ["reader-1", "reader-2", "reader-3"]);
  }

  const snapshot = structuredClone(schedule);
  assert.throws(
    () => enqueueFollowUpReads(schedule, finalManualSlot + 1, accepted),
    /overlapped an existing slot/,
  );
  assert.deepEqual(schedule, snapshot);
});

test("due follow-up reads dispatch concurrently and settle together", async () => {
  const schedule = new Map([[7, ["reader-1", "reader-2", "reader-3"]]]);
  const controls = [];
  const round = runFollowUpReadsForSlot({
    measured: async (category, path, options) => {
      assert.equal(category, "followUpReads");
      assert.equal(path, "/v1/snapshot");
      return new Promise((resolve, reject) => { controls.push({ options, reject, resolve }); });
    },
    schedule,
    slot: 7,
  });
  let settled = false;
  const observed = round.then(
    (value) => { settled = true; return value; },
    (error) => { settled = true; throw error; },
  );
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(controls.map((control) => control.options.token), ["reader-1", "reader-2", "reader-3"]);
  controls[0].reject(new Error("private failure"));
  await new Promise((resolve) => setImmediate(resolve));
  const settledEarly = settled;
  controls[1].resolve({ status: 200, text: "snapshot" });
  controls[2].resolve({ status: 200, text: "snapshot" });
  await assert.rejects(observed, /Follow-up read round failed/);
  assert.equal(settledEarly, false);
  assert.equal(schedule.has(7), false);
  assert.equal(await runFollowUpReadsForSlot({ measured: async () => {}, schedule, slot: 8 }), 0);
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
