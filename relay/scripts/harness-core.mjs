import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline/promises";
import { Writable } from "node:stream";

export const SMALL_BODY_LIMIT = 4 * 1024;
export const SNAPSHOT_BODY_LIMIT = 64 * 1024;
export const REQUEST_TIMEOUT_MS = 10_000;
export const SLOT_SECONDS = 5.05;
export const DAILY_SLOTS = 17_280;
export const SAMPLE_SECONDS = 30 * 60;
const MAX_SEQUENCE = Number.MAX_SAFE_INTEGER;
const ENVELOPE_KEYS = [
  "ciphertext",
  "envelopeVersion",
  "keyVersion",
  "nonce",
  "protocolVersion",
  "publisherID",
  "sequence",
  "tag",
];
const REVIEWED_PATHS = [
  /^\/v1\/relay$/,
  /^\/v1\/snapshot$/,
  /^\/v1\/readers$/,
  /^\/v1\/readers\/activate$/,
  /^\/v1\/readers\/[0-9a-f]{32}$/,
  /^\/v1\/refresh-requests$/,
  /^\/v1\/refresh-requests\/[0-9a-f]{32}$/,
];

export class HarnessFailure extends Error {}

export function canonicalJSON(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(value[key])}`).join(",")}}`;
}

export function hasExactKeys(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());
}

function decodeBase64URL(value, expectedBytes, allowEmpty = false) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) return undefined;
  const decoded = Buffer.from(value, "base64url");
  if ((!allowEmpty && decoded.byteLength === 0) ||
      (expectedBytes !== undefined && decoded.byteLength !== expectedBytes) ||
      decoded.toString("base64url") !== value) return undefined;
  return decoded;
}

export function parseRemoteOrigin(input) {
  let url;
  try { url = new URL(input.trim()); } catch { throw new HarnessFailure("Enter one valid Worker origin."); }
  if (url.protocol !== "https:" || url.username || url.password || url.port || url.pathname !== "/" || url.search || url.hash) {
    throw new HarnessFailure("The origin must be canonical HTTPS with no credentials, port, path, query, or fragment.");
  }
  if (!/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.){2,}workers\.dev$/.test(url.hostname)) {
    throw new HarnessFailure("The origin must be a workers.dev subdomain.");
  }
  return url.origin;
}

export function isEncodedSecret(value) {
  return typeof value === "string" && value.length === 43 && decodeBase64URL(value, 32) !== undefined;
}

export function validateDistinctSecrets(values) {
  if (!Array.isArray(values) || !values.every(isEncodedSecret) || new Set(values).size !== values.length) {
    throw new HarnessFailure("Synthetic secrets must be valid and mutually distinct.");
  }
}

export function validateSecretSet(secrets, readerCount = 3) {
  if (!secrets || !Array.isArray(secrets.readTokens) || secrets.readTokens.length !== readerCount) {
    throw new HarnessFailure("Synthetic secret set is incomplete.");
  }
  const values = [secrets.writeToken, secrets.adminToken, secrets.contentKey, ...secrets.readTokens];
  validateDistinctSecrets(values);
  return Buffer.from(secrets.contentKey, "base64url");
}

export function digest(value) {
  if (!isEncodedSecret(value)) throw new HarnessFailure("A relay token had the wrong encoding.");
  return createHash("sha256").update(Buffer.from(value, "base64url")).digest("hex");
}
export function strongETag(text) {
  return `"${createHash("sha256").update(text, "utf8").digest("hex")}"`;
}
export function validateSnapshotReadETag(text, observedETag, expectedETag) {
  if (observedETag !== expectedETag) throw new HarnessFailure("Snapshot read ETag header was transformed.");
  if (strongETag(text) !== expectedETag) throw new HarnessFailure("Snapshot read body changed under its strong ETag.");
}
export function randomIdentifier(bytes = 16) { return randomBytes(bytes).toString("hex"); }

export async function readHidden(label) {
  if (!process.stdin.isTTY) throw new HarnessFailure("Secret input requires an interactive terminal.");
  process.stderr.write(`${label}: `);
  const muted = new Writable({ write(_chunk, _encoding, callback) { callback(); } });
  const terminal = createInterface({ input: process.stdin, output: muted, terminal: true });
  try { return (await terminal.question("")).trim(); } finally { terminal.close(); process.stderr.write("\n"); }
}

