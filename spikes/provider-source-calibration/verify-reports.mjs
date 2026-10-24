#!/usr/bin/env node

import { readdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const CODEX_TOP_LEVEL_KEYS = new Set([
  "childExit",
  "events",
  "exitedAfterStdinClose",
  "failures",
  "finishedAt",
  "formatVersion",
  "limits",
  "startedAt",
  "stderrBytesDiscarded",
  "stdinClosedAt",
]);
const CODEX_EVENT_KEYS = new Map([
  ["initialized", new Set(["at", "frameBytes", "kind", "latencyMs", "resultKeys"])],
  ["account-read", new Set([
    "accountKind", "accountType", "at", "bounds", "frameBytes", "kind", "latencyMs",
    "requiresOpenaiAuth", "requiresOpenaiAuthType", "topLevelKeys",
  ])],
  ["rate-limit-read", new Set([
    "at", "bounds", "compatibility", "defaultBucket", "elapsedMs", "kind", "latencyMs",
    "accountIdentifierClassification", "multiBucketCount", "multiBucketShapes", "multiBucketType",
    "reason", "topLevelKeys",
  ])],
  ["read-coalesced", new Set(["at", "kind", "reason"])],
  ["rate-limit-update-notification", new Set([
    "at", "frameBytes", "kind", "maxDepth", "maxStringBytes", "parameterKeys",
  ])],
  ["update-refetch-rate-limited", new Set(["at", "kind"])],
  ["other-message", new Set(["at", "kind", "method"])],
]);
const CLAUDE_EVENT_KEYS = new Set([
  "activity",
  "advanceObservedAt",
  "at",
  "formatVersion",
  "inputBytes",
  "invocation",
  "label",
  "observedAtReason",
  "rateLimitType",
  "sessionIdPresent",
  "topLevelKeys",
  "versionType",
  "windows",
]);
const CLAUDE_WINDOW_KEYS = new Set([
  "keys",
  "kind",
  "resetsAtPlausibility",
  "resetsAtType",
  "type",
  "usedPercentageType",
  "usedPercentageValid",
  "validObject",
]);
const RAW_VALUE_KEYS = new Set([
  "accountId",
  "balance",
  "limitId",
  "limitName",
  "planType",
  "prompt",
  "resetsAt",
  "resets_at",
  "response",
  "session_id",
  "usedPercent",
  "used_percentage",
]);

function parseArguments(argv) {
  if (argv.length !== 4 || argv[0] !== "--mode" || argv[2] !== "--root"
      || !["codex", "combined", "claude"].includes(argv[1])) {
    throw new Error("usage: node verify-reports.mjs --mode codex|combined|claude --root ROOT");
  }
  const mode = argv[1];
  const root = path.resolve(argv[3]);
  if (!root.startsWith("/private/tmp/reset-radar-source-calibration.")) {
    throw new Error("--root must be a Reset Radar source-calibration directory under /private/tmp");
  }
  return { mode, root };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function exactKeys(object, allowed, description) {
  assert(object && typeof object === "object" && !Array.isArray(object), `${description} is not an object`);
  const unexpected = Object.keys(object).filter((key) => !allowed.has(key));
  assert(unexpected.length === 0, `${description} has unexpected keys: ${unexpected.join(", ")}`);
}

function rejectRawValueKeys(value, description) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => rejectRawValueKeys(item, `${description}[${index}]`));
    return;
  }
  if (value == null || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    assert(!RAW_VALUE_KEYS.has(key), `${description} contains forbidden raw-value key ${key}`);
    rejectRawValueKeys(child, `${description}.${key}`);
  }
}

async function readJsonLines(filePath) {
  const text = await readFile(filePath, "utf8");
  return text.split("\n").filter(Boolean).map((line, index) => {
    try {
      return JSON.parse(line);
    } catch {
      throw new Error(`${path.basename(filePath)} line ${index + 1} is not valid JSON`);
    }
  });
}

