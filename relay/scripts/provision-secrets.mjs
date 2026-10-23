#!/usr/bin/env node

import { spawn } from "node:child_process";

const input = await new Promise((resolve, reject) => {
  let value = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => { value += chunk; });
  process.stdin.once("end", () => resolve(value));
  process.stdin.once("error", reject);
});
const [writeDigest, adminDigest, ...extra] = input.trimEnd().split(/\r?\n/);

if (
  extra.length !== 0 ||
  !/^[0-9a-f]{64}$/.test(writeDigest ?? "") ||
  !/^[0-9a-f]{64}$/.test(adminDigest ?? "") ||
  writeDigest === adminDigest
) {
  process.stderr.write("Expected distinct lowercase SHA-256 write and administration digests on two input lines.\n");
  process.exitCode = 2;
} else {
  for (const [name, digest] of [
    ["WRITE_TOKEN_DIGEST", writeDigest],
    ["ADMIN_TOKEN_DIGEST", adminDigest],
  ]) {
    await new Promise((resolve, reject) => {
      const command = process.platform === "win32" ? "wrangler.cmd" : "wrangler";
      const child = spawn(command, ["secret", "put", name], {
        cwd: new URL("..", import.meta.url),
        stdio: ["pipe", "inherit", "inherit"],
      });
      child.once("error", reject);
      child.once("exit", (code) => code === 0 ? resolve(undefined) : reject(new Error(`${name} provisioning failed`)));
      child.stdin.end(`${digest}\n`);
    });
  }
}
