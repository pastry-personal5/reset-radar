// Reset Radar P1-M9 synthetic cellular check for the temporary Scriptable app.
// This file contains only public synthetic self-test bytes. It never persists inputs.

const SELF_TEST_KEY = "Z2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2c=";
const SELF_TEST_PUBLISHER = "2323232323232323232323232323232323232323232323232323232323232323";
const CELLULAR_PUBLISHER = SELF_TEST_PUBLISHER;
const CELLULAR_MINIMUM_SEQUENCE = 1;
const SELF_TEST_ETAG = '"2d41e437b8489eecefb1a6a84657f0252dc05dc4e93eac1aa5ff042025915f86"';
const SELF_TEST_ENVELOPE = "{\"ciphertext\":\"3OqlElLXZeEhjgZAefNdEci5e9RX-AfHQmDAxRmahp5oP3CYFPKk-3pQhlEs61YDzXDwpDVRC6epGSm3vwOpfBCGTjxRfCZ7YxYLabCVYCN6zj6NiQZ9ZGc8KMOncE3m1v9EgA4bKoXy_WXDLEsk2QBWT5gPIlO7JOsZi24qkMeGLBzjAcC32Z5ay6Q2b47b0iyZjnV7zwnCTOfxw5ZPinN5THuZOldnmNIlp6biZNqDfFPU3V_6gyLy-mcm7WAfwvDUuZ3dt3F3Fw1ojAwjpMyk9ibW5OyJWnxyBe_j3YbL6y7nhyRfUQ\",\"envelopeVersion\":1,\"keyVersion\":1,\"nonce\":\"q6urq6urq6urq6ur\",\"protocolVersion\":1,\"publisherID\":\"2323232323232323232323232323232323232323232323232323232323232323\",\"sequence\":7,\"tag\":\"XmE-OivGqkXodjuSrTtiqQ\"}";
const SELF_TEST_PLAINTEXT = "{\"diagnostics\":[],\"generatedAt\":\"2023-11-14T22:13:20.000Z\",\"heartbeatSeconds\":60,\"manualRefreshResults\":[],\"publisherID\":\"2323232323232323232323232323232323232323232323232323232323232323\",\"schemaVersion\":1,\"sources\":[],\"windows\":[]}";

function fail(message) { throw new Error(message); }

async function promptInputs() {
  const prompt = new Alert();
  prompt.title = "Reset Radar synthetic cellular check";
  prompt.message = "Enter private synthetic values. Nothing is saved.";
  prompt.addTextField("https://…workers.dev");
  prompt.addSecureTextField("Reader token");
  prompt.addSecureTextField("Content key");
  prompt.addAction("Run");
  prompt.addCancelAction("Cancel");
  if (await prompt.presentAlert() < 0) fail("Cancelled.");
  const values = {
    origin: prompt.textFieldValue(0).trim(),
    readToken: prompt.textFieldValue(1).trim(),
    contentKey: prompt.textFieldValue(2).trim(),
    publisherID: CELLULAR_PUBLISHER,
    minimumSequence: CELLULAR_MINIMUM_SEQUENCE,
  };
  Pasteboard.copyString("");
  return values;
}

function validateInputs(values) {
  if (!/^https:\/\/(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.){2,}workers\.dev$/.test(values.origin)) fail("Invalid Worker origin.");
  if (!/^[A-Za-z0-9_-]{43}$/.test(values.readToken)) fail("Invalid reader token.");
  if (!/^[A-Za-z0-9_-]{43}$/.test(values.contentKey)) fail("Invalid content key.");
}

function headerValue(headers, name) {
  const match = Object.keys(headers || {}).find((key) => key.toLowerCase() === name.toLowerCase());
  return match ? String(headers[match]) : null;
}

async function cryptoCheck(input) {
  const view = new WebView();
  view.shouldAllowRequest = () => false;
  await view.loadHTML("<!doctype html><meta charset=utf-8>", "https://reset-radar.invalid/");
  const source = `
    const input = ${JSON.stringify(input)};
    const canonical = (value) => Array.isArray(value)
      ? "[" + value.map(canonical).join(",") + "]"
      : value === null || typeof value !== "object"
        ? JSON.stringify(value)
        : "{" + Object.keys(value).sort().map((key) => JSON.stringify(key) + ":" + canonical(value[key])).join(",") + "}";
    const encode = (bytes) => {
      let binary = "";
      for (const byte of bytes) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    };
    const decode = (value, expectedLength = null) => {
      if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) throw new Error("base64url");
      const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
      const binary = atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "="));
      const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
      if (bytes.length === 0 || (expectedLength !== null && bytes.length !== expectedLength) || encode(bytes) !== value) throw new Error("base64url");
      return bytes;
    };
    const hex = (bytes) => Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
    (async () => {
      if (!window.isSecureContext || !window.crypto || !window.crypto.subtle) throw new Error("WebCrypto unavailable");
      const envelope = JSON.parse(input.envelopeText);
      if (canonical(envelope) !== input.envelopeText) throw new Error("non-canonical envelope");
      const keys = ["ciphertext", "envelopeVersion", "keyVersion", "nonce", "protocolVersion", "publisherID", "sequence", "tag"];
      if (JSON.stringify(Object.keys(envelope).sort()) !== JSON.stringify(keys)) throw new Error("envelope keys");
      if (envelope.protocolVersion !== 1 || envelope.envelopeVersion !== 1 || envelope.keyVersion !== 1) throw new Error("version");
      if (envelope.publisherID !== input.publisherID || !Number.isSafeInteger(envelope.sequence) || envelope.sequence < input.minimumSequence) throw new Error("identity or sequence");
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input.envelopeText));
      if ('"' + hex(new Uint8Array(digest)) + '"' !== input.etag) throw new Error("etag");
      const key = await crypto.subtle.importKey("raw", decode(input.contentKey, 32), "AES-GCM", false, ["decrypt"]);
      const header = { envelopeVersion: 1, keyVersion: 1, protocolVersion: 1, publisherID: envelope.publisherID, sequence: envelope.sequence };
      const ciphertext = decode(envelope.ciphertext);
      const tag = decode(envelope.tag, 16);
      const combined = new Uint8Array(ciphertext.length + tag.length);
      combined.set(ciphertext); combined.set(tag, ciphertext.length);
      const plaintextBytes = await crypto.subtle.decrypt({ name: "AES-GCM", iv: decode(envelope.nonce, 12), additionalData: new TextEncoder().encode(canonical(header)), tagLength: 128 }, key, combined);
      const plaintextText = new TextDecoder("utf-8", { fatal: true }).decode(plaintextBytes);
      if (input.expectedPlaintext !== null) {
        if (plaintextText !== input.expectedPlaintext) throw new Error("self-test plaintext");
      } else {
        const plaintext = JSON.parse(plaintextText);
        const plaintextKeys = ["observedAt", "synthetic", "value"];
        if (canonical(plaintext) !== plaintextText || JSON.stringify(Object.keys(plaintext).sort()) !== JSON.stringify(plaintextKeys) || plaintext.synthetic !== true || plaintext.value !== envelope.sequence || typeof plaintext.observedAt !== "string" || Number.isNaN(Date.parse(plaintext.observedAt)) || Date.parse(plaintext.observedAt) - Date.now() > 300000) throw new Error("synthetic plaintext");
      }
      completion({ pass: true, plaintextText, sequence: envelope.sequence });
    })().catch(() => completion({ pass: false }));
  `;
  const result = await view.evaluateJavaScript(source, true);
  if (!result || result.pass !== true) fail("AES-GCM validation failed.");
  return result;
}

