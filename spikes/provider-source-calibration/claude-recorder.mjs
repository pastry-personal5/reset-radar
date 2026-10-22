#!/usr/bin/env node

import { appendFile, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const MAX_INPUT_BYTES = 1024 * 1024;

function parseArguments(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith("--") || value === undefined) {
      throw new Error("arguments must be --name value pairs");
    }
    if (values.has(name)) throw new Error(`duplicate argument ${name}`);
    values.set(name, value);
  }
  const allowed = new Set(["--root", "--label"]);
  for (const name of values.keys()) {
    if (!allowed.has(name)) throw new Error(`unknown argument ${name}`);
  }
  for (const name of allowed) {
    if (!values.has(name)) throw new Error(`missing ${name}`);
  }
  const root = path.resolve(values.get("--root"));
  if (!root.startsWith("/private/tmp/reset-radar-source-calibration.")) {
    throw new Error("--root must be a Reset Radar source-calibration directory under /private/tmp");
  }
  const label = values.get("--label");
  if (!/^[AB]$/.test(label)) throw new Error("--label must be A or B");
  return { root, label };
}

function jsonType(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

async function run() {
  const { root, label } = parseArguments(process.argv.slice(2));
  const stateDirectory = path.join(root, "claude-state");
  const statePath = path.join(stateDirectory, `${label}.json`);
  const reportPath = path.join(root, `claude-${label}-report.jsonl`);
  await mkdir(stateDirectory, { recursive: true, mode: 0o700 });

  const chunks = [];
  let inputBytes = 0;
  for await (const chunk of process.stdin) {
    inputBytes += chunk.length;
    if (inputBytes > MAX_INPUT_BYTES) {
      throw new Error(`status-line input exceeded ${MAX_INPUT_BYTES} bytes`);
    }
    chunks.push(chunk);
  }

  let payload;
  try {
    payload = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Error("status-line input was not valid JSON");
  }

  let state = { invocationCount: 0, priorDurationMs: null, previouslyHadRateLimits: false };
  try {
    state = JSON.parse(await readFile(statePath, "utf8"));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  const duration = payload?.cost?.total_api_duration_ms;
  let activity;
  if (duration === undefined || duration === null) {
    activity = "absent";
  } else if (typeof duration !== "number" || !Number.isFinite(duration) || duration < 0) {
    activity = "invalid";
  } else if (state.priorDurationMs === null) {
    activity = "first-observed";
  } else if (duration > state.priorDurationMs) {
    activity = "increased";
  } else if (duration === state.priorDurationMs) {
    activity = "unchanged";
  } else {
    activity = "decreased";
  }

  const rateLimits = payload?.rate_limits;
  const windows = [];
  if (rateLimits && typeof rateLimits === "object" && !Array.isArray(rateLimits)) {
    for (const [kind, value] of Object.entries(rateLimits)) {
      if (value === null || typeof value !== "object" || Array.isArray(value)) {
        windows.push({ kind, type: jsonType(value), validObject: false });
        continue;
      }
      const used = value.used_percentage;
      const reset = value.resets_at;
      windows.push({
        kind,
        type: "object",
        validObject: true,
        keys: Object.keys(value).sort(),
        usedPercentageType: jsonType(used),
        usedPercentageValid: typeof used === "number"
          && Number.isFinite(used)
          && used >= 0
          && used <= 100,
        resetsAtType: jsonType(reset),
        resetsAtPlausibility:
          reset === undefined || reset === null
            ? "absent"
            : (typeof reset === "number" && Number.isFinite(reset) && reset > 0)
                || (typeof reset === "string" && !Number.isNaN(Date.parse(reset)))
              ? "parseable"
              : "invalid",
      });
    }
  }

  const normalWindows = windows.filter((window) => window.kind !== "spend_limit");
  const hasRateLimits = normalWindows.length > 0;
  const firstAppearance = hasRateLimits && !state.previouslyHadRateLimits;
  const advanceObservedAt = activity === "increased" || firstAppearance;
  const observedAtReason = activity === "increased"
    ? "activity-increased"
    : firstAppearance
      ? "first-rate-limit-appearance"
      : "retain-prior-observed-at";

  const event = {
    formatVersion: 1,
    at: new Date().toISOString(),
    label,
    invocation: state.invocationCount + 1,
    inputBytes,
    topLevelKeys: payload && typeof payload === "object" ? Object.keys(payload).sort() : [],
    versionType: jsonType(payload?.version),
    sessionIdPresent: typeof payload?.session_id === "string" && payload.session_id.length > 0,
    activity,
    rateLimitType: jsonType(rateLimits),
    windows,
    advanceObservedAt,
    observedAtReason,
  };
  await appendFile(reportPath, `${JSON.stringify(event)}\n`, { mode: 0o600 });

  state.invocationCount += 1;
  if (typeof duration === "number" && Number.isFinite(duration) && duration >= 0) {
    state.priorDurationMs = duration;
  }
  state.previouslyHadRateLimits ||= hasRateLimits;
  const temporaryStatePath = `${statePath}.tmp`;
  await writeFile(temporaryStatePath, `${JSON.stringify(state)}\n`, { mode: 0o600 });
  await rename(temporaryStatePath, statePath);
  process.stdout.write(`Reset Radar calibration ${label}: recorded\n`);
}

await run();
