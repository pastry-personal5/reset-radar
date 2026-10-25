#!/usr/bin/env node

import { spawn } from "node:child_process";
import { rename, writeFile } from "node:fs/promises";
import process from "node:process";

const LIMITS = Object.freeze({
  frameBytes: 1024 * 1024,
  stringBytes: 4 * 1024,
  nestingDepth: 32,
  bucketEntries: 128,
  candidateWindows: 128,
  requestTimeoutMs: 10_000,
});
const POLL_INTERVAL_MS = 5 * 60_000;
const UPDATE_REFETCH_FLOOR_MS = 60_000;

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
  const allowed = new Set(["--codex", "--report", "--duration-minutes"]);
  for (const name of values.keys()) {
    if (!allowed.has(name)) throw new Error(`unknown argument ${name}`);
  }
  for (const name of allowed) {
    if (!values.has(name)) throw new Error(`missing ${name}`);
  }
  const durationMinutes = Number(values.get("--duration-minutes"));
  if (!Number.isFinite(durationMinutes) || durationMinutes < 0 || durationMinutes > 120) {
    throw new Error("--duration-minutes must be between 0 and 120");
  }
  return {
    codexPath: values.get("--codex"),
    reportPath: values.get("--report"),
    durationMinutes,
  };
}

function jsonType(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function inspectValue(root) {
  const metrics = { maxDepth: 0, maxStringBytes: 0 };
  const stack = [{ value: root, depth: 0 }];
  while (stack.length > 0) {
    const { value, depth } = stack.pop();
    metrics.maxDepth = Math.max(metrics.maxDepth, depth);
    if (typeof value === "string") {
      metrics.maxStringBytes = Math.max(metrics.maxStringBytes, Buffer.byteLength(value, "utf8"));
    } else if (Array.isArray(value)) {
      for (const item of value) stack.push({ value: item, depth: depth + 1 });
    } else if (value !== null && typeof value === "object") {
      for (const [key, item] of Object.entries(value)) {
        metrics.maxStringBytes = Math.max(metrics.maxStringBytes, Buffer.byteLength(key, "utf8"));
        stack.push({ value: item, depth: depth + 1 });
      }
    }
  }
  return metrics;
}

function accountStatusShape(result) {
  const account = result?.account;
  const accountIsObject = account !== null && typeof account === "object" && !Array.isArray(account);
  return {
    accountType: account === null ? "null" : accountIsObject ? jsonType(account.type) : jsonType(account),
    accountKind: accountIsObject && typeof account.type === "string" ? account.type : null,
    requiresOpenaiAuthType: jsonType(result?.requiresOpenaiAuth),
    requiresOpenaiAuth: typeof result?.requiresOpenaiAuth === "boolean"
      ? result.requiresOpenaiAuth
      : null,
  };
}

const STANDARD_DURATION_MINUTES = new Set([300, 10_080]);

// Coarse class only: an exact value outside the two standard durations is never retained.
function durationClass(minutes) {
  if (minutes === null || minutes === undefined) return "absent";
  if (!Number.isInteger(minutes) || minutes <= 0) return "invalid";
  return STANDARD_DURATION_MINUTES.has(minutes) ? String(minutes) : "other";
}

function windowShape(window) {
  if (window === null || typeof window !== "object" || Array.isArray(window)) {
    return { type: jsonType(window), validObject: false };
  }
  return {
    type: "object",
    validObject: true,
    keys: Object.keys(window).sort(),
    usedPercentType: jsonType(window.usedPercent),
    usedPercentValid:
      Number.isInteger(window.usedPercent) && window.usedPercent >= 0 && window.usedPercent <= 100,
    durationType: jsonType(window.windowDurationMins),
    durationClass: durationClass(window.windowDurationMins),
    resetType: jsonType(window.resetsAt),
    resetPlausibility:
      window.resetsAt === null || window.resetsAt === undefined
        ? "absent"
        : Number.isInteger(window.resetsAt) && window.resetsAt > 0
          ? "positive-integer"
          : "invalid",
  };
}

function snapshotShape(snapshot) {
  if (snapshot === null || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    return { type: jsonType(snapshot), validObject: false, windowCount: 0 };
  }
  const primary = snapshot.primary == null ? null : windowShape(snapshot.primary);
  const secondary = snapshot.secondary == null ? null : windowShape(snapshot.secondary);
  return {
    type: "object",
    validObject: true,
    keys: Object.keys(snapshot).sort(),
    hasLimitId: typeof snapshot.limitId === "string" && snapshot.limitId.length > 0,
    hasLimitName: typeof snapshot.limitName === "string" && snapshot.limitName.length > 0,
    primary,
    secondary,
    windowCount: Number(primary !== null) + Number(secondary !== null),
  };
}

function structurallyEqual(left, right) {
  if (left === right) return true;
  if (jsonType(left) !== jsonType(right)) return false;
  if (Array.isArray(left)) {
    return left.length === right.length && left.every((item, index) => structurallyEqual(item, right[index]));
  }
  if (left !== null && typeof left === "object") {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    return structurallyEqual(leftKeys, rightKeys)
      && leftKeys.every((key) => structurallyEqual(left[key], right[key]));
  }
  return false;
}

function defaultBucketResult(compatibility, buckets) {
  if (buckets == null || (typeof buckets === "object" && Object.keys(buckets).length === 0)) {
    return { status: "compatibility-only", candidateCount: 0, basis: [] };
  }
  if (typeof buckets !== "object" || Array.isArray(buckets)) {
    return { status: "invalid-multi-bucket-shape", candidateCount: 0, basis: [] };
  }
  const candidates = [];
  for (const [key, value] of Object.entries(buckets)) {
    const basis = [];
    if (typeof compatibility?.limitId === "string" && compatibility.limitId.length > 0) {
      if (key === compatibility.limitId) basis.push("map-key-equals-compatibility-limit-id");
      if (value?.limitId === compatibility.limitId) basis.push("snapshot-limit-id-equality");
    }
    if (structurallyEqual(value, compatibility)) basis.push("complete-snapshot-equality");
    if (basis.length > 0) candidates.push({ basis });
  }
  return {
    status: candidates.length === 1 ? "unique" : candidates.length === 0 ? "not-found" : "ambiguous",
    candidateCount: candidates.length,
    basis: [...new Set(candidates.flatMap((candidate) => candidate.basis))].sort(),
  };
}

function sourceEnvironment() {
  return Object.fromEntries(
    ["HOME", "USER", "LANG", "PATH", "CODEX_HOME"]
      .filter((name) => process.env[name] !== undefined)
      .map((name) => [name, process.env[name]]),
  );
}

async function run() {
  const { codexPath, reportPath, durationMinutes } = parseArguments(process.argv.slice(2));
  const startedAt = Date.now();
  const report = {
    formatVersion: 2,
    startedAt: new Date(startedAt).toISOString(),
    limits: LIMITS,
    events: [],
    failures: [],
  };
  let persistence = Promise.resolve();
  const persist = () => {
    const operation = async () => {
      const temporaryPath = `${reportPath}.tmp`;
      await writeFile(temporaryPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
      await rename(temporaryPath, reportPath);
    };
    persistence = persistence.then(operation, operation);
    return persistence;
  };
  const fail = (message) => report.failures.push({ at: new Date().toISOString(), message });

  const child = spawn(
    codexPath,
    ["app-server", "--strict-config", "-c", "analytics.enabled=false", "--listen", "stdio://"],
    { stdio: ["pipe", "pipe", "pipe"], env: sourceEnvironment() },
  );
  let stderrBytes = 0;
  let nextId = 1;
  let buffer = Buffer.alloc(0);
  let lastUpdateRefetchAt = 0;
  let readInFlight = false;
  const pending = new Map();

  child.stderr.on("data", (chunk) => {
    stderrBytes += chunk.length;
  });

  const exitPromise = new Promise((resolve) => {
    child.once("exit", (code, signal) => resolve({ code, signal }));
    child.once("error", (error) => {
      fail(`app-server process error: ${error.code ?? "unknown"}`);
      resolve({ code: null, signal: null });
    });
  });

  const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
  const request = (method, params, timeoutMs = LIMITS.requestTimeoutMs) => {
    const id = nextId++;
    const sentAt = Date.now();
    send({ jsonrpc: "2.0", id, method, params });
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`${method} timed out after ${timeoutMs} ms`));
      }, timeoutMs);
      pending.set(id, { sentAt, resolve, reject, timer });
    });
  };

  const summarize = (result, frameBytes, latencyMs, reason) => {
    const metrics = inspectValue(result);
    const compatibility = snapshotShape(result?.rateLimits);
    const buckets = result?.rateLimitsByLimitId;
    const bucketValues = buckets && typeof buckets === "object" && !Array.isArray(buckets)
      ? Object.values(buckets)
      : [];
    const candidateWindows = compatibility.windowCount
      + bucketValues.map((value) => snapshotShape(value).windowCount).reduce((sum, count) => sum + count, 0);
    const accountIdentifier = result?.accountId;
    return {
      at: new Date().toISOString(),
      elapsedMs: Date.now() - startedAt,
      kind: "rate-limit-read",
      reason,
      latencyMs,
      topLevelKeys: result && typeof result === "object" ? Object.keys(result).sort() : [],
      accountIdentifierClassification: accountIdentifier === undefined || accountIdentifier === null
        ? "absent"
        : typeof accountIdentifier === "string" && accountIdentifier.length > 0
          ? "present-string"
          : "wrong-type-or-empty",
      compatibility,
      multiBucketType: jsonType(buckets),
      multiBucketCount: bucketValues.length,
      multiBucketShapes: bucketValues.map(snapshotShape),
      defaultBucket: defaultBucketResult(result?.rateLimits, buckets),
      bounds: {
        frameBytes,
        maxStringBytes: metrics.maxStringBytes,
        maxDepth: metrics.maxDepth,
        bucketEntryCount: bucketValues.length,
        candidateWindowCount: candidateWindows,
        withinFrameBound: frameBytes <= LIMITS.frameBytes,
        withinStringBound: metrics.maxStringBytes <= LIMITS.stringBytes,
        withinDepthBound: metrics.maxDepth <= LIMITS.nestingDepth,
        withinBucketEntryBound: bucketValues.length <= LIMITS.bucketEntries,
        withinWindowBound: candidateWindows <= LIMITS.candidateWindows,
      },
    };
  };

  const calibratedRead = async (reason) => {
    if (readInFlight) {
      report.events.push({ at: new Date().toISOString(), kind: "read-coalesced", reason });
      return;
    }
    readInFlight = true;
    try {
      const response = await request("account/rateLimits/read", {});
      if (response.error) {
        throw new Error(`account/rateLimits/read returned JSON-RPC error code ${response.error.code ?? "unknown"}`);
      }
      const event = summarize(response.result, response.frameBytes, response.latencyMs, reason);
      report.events.push(event);
      const boundChecks = Object.entries(event.bounds)
        .filter(([, value]) => typeof value === "boolean")
        .map(([, value]) => value);
      if (!boundChecks.every(Boolean)) throw new Error("legitimate Codex response exceeded a proposed safety bound");
      if (["not-found", "ambiguous", "invalid-multi-bucket-shape"].includes(event.defaultBucket.status)) {
        throw new Error(`default bucket mapping is ${event.defaultBucket.status}`);
      }
    } finally {
      readInFlight = false;
      await persist();
    }
  };

  const handleMessage = async (message, frameBytes) => {
    if (Object.hasOwn(message, "id") && pending.has(message.id)) {
      const entry = pending.get(message.id);
      pending.delete(message.id);
      clearTimeout(entry.timer);
      entry.resolve({ ...message, frameBytes, latencyMs: Date.now() - entry.sentAt });
      return;
    }
    if (message?.method === "account/rateLimits/updated") {
      const metrics = inspectValue(message.params);
      report.events.push({
        at: new Date().toISOString(),
        kind: "rate-limit-update-notification",
        frameBytes,
        parameterKeys: message.params && typeof message.params === "object"
          ? Object.keys(message.params).sort()
          : [],
        maxStringBytes: metrics.maxStringBytes,
        maxDepth: metrics.maxDepth,
      });
      const now = Date.now();
      if (now - lastUpdateRefetchAt >= UPDATE_REFETCH_FLOOR_MS) {
        lastUpdateRefetchAt = now;
        await calibratedRead("update-notification");
      } else {
        report.events.push({ at: new Date().toISOString(), kind: "update-refetch-rate-limited" });
      }
      await persist();
    } else if (Object.hasOwn(message ?? {}, "method")) {
      report.events.push({ at: new Date().toISOString(), kind: "other-message", method: String(message.method) });
      await persist();
    }
  };

  child.stdout.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (true) {
      const newline = buffer.indexOf(0x0a);
      if (newline < 0) break;
      const frame = buffer.subarray(0, newline);
      buffer = buffer.subarray(newline + 1);
      if (frame.length === 0) continue;
      if (frame.length > LIMITS.frameBytes) {
        fail(`incoming frame exceeded ${LIMITS.frameBytes} bytes`);
        child.kill("SIGTERM");
        continue;
      }
      let message;
      try {
        message = JSON.parse(frame.toString("utf8"));
      } catch {
        fail("incoming frame was not valid JSON");
        child.kill("SIGTERM");
        continue;
      }
      void handleMessage(message, frame.length).catch((error) => {
        fail(error.message);
        void persist();
      });
    }
    if (buffer.length > LIMITS.frameBytes) {
      fail(`unterminated incoming frame exceeded ${LIMITS.frameBytes} bytes`);
      child.kill("SIGTERM");
    }
  });
  child.stdout.on("end", () => {
    if (buffer.length > 0) fail("app-server stdout ended with an unterminated frame");
  });

  try {
    const initialized = await request("initialize", {
      clientInfo: { name: "reset-radar-source-calibration", version: "1" },
      capabilities: { experimentalApi: false },
    });
    if (initialized.error) {
      throw new Error(`initialize returned JSON-RPC error code ${initialized.error.code ?? "unknown"}`);
    }
    report.events.push({
      at: new Date().toISOString(),
      kind: "initialized",
      latencyMs: initialized.latencyMs,
      frameBytes: initialized.frameBytes,
      resultKeys: initialized.result && typeof initialized.result === "object"
        ? Object.keys(initialized.result).sort()
        : [],
    });
    send({ jsonrpc: "2.0", method: "initialized" });
    const account = await request("account/read", { refreshToken: false });
    if (account.error) {
      throw new Error(`account/read returned JSON-RPC error code ${account.error.code ?? "unknown"}`);
    }
    const accountMetrics = inspectValue(account.result);
    report.events.push({
      at: new Date().toISOString(),
      kind: "account-read",
      latencyMs: account.latencyMs,
      frameBytes: account.frameBytes,
      topLevelKeys: account.result && typeof account.result === "object"
        ? Object.keys(account.result).sort()
        : [],
      ...accountStatusShape(account.result),
      bounds: {
        withinFrameBound: account.frameBytes <= LIMITS.frameBytes,
        withinStringBound: accountMetrics.maxStringBytes <= LIMITS.stringBytes,
        withinDepthBound: accountMetrics.maxDepth <= LIMITS.nestingDepth,
      },
    });
    await calibratedRead("initial");
    const pollCount = Math.floor((durationMinutes * 60_000) / POLL_INTERVAL_MS);
    for (let poll = 0; poll < pollCount && report.failures.length === 0; poll += 1) {
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
      await calibratedRead("scheduled-poll");
    }
  } catch (error) {
    fail(error.message);
  } finally {
    report.stderrBytesDiscarded = stderrBytes;
    report.stdinClosedAt = new Date().toISOString();
    child.stdin.end();
    let exitedAfterStdinClose = true;
    let exit = await Promise.race([
      exitPromise,
      new Promise((resolve) => setTimeout(() => resolve(null), 5_000)),
    ]);
    if (exit === null) {
      exitedAfterStdinClose = false;
      child.kill("SIGTERM");
      exit = await exitPromise;
    }
    for (const entry of pending.values()) {
      clearTimeout(entry.timer);
      entry.reject(new Error("app-server exited before replying"));
    }
    pending.clear();
    report.exitedAfterStdinClose = exitedAfterStdinClose;
    report.childExit = exit;
    report.finishedAt = new Date().toISOString();
    await persist();
  }

  if (report.failures.length > 0 || !report.exitedAfterStdinClose) process.exitCode = 1;
}

await run();