function verifyCodex(report) {
  exactKeys(report, CODEX_TOP_LEVEL_KEYS, "Codex report");
  rejectRawValueKeys(report, "Codex report");
  assert(report.formatVersion === 2, "unexpected Codex report version");
  assert(Array.isArray(report.failures) && report.failures.length === 0, "Codex report contains failures");
  assert(report.exitedAfterStdinClose === true, "Codex app-server did not exit after stdin closed");
  for (const event of report.events) {
    assert(CODEX_EVENT_KEYS.has(event.kind), `Codex report has unknown event kind ${event.kind}`);
    exactKeys(event, CODEX_EVENT_KEYS.get(event.kind), `Codex ${event.kind} event`);
  }
  const reads = report.events.filter((event) => event.kind === "rate-limit-read");
  const accountReads = report.events.filter((event) => event.kind === "account-read");
  assert(accountReads.length === 1, "Codex report must contain exactly one account-status read");
  const accountRead = accountReads[0];
  assert(accountRead.latencyMs <= 10_000, "Codex account read exceeded timeout");
  assert(accountRead.accountType === "string", "Codex account discriminator has the wrong type");
  assert(accountRead.accountKind === "chatgpt", "Codex account is not a supported ChatGPT account");
  assert(accountRead.requiresOpenaiAuthType === "boolean", "Codex authentication discriminator has the wrong type");
  assert(accountRead.requiresOpenaiAuth === false, "Codex account is not structurally authenticated");
  assert(Object.values(accountRead.bounds).every((value) => value === true), "Codex account read exceeded a safety bound");
  const scheduled = reads.filter((event) => event.reason === "initial" || event.reason === "scheduled-poll");
  assert(scheduled.length === 7, "Codex report must contain one initial and six scheduled reads");
  for (const read of reads) {
    assert(read.accountIdentifierClassification === "present-string", "Codex rate-limit account identifier is absent or malformed");
    assert(Number.isFinite(read.latencyMs) && read.latencyMs <= 10_000, "Codex read exceeded timeout");
    assert(
      read.defaultBucket?.status === "unique" || read.defaultBucket?.status === "compatibility-only",
      "Codex default bucket was not identified safely",
    );
    assert(read.bounds?.withinFrameBound === true, "Codex frame bound failed");
    assert(read.bounds?.withinStringBound === true, "Codex string bound failed");
    assert(read.bounds?.withinDepthBound === true, "Codex depth bound failed");
    assert(read.bounds?.withinWindowBound === true, "Codex window bound failed");
  }
  for (let index = 1; index < scheduled.length; index += 1) {
    assert(scheduled[index].elapsedMs - scheduled[index - 1].elapsedMs <= 15 * 60_000, "Codex read gap exceeded 15 minutes");
  }
  const latencies = reads.map((read) => read.latencyMs);
  return {
    readCount: reads.length,
    scheduledReadCount: scheduled.length,
    latencyMinimumMs: Math.min(...latencies),
    latencyMaximumMs: Math.max(...latencies),
    maximumFrameBytes: Math.max(...reads.map((read) => read.bounds.frameBytes)),
    maximumStringBytes: Math.max(...reads.map((read) => read.bounds.maxStringBytes)),
    maximumDepth: Math.max(...reads.map((read) => read.bounds.maxDepth)),
    maximumBucketEntryCount: Math.max(...reads.map((read) => read.bounds.bucketEntryCount)),
    maximumCandidateWindowCount: Math.max(...reads.map((read) => read.bounds.candidateWindowCount)),
    accountIdentifierClassifications: [...new Set(reads.map((read) => read.accountIdentifierClassification))],
    accountStatusChecks: "pass",
    defaultBucketStatuses: [...new Set(reads.map((read) => read.defaultBucket.status))].sort(),
    updateNotificationObserved: report.events.some((event) => event.kind === "rate-limit-update-notification"),
    currentDataWindowMinutes: 15,
    currentDataWindowTechnicalChecks: "pass",
  };
}