async function selfTest() {
  await cryptoCheck({
    contentKey: SELF_TEST_KEY,
    envelopeText: SELF_TEST_ENVELOPE,
    etag: SELF_TEST_ETAG,
    expectedPlaintext: SELF_TEST_PLAINTEXT,
    minimumSequence: 7,
    publisherID: SELF_TEST_PUBLISHER,
  });
}

async function fetchEnvelope(values) {
  const expectedURL = `${values.origin}/v1/snapshot`;
  const request = new Request(expectedURL);
  request.method = "GET";
  request.timeoutInterval = 10;
  request.headers = { Accept: "application/json", Authorization: `Bearer ${values.readToken}` };
  request.onRedirect = () => null;
  const data = await request.load();
  const response = request.response;
  const bytes = data.getBytes().length;
  if (!response || response.url !== expectedURL || response.statusCode !== 200) fail("Relay response failed.");
  if (bytes < 1 || bytes > 65_536) fail("Response size failed.");
  const mediaType = (response.mimeType || headerValue(response.headers, "Content-Type") || "").split(";", 1)[0].toLowerCase();
  if (mediaType !== "application/json") fail("Response media type failed.");
  const etag = headerValue(response.headers, "ETag");
  if (!/^"[0-9a-f]{64}"$/.test(etag || "")) fail("Response ETag failed.");
  const envelopeText = data.toRawString();
  if (envelopeText === null) fail("Response encoding failed.");
  const authenticated = await cryptoCheck({ contentKey: values.contentKey, envelopeText, etag, expectedPlaintext: null, minimumSequence: values.minimumSequence, publisherID: values.publisherID });
  return { authenticated, bytes };
}

function commitSyntheticCache(authenticated) {
  if (!authenticated || !Number.isSafeInteger(authenticated.sequence) || typeof authenticated.plaintextText !== "string") fail("Synthetic cache commit failed.");
  return { plaintextText: authenticated.plaintextText, sequence: authenticated.sequence };
}

async function activateReader(values) {
  const expectedURL = `${values.origin}/v1/readers/activate`;
  const request = new Request(expectedURL);
  request.method = "POST";
  request.timeoutInterval = 10;
  request.headers = { Accept: "application/json", Authorization: `Bearer ${values.readToken}` };
  request.onRedirect = () => null;
  const data = await request.load();
  const response = request.response;
  const bytes = data.getBytes().length;
  if (!response || response.url !== expectedURL || response.statusCode !== 200 || bytes < 1 || bytes > 4_096) fail("Reader activation failed.");
  const mediaType = (response.mimeType || headerValue(response.headers, "Content-Type") || "").split(";", 1)[0].toLowerCase();
  if (mediaType !== "application/json" || data.toRawString() !== "{\"activated\":true,\"protocolVersion\":1}") fail("Reader activation response failed.");
}

try {
  await selfTest();
  let values = await promptInputs();
  validateInputs(values);
  const fetched = await fetchEnvelope(values);
  let syntheticCache = commitSyntheticCache(fetched.authenticated);
  await activateReader(values);
  if (syntheticCache.sequence < CELLULAR_MINIMUM_SEQUENCE) fail("Synthetic cache verification failed.");
  syntheticCache = null;
  values = null;
  const result = new Alert();
  result.title = "PASS";
  result.message = `Authenticated synthetic cellular read (0 request-body bytes, ${fetched.bytes} response bytes).`;
  result.addAction("Done");
  await result.presentAlert();
  Script.setShortcutOutput({ requestBodyBytes: 0, responseBytes: fetched.bytes, result: "pass" });
} catch (_error) {
  Pasteboard.copyString("");
  const result = new Alert();
  result.title = "FAIL";
  result.message = "Synthetic cellular validation did not pass.";
  result.addAction("Done");
  await result.presentAlert();
  Script.setShortcutOutput({ result: "fail" });
}
Script.complete();