export async function clearPasteboard(spawnImplementation = spawn) {
  const child = spawnImplementation("pbcopy", [], { shell: false, stdio: ["pipe", "ignore", "ignore"] });
  child.stdin.end();
  const code = await new Promise((resolvePromise, rejectPromise) => {
    child.once("error", rejectPromise);
    child.once("close", resolvePromise);
  });
  if (code !== 0) throw new HarnessFailure("The pasteboard could not be cleared.");
}

export async function withPasteboardCleared(action, clear = clearPasteboard) {
  try {
    return await action();
  } finally {
    await clear();
  }
}

async function boundedText(response, limit, signal) {
  if (response.body === null) return "";
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  let rejectAbort;
  const aborted = new Promise((_resolve, reject) => { rejectAbort = reject; });
  const onAbort = () => {
    rejectAbort(new HarnessFailure("Relay request failed or timed out."));
    void reader.cancel();
  };
  signal.addEventListener("abort", onAbort, { once: true });
  try {
    while (true) {
      let part;
      try { part = await Promise.race([reader.read(), aborted]); } catch (error) {
        if (error instanceof HarnessFailure) throw error;
        throw new HarnessFailure("Response body stream failed.");
      }
      if (part.done) break;
      size += part.value.byteLength;
      if (size > limit) { await reader.cancel(); throw new HarnessFailure("Response exceeded its reviewed byte limit."); }
      chunks.push(part.value);
    }
  } finally {
    signal.removeEventListener("abort", onAbort);
  }
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true })
      .decode(Buffer.concat(chunks.map((value) => Buffer.from(value))));
  } catch {
    throw new HarnessFailure("Relay returned invalid UTF-8.");
  }
}

