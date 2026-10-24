#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const expectedTopLevelKeys = [
  "$schema",
  "compatibility_date",
  "durable_objects",
  "exports",
  "main",
  "name",
  "observability",
  "preview_urls",
  "routes",
  "secrets",
  "workers_dev",
];
const requiredSecrets = ["ADMIN_TOKEN_DIGEST", "WRITE_TOKEN_DIGEST"];

function hasExactKeys(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());
}

function exactVersion(value) {
  return typeof value === "string" && /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(value);
}

export function validateDeployment(config, contract, packageManifest) {
  const errors = [];
  if (!hasExactKeys(config, expectedTopLevelKeys)) errors.push("unapproved top-level configuration");
  if (!hasExactKeys(contract, ["compatibilityDate", "dependencies", "entryPoint", "requiredSecrets", "workerName"])) errors.push("invalid deployment contract shape");
  if (config.name !== contract.workerName) errors.push("Worker name differs from the deployment contract");
  if (config.main !== contract.entryPoint) errors.push("entry point differs from the deployment contract");
  if (config.compatibility_date !== contract.compatibilityDate) errors.push("compatibility date differs from the deployment contract");
  if (config.workers_dev !== true) errors.push("workers.dev must be enabled");
  if (config.preview_urls !== false) errors.push("Version URLs must be disabled");
  if (!Array.isArray(config.routes) || config.routes.length !== 0) errors.push("routes and custom domains are forbidden");
  if (!hasExactKeys(config.observability, ["enabled"]) || config.observability.enabled !== false) errors.push("observability must be disabled");
  if (!hasExactKeys(config.secrets, ["required"]) ||
      JSON.stringify(config.secrets.required) !== JSON.stringify(requiredSecrets)) {
    errors.push("the exact required secret declarations are missing");
  }

  const binding = config.durable_objects?.bindings?.[0];
  if (!hasExactKeys(config.durable_objects, ["bindings"]) || config.durable_objects.bindings.length !== 1 ||
      !hasExactKeys(binding, ["class_name", "name"]) || binding.name !== "RELAY" || binding.class_name !== "RelayObject") {
    errors.push("exactly one approved Durable Object binding is required");
  }
  const relayExport = config.exports?.RelayObject;
  if (!hasExactKeys(config.exports, ["RelayObject"]) || !hasExactKeys(relayExport, ["storage", "type"]) ||
      relayExport.type !== "durable-object" || relayExport.storage !== "sqlite") {
    errors.push("RelayObject must be SQLite-backed");
  }
  if (JSON.stringify(contract.requiredSecrets) !== JSON.stringify(requiredSecrets)) errors.push("required secret names differ from the approved pair");
  const dependencies = { ...(packageManifest.dependencies ?? {}), ...(packageManifest.devDependencies ?? {}) };
  const approvedDependencies = contract.dependencies ?? {};
  if (!hasExactKeys(dependencies, Object.keys(approvedDependencies)) ||
      Object.entries(approvedDependencies).some(([name, version]) => dependencies[name] !== version)) {
    errors.push("direct dependencies differ from the deployment contract");
  }
  for (const [name, version] of Object.entries(dependencies)) {
    if (!exactVersion(version)) errors.push(`${name} is not pinned to an exact version`);
  }
  return errors;
}

async function main() {
  try {
    const directory = new URL("..", import.meta.url);
    const [config, contract, packageManifest] = await Promise.all([
      readFile(new URL("wrangler.jsonc", directory), "utf8").then(JSON.parse),
      readFile(new URL("deployment-contract.json", directory), "utf8").then(JSON.parse),
      readFile(new URL("package.json", directory), "utf8").then(JSON.parse),
    ]);
    const errors = validateDeployment(config, contract, packageManifest);
    if (errors.length > 0) throw new Error(errors.join("; "));
    process.stdout.write("Deployment configuration is fail-closed.\n");
  } catch (error) {
    process.stderr.write(`Deployment configuration rejected: ${error instanceof Error ? error.message : "unknown error"}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
