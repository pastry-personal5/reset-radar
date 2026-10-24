#!/usr/bin/env node

import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  digest,
  readHidden,
  validateDistinctSecrets,
  withPasteboardCleared,
} from "./harness-core.mjs";

export const secretNames = ["ADMIN_TOKEN_DIGEST", "WRITE_TOKEN_DIGEST"];
const MAX_WRANGLER_OUTPUT_BYTES = 64 * 1024;
const WRANGLER_TIMEOUT_MS = 2 * 60 * 1000;
export class ProvisionFailure extends Error {}

export function digestsFromTokens(writeToken, adminToken) {
  try {
    validateDistinctSecrets([writeToken, adminToken]);
    return { ADMIN_TOKEN_DIGEST: digest(adminToken), WRITE_TOKEN_DIGEST: digest(writeToken) };
  } catch {
    throw new ProvisionFailure("Expected distinct canonical write and administration tokens.");
  }
}

export function parseDigests(input) {
  const [writeDigest, adminDigest, ...extra] = input.trimEnd().split(/\r?\n/);
  if (
    extra.length !== 0 ||
    !/^[0-9a-f]{64}$/.test(writeDigest ?? "") ||
    !/^[0-9a-f]{64}$/.test(adminDigest ?? "") ||
    writeDigest === adminDigest
  ) throw new ProvisionFailure("Expected distinct lowercase SHA-256 write and administration digests on two input lines.");
  return { ADMIN_TOKEN_DIGEST: adminDigest, WRITE_TOKEN_DIGEST: writeDigest };
}

export async function provisionSecrets(digests, spawnImplementation = spawn) {
  const relayDirectory = fileURLToPath(new URL("..", import.meta.url));
  const executable = resolve(relayDirectory, "node_modules/.bin/wrangler");
  const child = spawnImplementation(executable, ["secret", "bulk"], {
    cwd: relayDirectory,
    env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
    shell: false,
    stdio: ["pipe", "pipe", "pipe"],
  });
  child.stdin.end(`${JSON.stringify(digests)}\n`);
  let stdout = "";
  let stderr = "";
  let outputBytes = 0;
  let outputExceeded = false;
  let timedOut = false;
  const collect = (target, chunk) => {
    outputBytes += Buffer.byteLength(chunk);
    if (outputBytes > MAX_WRANGLER_OUTPUT_BYTES) {
      outputExceeded = true;
      child.kill("SIGTERM");
      return target;
    }
    return target + chunk;
  };
  child.stdout.on("data", (chunk) => { stdout = collect(stdout, chunk); });
  child.stderr.on("data", (chunk) => { stderr = collect(stderr, chunk); });
  const timeout = setTimeout(() => {
    timedOut = true;
    child.kill("SIGTERM");
  }, WRANGLER_TIMEOUT_MS);
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
    throw new ProvisionFailure("Wrangler rejected bounded bulk secret provisioning.");
  }
  return { stderrLength: Buffer.byteLength(stderr), stdoutLength: Buffer.byteLength(stdout) };
}

async function main() {
  try {
    const digests = process.stdin.isTTY
      ? await withPasteboardCleared(async () => digestsFromTokens(
          await readHidden("Synthetic write token"),
          await readHidden("Synthetic administration token"),
        ))
      : parseDigests(await new Promise((resolveInput, reject) => {
          let value = "";
          process.stdin.setEncoding("utf8");
          process.stdin.on("data", (chunk) => { value += chunk; });
          process.stdin.once("end", () => resolveInput(value));
          process.stdin.once("error", reject);
        }));
    const result = await provisionSecrets(digests);
    const outputBytes = result.stdoutLength + result.stderrLength;
    process.stdout.write(`Both required secrets were provisioned in one operation (${outputBytes} bytes of Wrangler output suppressed).\n`);
  } catch (error) {
    process.stderr.write(`${error instanceof ProvisionFailure ? error.message : "Secret provisioning failed."}\n`);
    process.exitCode = 2;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
