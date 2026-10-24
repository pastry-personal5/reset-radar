export const MAX_SEQUENCE = 9_007_199_254_740_991;
export const SNAPSHOT_LIMIT = 64 * 1024;
export const REFRESH_LIMIT = 192;
export const REGISTRATION_LIMIT = 256;
export const RESPONSE_LIMIT = 4 * 1024;
export const PROTOCOL_VERSION = 1;
export const REFRESH_PROTOCOL_VERSION = 2;

export type ErrorCode =
  | "awaitingFirstPublish"
  | "badRequest"
  | "payloadTooLarge"
  | "publisherMismatch"
  | "quotaLimited"
  | "readerCapReached"
  | "relayUnavailable"
  | "requestAlreadyCompleted"
  | "requestRateLimited"
  | "sequenceConflict"
  | "unauthorized"
  | "unknownRoute"
  | "unsupportedVersion";

export type ProtocolFailure = "badRequest" | "unsupportedVersion";

export type Envelope = {
  ciphertext: string;
  envelopeVersion: 1;
  keyVersion: 1;
  nonce: string;
  protocolVersion: 1;
  publisherID: string;
  sequence: number;
  tag: string;
};

export type RefreshRequestBody =
  | { accountID: string; protocolVersion: 2; requestID: string; target: "account" }
  | { protocolVersion: 2; requestID: string; target: "allCodex" };

export type RegistrationBody = {
  protocolVersion: 1;
  tokenDigest: string;
};

type ObjectRecord = Record<string, unknown>;

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

export function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJSON).join(",")}]`;
  }
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }

  const record = value as ObjectRecord;
  return `{${Object.keys(record).sort().map((key) =>
    `${JSON.stringify(key)}:${canonicalJSON(record[key])}`).join(",")}}`;
}

export function errorBody(
  code: ErrorCode,
  protocolVersion: typeof PROTOCOL_VERSION | typeof REFRESH_PROTOCOL_VERSION = PROTOCOL_VERSION,
): string {
  return canonicalJSON({ code, protocolVersion });
}

export function parseCanonicalObject(
  text: string,
  keys: readonly string[],
  protocolVersion: number = PROTOCOL_VERSION,
): { value: ObjectRecord } | { failure: ProtocolFailure } {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return { failure: "badRequest" };
  }

  if (value === null || Array.isArray(value) || typeof value !== "object") {
    return { failure: "badRequest" };
  }
  const record = value as ObjectRecord;
  const actualKeys = Object.keys(record).sort();
  if (
    actualKeys.length !== keys.length ||
    actualKeys.some((key, index) => key !== [...keys].sort()[index]) ||
    canonicalJSON(record) !== text
  ) {
    return { failure: "badRequest" };
  }
  if (record.protocolVersion !== protocolVersion) {
    return { failure: "unsupportedVersion" };
  }
  return { value: record };
}

export function parseEnvelope(text: string): { value: Envelope } | { failure: ProtocolFailure } {
  const parsed = parseCanonicalObject(text, [
    "ciphertext",
    "envelopeVersion",
    "keyVersion",
    "nonce",
    "protocolVersion",
    "publisherID",
    "sequence",
    "tag",
  ]);
  if ("failure" in parsed) {
    return parsed;
  }
  const value = parsed.value;
  if (value.envelopeVersion !== 1 || value.keyVersion !== 1) {
    return { failure: "unsupportedVersion" };
  }
  if (
    !isPublisherID(value.publisherID) ||
    !isSequence(value.sequence) ||
    !isBase64URL(value.nonce, 12) ||
    !isBase64URL(value.tag, 16) ||
    !isNonEmptyBase64URL(value.ciphertext)
  ) {
    return { failure: "badRequest" };
  }
  return { value: value as Envelope };
}

export function parseRegistration(
  text: string,
): { value: RegistrationBody } | { failure: ProtocolFailure } {
  const parsed = parseCanonicalObject(text, ["protocolVersion", "tokenDigest"]);
  if ("failure" in parsed) {
    return parsed;
  }
  if (!isDigest(parsed.value.tokenDigest)) {
    return { failure: "badRequest" };
  }
  return { value: parsed.value as RegistrationBody };
}

export function parseRefreshRequest(
  text: string,
): { value: RefreshRequestBody } | { failure: ProtocolFailure } {
  let untyped: unknown;
  try {
    untyped = JSON.parse(text);
  } catch {
    return { failure: "badRequest" };
  }
  if (untyped === null || Array.isArray(untyped) || typeof untyped !== "object") {
    return { failure: "badRequest" };
  }
  const record = untyped as ObjectRecord;
  const keys = record.target === "account"
    ? ["accountID", "protocolVersion", "requestID", "target"]
    : ["protocolVersion", "requestID", "target"];
  const parsed = parseCanonicalObject(text, keys, REFRESH_PROTOCOL_VERSION);
  if ("failure" in parsed) {
    return parsed;
  }
  if (!isReaderOrRequestID(parsed.value.requestID)) {
    return { failure: "badRequest" };
  }
  if (parsed.value.target === "account") {
    if (!isReaderOrRequestID(parsed.value.accountID)) return { failure: "badRequest" };
  } else if (parsed.value.target !== "allCodex" || "accountID" in parsed.value) {
    return { failure: "badRequest" };
  }
  return { value: parsed.value as RefreshRequestBody };
}

export function isPublisherID(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

export function isReaderOrRequestID(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{32}$/.test(value);
}

export function isDigest(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

export function isSequence(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isSafeInteger(value) && value >= 1 && value <= MAX_SEQUENCE;
}

export function byteLength(text: string): number {
  return encoder.encode(text).byteLength;
}

export function decodeUTF8(bytes: Uint8Array): string | undefined {
  try {
    return decoder.decode(bytes);
  } catch {
    return undefined;
  }
}

export function isBase64URL(value: unknown, expectedLength: number): value is string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) {
    return false;
  }
  try {
    const decoded = decodeBase64URL(value);
    return decoded.byteLength === expectedLength && encodeBase64URL(decoded) === value;
  } catch {
    return false;
  }
}

export function isNonEmptyBase64URL(value: unknown): value is string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) {
    return false;
  }
  try {
    const decoded = decodeBase64URL(value);
    return decoded.byteLength > 0 && encodeBase64URL(decoded) === value;
  } catch {
    return false;
  }
}

export function decodeBase64URL(value: string): Uint8Array {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const binary = atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "="));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function encodeBase64URL(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