function verifyClaude(events, label) {
  assert(events.length > 0, `Claude ${label} report is empty`);
  events.forEach((event, index) => {
    exactKeys(event, CLAUDE_EVENT_KEYS, `Claude ${label} event`);
    rejectRawValueKeys(event, `Claude ${label} event`);
    assert(event.formatVersion === 1, `unexpected Claude ${label} event version`);
    assert(event.label === label, `Claude ${label} report contains another label`);
    assert(event.invocation === index + 1, `Claude ${label} invocation sequence is not isolated and contiguous`);
    if (index > 0) {
      assert(Date.parse(event.at) >= Date.parse(events[index - 1].at), `Claude ${label} timestamps are not ordered`);
    }
    assert(!["invalid", "decreased"].includes(event.activity), `Claude ${label} activity signal failed`);
    assert(event.advanceObservedAt === (event.observedAtReason !== "retain-prior-observed-at"), `Claude ${label} observation decision is inconsistent`);
    for (const window of event.windows) {
      exactKeys(window, CLAUDE_WINDOW_KEYS, `Claude ${label} window`);
      assert(window.validObject === true, `Claude ${label} window is not an object`);
      if (window.kind !== "spend_limit") {
        assert(window.usedPercentageValid === true, `Claude ${label} percentage shape is invalid`);
      }
      assert(window.resetsAtPlausibility !== "invalid", `Claude ${label} reset shape is invalid`);
    }
  });
  const advancing = events.filter((event) => event.advanceObservedAt);
  const increased = events.filter((event) => event.activity === "increased");
  const idle = events.filter((event) => event.activity === "unchanged" && event.advanceObservedAt === false);
  assert(advancing.length >= 2, `Claude ${label} needs two response-linked observations`);
  assert(increased.length >= 1, `Claude ${label} needs an activity increase`);
  assert(idle.length >= 1, `Claude ${label} needs an idle rerun`);
  assert(events.some((event) => event.windows.some((window) => window.kind !== "spend_limit")), `Claude ${label} has no normal rate-limit window`);
  return { advancing, increased, idle };
}

function verifySixtyMinutes(events, increased) {
  return increased.some((fresh) => {
    const freshTime = Date.parse(fresh.at);
    return events.some((event) => event.activity === "unchanged"
      && event.advanceObservedAt === false
      && Date.parse(event.at) - freshTime >= 60 * 60_000);
  });
}

async function run() {
  const { mode, root } = parseArguments(process.argv.slice(2));
  const summary = { formatVersion: 2, mode, privacyShapeChecks: "pass" };
  if (mode !== "claude") {
    const codexReportNames = (await readdir(root))
      .filter((name) => /^codex-[1-9][0-9]*-report\.json$/.test(name))
      .sort((left, right) => Number(left.match(/[0-9]+/u)[0]) - Number(right.match(/[0-9]+/u)[0]));
    assert(codexReportNames.length > 0, "no explicitly selected Codex profile reports found");
    codexReportNames.forEach((name, index) => {
      assert(name === `codex-${index + 1}-report.json`, "Codex profile report sequence is not contiguous");
    });
    const codexSummaries = [];
    for (const name of codexReportNames) {
      const report = JSON.parse(await readFile(path.join(root, name), "utf8"));
      codexSummaries.push(verifyCodex(report));
    }
    summary.codex = {
      profileCount: codexSummaries.length,
      profiles: codexSummaries,
      allProfileTechnicalChecks: codexSummaries.every((profile) => profile.updateNotificationObserved)
        ? "pass"
        : "deferred",
    };
  }
  if (mode !== "codex") {
    const claudeA = await readJsonLines(path.join(root, "claude-A-report.jsonl"));
    const claudeB = await readJsonLines(path.join(root, "claude-B-report.jsonl"));
    const a = verifyClaude(claudeA, "A");
    const b = verifyClaude(claudeB, "B");
    assert(a.advancing.length + b.advancing.length >= 4, "Claude needs four response-linked observations across two sessions");
    assert(verifySixtyMinutes(claudeA, a.increased), "Claude A lacks an unchanged idle event at least 60 minutes after an increase");
    assert(b.advancing.some((bEvent) => claudeA.some((aEvent) =>
      aEvent.activity === "unchanged"
        && aEvent.advanceObservedAt === false
        && Date.parse(aEvent.at) > Date.parse(bEvent.at))),
    "Claude A lacks an unchanged idle event after Claude B activity");
    summary.claudeCode = {
      labels: ["A", "B"],
      eventCount: claudeA.length + claudeB.length,
      advancingEventCount: a.advancing.length + b.advancing.length,
      increasedEventCount: a.increased.length + b.increased.length,
      idleEventCount: a.idle.length + b.idle.length,
      windowKinds: [...new Set([...claudeA, ...claudeB].flatMap((event) => event.windows.map((window) => window.kind)))].sort(),
      currentDataWindowMinutes: 60,
      currentDataWindowTechnicalChecks: "pass",
      crossSessionIsolationChecks: "pass",
    };
  }
  const outputPath = path.join(root, "verification-summary.json");
  const temporaryPath = `${outputPath}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(summary, null, 2)}\n`, { mode: 0o600 });
  await rename(temporaryPath, outputPath);
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

await run();

