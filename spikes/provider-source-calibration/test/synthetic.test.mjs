import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmod, copyFile, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testRoot = path.dirname(fileURLToPath(import.meta.url));
const spikeRoot = path.dirname(testRoot);

const standardCompatibility = {
  primary: { durationClass: "300" },
  secondary: { durationClass: "10080" },
};

async function execute(command, arguments_, options = {}) {
  return await new Promise((resolve, reject) => {
    const child = spawn(command, arguments_, { ...options, stdio: ["pipe", "pipe", "pipe"] });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve({
      code,
      signal,
      stdout: Buffer.concat(stdout).toString("utf8"),
      stderr: Buffer.concat(stderr).toString("utf8"),
    }));
    if (options.input !== undefined) child.stdin.end(options.input);
    else child.stdin.end();
  });
}

test("Codex report is sanitized for unique and compatibility-only buckets", async () => {
  const root = await mkdtemp(path.join("/private/tmp", "reset-radar-source-calibration.test."));
  try {
    for (const mode of ["unique", "compatibility-only"]) {
      const mockPath = path.join(root, `mock-${mode}`);
      await copyFile(path.join(testRoot, "mock-codex.mjs"), mockPath);
      await chmod(mockPath, 0o700);
      const reportPath = path.join(root, `${mode}.json`);
      const result = await execute(process.execPath, [
        path.join(spikeRoot, "codex-calibration.mjs"),
        "--codex", mockPath,
        "--report", reportPath,
        "--duration-minutes", "0",
      ]);
      assert.equal(result.code, 0, result.stderr);
      const reportText = await readFile(reportPath, "utf8");
      for (const secret of [
        "DO_NOT_PERSIST_LIMIT_ID_SENTINEL",
        "DO_NOT_PERSIST_LIMIT_NAME_SENTINEL",
        "DO_NOT_PERSIST_BUCKET_KEY_SENTINEL",
        "DO_NOT_PERSIST_ACCOUNT_ID_SENTINEL",
        "1999999999",
        "2000000000",
      ]) {
        assert.equal(reportText.includes(secret), false, `persisted ${secret}`);
      }
      const report = JSON.parse(reportText);
      assert.deepEqual(report.failures, []);
      assert.equal(report.exitedAfterStdinClose, true);
      const read = report.events.find((event) => event.kind === "rate-limit-read");
      assert.equal(read.defaultBucket.status, mode === "unique" ? "unique" : "compatibility-only");
      assert.equal(read.bounds.withinFrameBound, true);
      assert.equal(read.bounds.withinStringBound, true);
      assert.equal(read.bounds.withinDepthBound, true);
      assert.equal(read.bounds.withinBucketEntryBound, true);
      assert.equal(read.bounds.withinWindowBound, true);
      assert.equal(read.accountIdentifierClassification, "present-string");
      assert.equal(read.compatibility.primary.durationClass, "300");
      assert.equal(read.compatibility.secondary.durationClass, "10080");
      const accountRead = report.events.find((event) => event.kind === "account-read");
      assert.equal(accountRead.accountKind, "chatgpt");
      assert.equal(accountRead.requiresOpenaiAuth, true);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("Claude recorder classifies activity without persisting raw values", async () => {
  const root = await mkdtemp(path.join("/private/tmp", "reset-radar-source-calibration.test."));
  try {
    const recorder = path.join(spikeRoot, "claude-recorder.mjs");
    const payloads = [
      { duration: 10, percentage: 37 },
      { duration: 10, percentage: 37 },
      { duration: 20, percentage: 52 },
    ];
    for (const payload of payloads) {
      const input = JSON.stringify({
        version: "DO_NOT_PERSIST_VERSION_SENTINEL",
        session_id: "DO_NOT_PERSIST_SESSION_SENTINEL",
        cost: { total_api_duration_ms: payload.duration },
        rate_limits: {
          five_hour: {
            used_percentage: payload.percentage,
            resets_at: "2099-05-06T07:08:09Z",
          },
        },
        prompt: "DO_NOT_PERSIST_PROMPT_SENTINEL",
      });
      const result = await execute(process.execPath, [recorder, "--root", root, "--label", "A"], { input });
      assert.equal(result.code, 0, result.stderr);
    }
    const reportText = await readFile(path.join(root, "claude-A-report.jsonl"), "utf8");
    for (const secret of [
      "DO_NOT_PERSIST_VERSION_SENTINEL",
      "DO_NOT_PERSIST_SESSION_SENTINEL",
      "DO_NOT_PERSIST_PROMPT_SENTINEL",
      "2099-05-06T07:08:09Z",
    ]) {
      assert.equal(reportText.includes(secret), false, `persisted ${secret}`);
    }
    const events = reportText.trim().split("\n").map(JSON.parse);
    assert.deepEqual(events.map((event) => event.activity), ["first-observed", "unchanged", "increased"]);
    assert.deepEqual(events.map((event) => event.advanceObservedAt), [true, false, true]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("Claude recorder rejects oversized input", async () => {
  const root = await mkdtemp(path.join("/private/tmp", "reset-radar-source-calibration.test."));
  try {
    const input = JSON.stringify({ padding: "x".repeat(1024 * 1024) });
    const result = await execute(process.execPath, [
      path.join(spikeRoot, "claude-recorder.mjs"),
      "--root", root,
      "--label", "A",
    ], { input });
    assert.notEqual(result.code, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("report verifier accepts a complete sanitized observation", async () => {
  const root = await mkdtemp(path.join("/private/tmp", "reset-radar-source-calibration.test."));
  try {
    const base = Date.parse("2026-01-01T00:00:00.000Z");
    const reads = Array.from({ length: 7 }, (_, index) => ({
      at: new Date(base + index * 5 * 60_000).toISOString(),
      elapsedMs: index * 5 * 60_000,
      kind: "rate-limit-read",
      reason: index === 0 ? "initial" : "scheduled-poll",
      latencyMs: 12 + index,
      accountIdentifierClassification: "present-string",
      defaultBucket: { status: "unique", candidateCount: 1, basis: ["complete-snapshot-equality"] },
      compatibility: standardCompatibility,
      bounds: {
        frameBytes: 512,
        maxStringBytes: 20,
        maxDepth: 5,
        bucketEntryCount: 2,
        candidateWindowCount: 4,
        withinFrameBound: true,
        withinStringBound: true,
        withinDepthBound: true,
        withinBucketEntryBound: true,
        withinWindowBound: true,
      },
    }));
    const codexReport = JSON.stringify({
      formatVersion: 2,
      startedAt: new Date(base).toISOString(),
      limits: {},
      events: [
        {
          at: new Date(base).toISOString(),
          kind: "account-read",
          latencyMs: 10,
          frameBytes: 256,
          topLevelKeys: ["account", "requiresOpenaiAuth"],
          accountType: "string",
          accountKind: "chatgpt",
          requiresOpenaiAuthType: "boolean",
          requiresOpenaiAuth: true,
          bounds: { withinFrameBound: true, withinStringBound: true, withinDepthBound: true },
        },
        ...reads,
        { at: new Date(base + 1_000).toISOString(), kind: "rate-limit-update-notification" },
      ],
      failures: [],
      stderrBytesDiscarded: 0,
      stdinClosedAt: new Date(base + 31 * 60_000).toISOString(),
      exitedAfterStdinClose: true,
      childExit: { code: 0, signal: null },
      finishedAt: new Date(base + 31 * 60_000).toISOString(),
    });
    await writeFile(path.join(root, "codex-1-report.json"), codexReport, { mode: 0o600 });
    await writeFile(path.join(root, "codex-2-report.json"), codexReport, { mode: 0o600 });

    const event = (label, invocation, offsetMinutes, activity, advanceObservedAt) => ({
      formatVersion: 1,
      at: new Date(base + offsetMinutes * 60_000).toISOString(),
      label,
      invocation,
      inputBytes: 300,
      topLevelKeys: ["cost", "rate_limits", "session_id", "version"],
      versionType: "string",
      sessionIdPresent: true,
      activity,
      rateLimitType: "object",
      windows: [{
        kind: "five_hour",
        type: "object",
        validObject: true,
        keys: ["resets_at", "used_percentage"],
        usedPercentageType: "number",
        usedPercentageValid: true,
        resetsAtType: "number",
        resetsAtPlausibility: "parseable",
      }],
      advanceObservedAt,
      observedAtReason: advanceObservedAt ? "activity-increased" : "retain-prior-observed-at",
    });
    const claudeA = [
      event("A", 1, 0, "first-observed", true),
      event("A", 2, 1, "unchanged", false),
      event("A", 3, 2, "increased", true),
      event("A", 4, 67, "unchanged", false),
    ];
    const claudeB = [
      event("B", 1, 3, "first-observed", true),
      event("B", 2, 4, "unchanged", false),
      event("B", 3, 5, "increased", true),
    ];
    await writeFile(path.join(root, "claude-A-report.jsonl"), `${claudeA.map(JSON.stringify).join("\n")}\n`, { mode: 0o600 });
    await writeFile(path.join(root, "claude-B-report.jsonl"), `${claudeB.map(JSON.stringify).join("\n")}\n`, { mode: 0o600 });

    const result = await execute(process.execPath, [
      path.join(spikeRoot, "verify-reports.mjs"),
      "--mode", "combined",
      "--root", root,
    ]);
    assert.equal(result.code, 0, result.stderr);
    const summary = JSON.parse(result.stdout);
    assert.equal(summary.codex.profileCount, 2);
    assert.equal(summary.codex.allProfileTechnicalChecks, "pass");
    assert.equal(summary.codex.profiles.every((profile) => profile.updateNotificationObserved), true);
    assert.equal(summary.codex.profiles.every((profile) => profile.currentDataWindowTechnicalChecks === "pass"), true);
    assert.equal(summary.claudeCode.currentDataWindowTechnicalChecks, "pass");
    assert.equal(summary.privacyShapeChecks, "pass");

    // Claude Code-only verification needs no Codex report and emits no Codex section.
    await rm(path.join(root, "codex-1-report.json"));
    await rm(path.join(root, "codex-2-report.json"));
    const claudeOnly = await execute(process.execPath, [
      path.join(spikeRoot, "verify-reports.mjs"),
      "--mode", "claude",
      "--root", root,
    ]);
    assert.equal(claudeOnly.code, 0, claudeOnly.stderr);
    const claudeSummary = JSON.parse(claudeOnly.stdout);
    assert.equal(claudeSummary.mode, "claude");
    assert.equal(Object.hasOwn(claudeSummary, "codex"), false);
    assert.equal(claudeSummary.claudeCode.currentDataWindowTechnicalChecks, "pass");
    const codexRequired = await execute(process.execPath, [
      path.join(spikeRoot, "verify-reports.mjs"),
      "--mode", "combined",
      "--root", root,
    ]);
    assert.notEqual(codexRequired.code, 0);
    await rm(path.join(root, "claude-B-report.jsonl"));
    const missing = await execute(process.execPath, [
      path.join(spikeRoot, "verify-reports.mjs"),
      "--mode", "claude",
      "--root", root,
    ]);
    assert.notEqual(missing.code, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("Codex-only verifier does not require or inspect Claude reports", async () => {
  const root = await mkdtemp(path.join("/private/tmp", "reset-radar-source-calibration.test."));
  try {
    const base = Date.parse("2026-01-01T00:00:00.000Z");
    const reads = Array.from({ length: 7 }, (_, index) => ({
      at: new Date(base + index * 5 * 60_000).toISOString(),
      elapsedMs: index * 5 * 60_000,
      kind: "rate-limit-read",
      reason: index === 0 ? "initial" : "scheduled-poll",
      latencyMs: 10,
      accountIdentifierClassification: "present-string",
      defaultBucket: { status: "compatibility-only", candidateCount: 0, basis: [] },
      compatibility: standardCompatibility,
      bounds: {
        frameBytes: 100,
        maxStringBytes: 10,
        maxDepth: 4,
        bucketEntryCount: 0,
        candidateWindowCount: 2,
        withinFrameBound: true,
        withinStringBound: true,
        withinDepthBound: true,
        withinBucketEntryBound: true,
        withinWindowBound: true,
      },
    }));
    await writeFile(path.join(root, "codex-1-report.json"), JSON.stringify({
      formatVersion: 2,
      startedAt: new Date(base).toISOString(),
      limits: {},
      events: [{
        at: new Date(base).toISOString(),
        kind: "account-read",
        latencyMs: 9,
        frameBytes: 100,
        topLevelKeys: ["account", "requiresOpenaiAuth"],
        accountType: "string",
        accountKind: "chatgpt",
        requiresOpenaiAuthType: "boolean",
        requiresOpenaiAuth: true,
        bounds: { withinFrameBound: true, withinStringBound: true, withinDepthBound: true },
      }, ...reads],
      failures: [],
      stderrBytesDiscarded: 0,
      stdinClosedAt: new Date(base + 31 * 60_000).toISOString(),
      exitedAfterStdinClose: true,
      childExit: { code: 0, signal: null },
      finishedAt: new Date(base + 31 * 60_000).toISOString(),
    }), { mode: 0o600 });
    const result = await execute(process.execPath, [
      path.join(spikeRoot, "verify-reports.mjs"),
      "--mode", "codex",
      "--root", root,
    ]);
    assert.equal(result.code, 0, result.stderr);
    const summary = JSON.parse(result.stdout);
    assert.equal(summary.mode, "codex");
    assert.equal(Object.hasOwn(summary, "claudeCode"), false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});


test("duration-class check accepts one initial read and rejects a missing weekly window", async () => {
  const root = await mkdtemp(path.join("/private/tmp", "reset-radar-source-calibration.test."));
  try {
    const base = Date.parse("2026-01-01T00:00:00.000Z");
    const report = (compatibility) => JSON.stringify({
      formatVersion: 2,
      startedAt: new Date(base).toISOString(),
      limits: {},
      events: [{
        at: new Date(base).toISOString(),
        kind: "account-read",
        latencyMs: 9,
        frameBytes: 100,
        topLevelKeys: ["account", "requiresOpenaiAuth"],
        accountType: "string",
        accountKind: "chatgpt",
        requiresOpenaiAuthType: "boolean",
        requiresOpenaiAuth: true,
        bounds: { withinFrameBound: true, withinStringBound: true, withinDepthBound: true },
      }, {
        at: new Date(base).toISOString(),
        elapsedMs: 0,
        kind: "rate-limit-read",
        reason: "initial",
        latencyMs: 10,
        accountIdentifierClassification: "present-string",
        defaultBucket: { status: "compatibility-only", candidateCount: 0, basis: [] },
        compatibility,
        bounds: {
          frameBytes: 100, maxStringBytes: 10, maxDepth: 4, bucketEntryCount: 0,
          candidateWindowCount: 2, withinFrameBound: true, withinStringBound: true,
          withinDepthBound: true, withinBucketEntryBound: true, withinWindowBound: true,
        },
      }],
      failures: [],
      stderrBytesDiscarded: 0,
      stdinClosedAt: new Date(base + 1_000).toISOString(),
      exitedAfterStdinClose: true,
      childExit: { code: 0, signal: null },
      finishedAt: new Date(base + 1_000).toISOString(),
    });
    const verify = (extra = []) => execute(process.execPath, [
      path.join(spikeRoot, "verify-reports.mjs"), "--mode", "codex", "--root", root, ...extra,
    ]);
    const file = path.join(root, "codex-1-report.json");

    await writeFile(file, report(standardCompatibility), { mode: 0o600 });
    const accepted = await verify(["--duration-class-check"]);
    assert.equal(accepted.code, 0, accepted.stderr);
    const summary = JSON.parse(accepted.stdout);
    assert.equal(summary.codex.allProfileTechnicalChecks, "duration-class-only");
    assert.equal(summary.codex.profiles[0].durationClassCheck, "pass");
    // The full 30-minute check still demands seven reads.
    assert.notEqual((await verify()).code, 0);

    for (const weekly of ["other", "absent", "300"]) {
      await writeFile(file, report({
        primary: { durationClass: "300" }, secondary: { durationClass: weekly },
      }), { mode: 0o600 });
      assert.notEqual((await verify(["--duration-class-check"])).code, 0, weekly);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