export async function relayRequest(fetchImplementation, originInput, path, options = {}) {
  const origin = parseRemoteOrigin(originInput);
  if (!REVIEWED_PATHS.some((pattern) => pattern.test(path))) throw new HarnessFailure("Unreviewed relay path.");
  const requestURL = `${origin}${path}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? REQUEST_TIMEOUT_MS);
  const headers = new Headers(options.headers);
  headers.delete("Authorization");
  headers.set("Accept", "application/json");
  if (options.token !== undefined) {
    if (!isEncodedSecret(options.token)) throw new HarnessFailure("A relay token had the wrong encoding.");
    headers.set("Authorization", `Bearer ${options.token}`);
  }
  if (options.body !== undefined) headers.set("Content-Type", "application/json");
  let response;
  let text;
  try {
    response = await fetchImplementation(requestURL, { body: options.body, headers, method: options.method ?? "GET", redirect: "manual", signal: controller.signal });
    if (response.status >= 300 && response.status < 400 && response.status !== 304) throw new HarnessFailure("Relay returned a forbidden redirect.");
    if (response.url !== "" && response.url !== requestURL) throw new HarnessFailure("Relay returned a forbidden redirect.");
    text = await boundedText(response, options.bodyLimit ?? SMALL_BODY_LIMIT, controller.signal);
  } catch (error) {
    if (error instanceof HarnessFailure) throw error;
    throw new HarnessFailure("Relay request failed or timed out.");
  }
  finally { clearTimeout(timeout); }
  if (options.expectedStatus !== undefined && response.status !== options.expectedStatus) {
    throw new HarnessFailure(
      `${options.label ?? "Relay operation"} returned HTTP ${response.status}; expected ${options.expectedStatus}.`,
    );
  }
  const mediaType = response.headers.get("Content-Type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (text !== "" && mediaType !== "application/json") throw new HarnessFailure("Relay returned an invalid media type.");
  return { headers: response.headers, status: response.status, text, bytes: Buffer.byteLength(text) };
}

export function parseCanonicalResponse(text) {
  let value;
  try { value = JSON.parse(text); } catch { throw new HarnessFailure("Relay returned malformed JSON."); }
  if (canonicalJSON(value) !== text) throw new HarnessFailure("Relay returned non-canonical JSON.");
  return value;
}

function isCanonicalTimestamp(value) {
  if (typeof value !== "string") return false;
  const milliseconds = Date.parse(value);
  return !Number.isNaN(milliseconds) && new Date(milliseconds).toISOString() === value;
}

export function parseExpiryResponse(text) {
  const value = parseCanonicalResponse(text);
  if (!hasExactKeys(value, ["expiresAt", "protocolVersion"]) || value.protocolVersion !== 1 ||
      !isCanonicalTimestamp(value.expiresAt)) throw new HarnessFailure("Relay returned an invalid expiry response.");
  return value;
}

export function parseActivationResponse(text) {
  const value = parseCanonicalResponse(text);
  if (!hasExactKeys(value, ["activated", "protocolVersion"]) || value.activated !== true ||
      value.protocolVersion !== 1) throw new HarnessFailure("Relay returned an invalid activation response.");
  return value;
}

export function parsePublicationResponse(text, expectedSequence) {
  const value = parseCanonicalResponse(text);
  if (!hasExactKeys(value, ["protocolVersion", "sequence"]) || value.protocolVersion !== 1 ||
      !Number.isSafeInteger(value.sequence) || value.sequence < 1 || value.sequence > MAX_SEQUENCE ||
      (expectedSequence !== undefined && value.sequence !== expectedSequence)) {
    throw new HarnessFailure("Relay returned an invalid publication response.");
  }
  return value;
}

export function parseErrorResponse(text, expectedCode) {
  const value = parseCanonicalResponse(text);
  if (!hasExactKeys(value, ["code", "protocolVersion"]) || value.protocolVersion !== 1 ||
      value.code !== expectedCode) throw new HarnessFailure("Relay returned an invalid error response.");
  return value;
}

export function parseReaderList(text) {
  const value = parseCanonicalResponse(text);
  if (!hasExactKeys(value, ["protocolVersion", "readers"]) || value.protocolVersion !== 1 ||
      !Array.isArray(value.readers) || value.readers.some((reader) =>
        !hasExactKeys(reader, ["activated", "readerID"]) || typeof reader.activated !== "boolean" ||
        !/^[0-9a-f]{32}$/.test(reader.readerID)) || value.readers.length > 3 ||
      new Set(value.readers.map((reader) => reader.readerID)).size !== value.readers.length) {
    throw new HarnessFailure("Relay returned an invalid reader list.");
  }
  return value.readers;
}

export function parseRefreshList(text) {
  const value = parseCanonicalResponse(text);
  if (!hasExactKeys(value, ["protocolVersion", "requests"]) || value.protocolVersion !== 1 ||
      !Array.isArray(value.requests) || value.requests.some((request) =>
        !hasExactKeys(request, ["expiresAt", "readerID", "requestID"]) ||
        !isCanonicalTimestamp(request.expiresAt) || !/^[0-9a-f]{32}$/.test(request.readerID) ||
        !/^[0-9a-f]{32}$/.test(request.requestID)) || value.requests.length > 3 ||
      new Set(value.requests.map((request) => request.readerID)).size !== value.requests.length ||
      new Set(value.requests.map((request) => request.requestID)).size !== value.requests.length) {
    throw new HarnessFailure("Relay returned an invalid refresh-request list.");
  }
  return value.requests;
}

export function createSyntheticEnvelope(sequence, { key = randomBytes(32), observedAt = new Date().toISOString(), publisherID = randomIdentifier(32), requestID } = {}) {
  if (!Buffer.isBuffer(key) || key.byteLength !== 32 || !Number.isSafeInteger(sequence) || sequence < 1 ||
      sequence > MAX_SEQUENCE || !/^[0-9a-f]{64}$/.test(publisherID) ||
      (requestID !== undefined && !/^[0-9a-f]{32}$/.test(requestID)) ||
      !isCanonicalTimestamp(observedAt)) {
    throw new HarnessFailure("Synthetic envelope input is invalid.");
  }
  const header = { envelopeVersion: 1, keyVersion: 1, protocolVersion: 1, publisherID, sequence };
  const payload = { observedAt, synthetic: true, value: sequence };
  if (requestID !== undefined) payload.requestID = requestID;
  const plaintext = canonicalJSON(payload);
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.from(canonicalJSON(header)));
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return { envelope: { ciphertext: ciphertext.toString("base64url"), ...header, nonce: nonce.toString("base64url"), tag: cipher.getAuthTag().toString("base64url") }, key, plaintext };
}

export function decryptSyntheticEnvelope(envelope, key) {
  const nonce = decodeBase64URL(envelope?.nonce, 12);
  const ciphertext = decodeBase64URL(envelope?.ciphertext);
  const tag = decodeBase64URL(envelope?.tag, 16);
  if (!hasExactKeys(envelope, ENVELOPE_KEYS) || !Buffer.isBuffer(key) || key.byteLength !== 32 ||
      envelope.protocolVersion !== 1 || envelope.envelopeVersion !== 1 || envelope.keyVersion !== 1 ||
      !Number.isSafeInteger(envelope.sequence) || envelope.sequence < 1 || envelope.sequence > MAX_SEQUENCE ||
      !/^[0-9a-f]{64}$/.test(envelope.publisherID) || nonce === undefined || ciphertext === undefined ||
      tag === undefined) throw new HarnessFailure("Envelope header is incompatible.");
  try {
    const header = {
      envelopeVersion: 1,
      keyVersion: 1,
      protocolVersion: 1,
      publisherID: envelope.publisherID,
      sequence: envelope.sequence,
    };
    const decipher = createDecipheriv("aes-256-gcm", key, nonce);
    decipher.setAAD(Buffer.from(canonicalJSON(header)));
    decipher.setAuthTag(tag);
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true })
      .decode(Buffer.concat([decipher.update(ciphertext), decipher.final()]));
  } catch { throw new HarnessFailure("Envelope authentication failed."); }
}

export class StatefulSyntheticReader {
  constructor({ key, publisherID, minimumSequence = 0, now = () => Date.now() }) {
    this.key = key; this.publisherID = publisherID; this.minimumSequence = minimumSequence; this.now = now; this.cache = undefined;
  }
  commit(text) {
    const envelope = parseCanonicalResponse(text);
    if (envelope.publisherID !== this.publisherID || envelope.sequence < this.minimumSequence || (this.cache && envelope.sequence <= this.cache.sequence)) throw new HarnessFailure("Envelope ordering or publisher validation failed.");
    const plaintext = parseCanonicalResponse(decryptSyntheticEnvelope(envelope, this.key));
    const requestID = plaintext?.requestID;
    const plaintextKeys = requestID === undefined
      ? ["observedAt", "synthetic", "value"]
      : ["observedAt", "requestID", "synthetic", "value"];
    if (!hasExactKeys(plaintext, plaintextKeys)) throw new HarnessFailure("Synthetic plaintext schema failed.");
    const observedAt = Date.parse(plaintext.observedAt);
    if (plaintext.synthetic !== true || plaintext.value !== envelope.sequence || !isCanonicalTimestamp(plaintext.observedAt) ||
        (requestID !== undefined && !/^[0-9a-f]{32}$/.test(requestID)) || observedAt - this.now() > 5 * 60 * 1000) {
      throw new HarnessFailure("Synthetic plaintext schema failed.");
    }
    this.cache = { committedAt: this.now(), envelopeText: text, requestID: plaintext.requestID, sequence: envelope.sequence };
    return this.cache;
  }

  ingest(result) {
    if (hasExactKeys(result, ["kind", "text"]) && result.kind === "snapshot" &&
        typeof result.text === "string") {
      return this.commit(result.text);
    }
    if (hasExactKeys(result, ["kind", "outcome"]) && result.kind === "failure" &&
        ["offline", "quotaLimited", "rateLimited"].includes(result.outcome)) {
      return this.cache;
    }
    throw new HarnessFailure("Synthetic relay result is invalid.");
  }
}

export function dailyWorkload() {
  return { acknowledgements: 4_320, followUpReads: 43_200, heartbeatPublications: 288, manualRequests: 4_320, manualResultPublications: 2_880, ordinaryPublications: 2_880, ordinaryReads: 5_790, requestListPolls: 5_760, setupRequests: 7 };
}
export function totalWorkload(counts) { return Object.entries(counts).filter(([key]) => key !== "slots").reduce((sum, [, value]) => sum + value, 0); }
export function sampleWorkload(durationSeconds = SAMPLE_SECONDS) {
  const slots = Math.floor(durationSeconds / SLOT_SECONDS);
  const fromStart = (period) => slots === 0 ? 0 : Math.floor((slots - 1) / period) + 1;
  const manualRequests = fromStart(12) * 3;
  return { acknowledgements: fromStart(6), followUpReads: manualRequests * 10, heartbeatPublications: fromStart(60), manualRequests, manualResultPublications: fromStart(6), ordinaryPublications: fromStart(6), ordinaryReads: fromStart(9) * 3, requestListPolls: fromStart(3), setupRequests: 7, slots };
}
export function percentile(values, fraction) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
}
