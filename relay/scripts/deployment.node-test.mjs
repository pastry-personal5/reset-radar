import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { readFile } from "node:fs/promises";
import { PassThrough } from "node:stream";
import test from "node:test";

import { validateDeployment } from "./check-deploy-config.mjs";
import { digestsFromTokens, parseDigests, provisionSecrets } from "./provision-secrets.mjs";
import { reviewedWranglerOperation, runWranglerRemote } from "./wrangler-remote.mjs";
import contract from "../deployment-contract.json" with { type: "json" };
import packageManifest from "../package.json" with { type: "json" };

const config = JSON.parse(await readFile(new URL("../wrangler.jsonc", import.meta.url), "utf8"));

const clone = (value) => structuredClone(value);

test("deployment contract accepts only the reviewed configuration", () => {
  assert.deepEqual(validateDeployment(config, contract, packageManifest), []);
  const mutations = [
    (value) => { value.extra = true; },
    (value) => { value.preview_urls = true; },
    (value) => { value.observability.enabled = true; },
    (value) => { value.secrets.required = ["ADMIN_TOKEN_DIGEST"]; },
    (value) => { value.routes = [{ pattern: "example.com/*" }]; },
    (value) => { value.durable_objects.bindings.push({ class_name: "Other", name: "OTHER" }); },
    (value) => { value.exports.RelayObject.storage = "key-value"; },
    (value) => { value.main = "src/other.ts"; },
    (value) => { value.compatibility_date = "2026-10-21"; },
  ];
  for (const mutate of mutations) {
    const candidate = clone(config);
    mutate(candidate);
    assert.notDeepEqual(validateDeployment(candidate, contract, packageManifest), []);
  }
  for (const requiredSecrets of [[], ["ADMIN_TOKEN_DIGEST"], [...contract.requiredSecrets, "EXTRA"]]) {
    assert.notDeepEqual(validateDeployment(config, { ...contract, requiredSecrets }, packageManifest), []);
  }
  const ranged = clone(packageManifest);
  ranged.devDependencies.wrangler = "^4.154.0";
  assert.match(validateDeployment(config, contract, ranged).join(" "), /not pinned/);
  const extraDependency = clone(packageManifest);
  extraDependency.devDependencies.extra = "1.0.0";
  assert.match(validateDeployment(config, contract, extraDependency).join(" "), /differ/);
});

test("bulk provisioning keeps both digests out of process metadata and output", async () => {
  const write = "1".repeat(64);
  const admin = "2".repeat(64);
  const digests = parseDigests(`${write}\n${admin}\n`);
  let invocation;
  let stdin = "";
  const spawnMock = (executable, arguments_, options) => {
    invocation = { arguments_, executable, options };
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.stdin.on("data", (chunk) => { stdin += chunk; });
    child.stdin.on("finish", () => {
      child.stdout.end("normal Wrangler output");
      child.stderr.end();
      queueMicrotask(() => child.emit("close", 0));
    });
    return child;
  };
  const result = await provisionSecrets(digests, spawnMock);
  assert.deepEqual(invocation.arguments_, ["secret", "bulk"]);
  assert.equal(Object.values(invocation.options.env).includes(write), false);
  assert.equal(Object.values(invocation.options.env).includes(admin), false);
  assert.equal(invocation.options.env.WRANGLER_SEND_METRICS, "false");
  assert.equal(JSON.stringify(invocation.arguments_).includes(write), false);
  assert.equal(JSON.stringify(invocation.arguments_).includes(admin), false);
  assert.deepEqual(JSON.parse(stdin), digests);
  assert.equal(JSON.stringify(result).includes(write), false);
  assert.equal(JSON.stringify(result).includes(admin), false);
});

test("bulk provisioning bounds suppressed Wrangler output", async () => {
  const spawnMock = () => {
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = () => { queueMicrotask(() => child.emit("close", 1)); };
    child.stdin.on("finish", () => { child.stdout.end("x".repeat(65 * 1024)); });
    return child;
  };
  await assert.rejects(
    () => provisionSecrets(
      { ADMIN_TOKEN_DIGEST: "2".repeat(64), WRITE_TOKEN_DIGEST: "1".repeat(64) },
      spawnMock,
    ),
    /bounded bulk/,
  );
});

