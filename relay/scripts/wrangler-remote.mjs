#!/usr/bin/env node

import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";

const MAX_WRANGLER_OUTPUT_BYTES = 64 * 1024;
const OPERATIONS = {
  delete: { arguments: ["delete"], input: "y\n", timeoutMs: 2 * 60 * 1000 },
  deploy: { arguments: ["deploy"], input: "", timeoutMs: 5 * 60 * 1000 },
  rollback: { arguments: ["rollback", "--yes"], input: "", timeoutMs: 2 * 60 * 1000 },
};

export class WranglerRemoteFailure extends Error {}

export function reviewedWranglerOperation(name) {
  const operation = OPERATIONS[name];
  if (operation === undefined) throw new WranglerRemoteFailure("Unreviewed Wrangler operation.");
  return structuredClone(operation);
}

export async function runWranglerRemote(
  name,
  { approvedDeletion = false, spawnImplementation = spawn, timeoutMs } = {},
) {
  const operation = reviewedWranglerOperation(name);
  if (name === "delete" && !approvedDeletion) {
    throw new WranglerRemoteFailure("Isolated Worker deletion was not approved.");
  }

  const relayDirectory = fileURLToPath(new URL("..", import.meta.url));
  const executable = resolve(relayDirectory, "node_modules/.bin/wrangler");
  const child = spawnImplementation(executable, operation.arguments, {
    cwd: relayDirectory,
    env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
    shell: false,
    stdio: ["pipe", "pipe", "pipe"],
  });
  child.stdin.on("error", () => {});
  child.stdin.end(operation.input);

  let outputBytes = 0;
  let outputExceeded = false;
  let timedOut = false;
  const suppress = (chunk) => {
    outputBytes += Buffer.byteLength(chunk);
    if (outputBytes > MAX_WRANGLER_OUTPUT_BYTES && !outputExceeded) {
      outputExceeded = true;
      child.kill("SIGTERM");
    }
  };
  child.stdout.on("data", suppress);
  child.stderr.on("data", suppress);
  const timeout = setTimeout(() => {
    timedOut = true;
    child.kill("SIGTERM");
  }, timeoutMs ?? operation.timeoutMs);

  let code;
  try {
    code = await new Promise((resolvePromise, rejectPromise) => {
      child.once("error", rejectPromise);
      child.once("close", resolvePromise);
    });
  } finally {
    clearTimeout(timeout);
  }
  if (timedOut || outputExceeded || code !== 0) {
    throw new WranglerRemoteFailure(`Remote Wrangler ${name} failed; output suppressed.`);
  }
  return { operation: name, passed: true };
}

async function confirmDeletion() {
  if (!process.stdin.isTTY) throw new WranglerRemoteFailure("Worker deletion requires an interactive terminal.");
  const terminal = createInterface({ input: process.stdin, output: process.stderr, terminal: true });
  try {
    const answer = await terminal.question("Type DELETE to remove only the reviewed isolated M9 Worker: ");
    return answer.trim() === "DELETE";
  } finally {
    terminal.close();
  }
}

async function main() {
  if (process.argv.length !== 3) throw new WranglerRemoteFailure("Select one reviewed Wrangler operation.");
  const name = process.argv[2];
  const approvedDeletion = name === "delete" ? await confirmDeletion() : false;
  await runWranglerRemote(name, { approvedDeletion });
  process.stdout.write(`Remote Wrangler ${name} completed with output suppressed.\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof WranglerRemoteFailure ? error.message : "Remote Wrangler operation failed; output suppressed."}\n`);
    process.exitCode = 1;
  });
}
