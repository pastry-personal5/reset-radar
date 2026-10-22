#!/usr/bin/env node

import readline from "node:readline";
import process from "node:process";

const compatibility = {
  limitId: "DO_NOT_PERSIST_LIMIT_ID_SENTINEL",
  limitName: "DO_NOT_PERSIST_LIMIT_NAME_SENTINEL",
  primary: { usedPercent: 43, windowDurationMins: 300, resetsAt: 1999999999 },
  secondary: { usedPercent: 17, windowDurationMins: 10080, resetsAt: 2000000000 },
};
const compatibilityOnly = process.argv[1].includes("compatibility-only");

const lines = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of lines) {
  if (!line) continue;
  const message = JSON.parse(line);
  if (message.method === "initialize") {
    process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: message.id, result: { serverInfo: { name: "synthetic" } } })}\n`);
  } else if (message.method === "account/rateLimits/read") {
    const result = { rateLimits: compatibility };
    if (!compatibilityOnly) {
      result.rateLimitsByLimitId = { DO_NOT_PERSIST_BUCKET_KEY_SENTINEL: compatibility };
    }
    process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: message.id, result })}\n`);
  }
}