test("provisioning input rejects malformed, duplicate, or extra digests", () => {
  assert.throws(() => parseDigests("a\nb\n"));
  assert.throws(() => parseDigests(`${"a".repeat(64)}\n${"a".repeat(64)}\n`));
  assert.throws(() => parseDigests(`${"a".repeat(64)}\n${"b".repeat(64)}\nextra\n`));
});

test("hidden synthetic tokens derive the protocol fixture digests", () => {
  assert.deepEqual(
    digestsFromTokens(
      "ERERERERERERERERERERERERERERERERERERERERERE",
      "IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI",
    ),
    {
      ADMIN_TOKEN_DIGEST: "9f72ea0cf49536e3c66c787f705186df9a4378083753ae9536d65b3ad7fcddc4",
      WRITE_TOKEN_DIGEST: "02d449a31fbb267c8f352e9968a79e3e5fc95c1bbeaa502fd6454ebde5a4bedc",
    },
  );
  assert.throws(
    () => digestsFromTokens(
      "ERERERERERERERERERERERERERERERERERERERERERE",
      "ERERERERERERERERERERERERERERERERERERERERERE",
    ),
    /distinct/,
  );
});

function successfulWranglerMock(output = "private origin and Cloudflare identifiers") {
  let invocation;
  let stdin = "";
  const spawnMock = (executable, arguments_, options) => {
    invocation = { arguments_, executable, options };
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.stdin.on("data", (chunk) => { stdin += chunk; });
    child.stdin.on("finish", () => {
      child.stdout.end(output);
      child.stderr.end(output);
      queueMicrotask(() => child.emit("close", 0));
    });
    return child;
  };
  return { get invocation() { return invocation; }, get stdin() { return stdin; }, spawnMock };
}

test("remote Wrangler operations use reviewed arguments and suppress all output", async () => {
  const cases = [
    ["deploy", ["deploy"], "", false],
    ["rollback", ["rollback", "--yes"], "", false],
    ["delete", ["delete"], "y\n", true],
  ];
  for (const [name, arguments_, expectedInput, approvedDeletion] of cases) {
    const mock = successfulWranglerMock();
    const result = await runWranglerRemote(name, {
      approvedDeletion,
      spawnImplementation: mock.spawnMock,
    });
    assert.deepEqual(mock.invocation.arguments_, arguments_);
    assert.equal(mock.invocation.options.env.WRANGLER_SEND_METRICS, "false");
    assert.equal(mock.invocation.options.shell, false);
    assert.deepEqual(mock.invocation.options.stdio, ["pipe", "pipe", "pipe"]);
    assert.equal(mock.stdin, expectedInput);
    assert.deepEqual(result, { operation: name, passed: true });
    assert.doesNotMatch(JSON.stringify(result), /private|workers\.dev|version/i);
  }
});

test("remote Wrangler operations pin timeouts and require deletion approval", async () => {
  assert.deepEqual(reviewedWranglerOperation("deploy"), {
    arguments: ["deploy"], input: "", timeoutMs: 5 * 60 * 1000,
  });
  assert.deepEqual(reviewedWranglerOperation("rollback"), {
    arguments: ["rollback", "--yes"], input: "", timeoutMs: 2 * 60 * 1000,
  });
  assert.deepEqual(reviewedWranglerOperation("delete"), {
    arguments: ["delete"], input: "y\n", timeoutMs: 2 * 60 * 1000,
  });
  assert.throws(() => reviewedWranglerOperation("versions"), /Unreviewed/);
  await assert.rejects(() => runWranglerRemote("delete"), /not approved/);
});

test("remote Wrangler failures bound and suppress private output", async () => {
  const privateOutput = "private-origin.workers.dev private-version-id";
  const failureMock = successfulWranglerMock(privateOutput);
  failureMock.spawnMock = (executable, arguments_, options) => {
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.stdin.on("finish", () => {
      child.stderr.end(privateOutput);
      queueMicrotask(() => child.emit("close", 1));
    });
    return child;
  };
  await assert.rejects(
    () => runWranglerRemote("deploy", { spawnImplementation: failureMock.spawnMock }),
    (error) => error.message === "Remote Wrangler deploy failed; output suppressed." &&
      !error.message.includes(privateOutput),
  );

  const oversizedMock = () => {
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = () => { queueMicrotask(() => child.emit("close", 1)); };
    child.stdin.on("finish", () => { child.stdout.end("x".repeat(65 * 1024)); });
    return child;
  };
  await assert.rejects(
    () => runWranglerRemote("deploy", { spawnImplementation: oversizedMock }),
    /output suppressed/,
  );
});
