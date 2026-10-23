import { DurableObject } from "cloudflare:workers";

import { bearerDigest, timingSafeDigestEqual } from "./adapters/security";
import { FixedClock, type Clock, SystemClock } from "./application/clock";
import {
  canonicalJSON,
  decodeUTF8,
  errorBody,
  isDigest,
  parseEnvelope,
  parseRefreshRequest,
  parseRegistration,
  REFRESH_LIMIT,
  REGISTRATION_LIMIT,
  RESPONSE_LIMIT,
  SNAPSHOT_LIMIT,
  type ErrorCode,
} from "./domain/protocol";

const INTERNAL_AUTHORITY = "X-Reset-Radar-Authority";
const SCHEMA_VERSION = 1;
const READER_LIMIT = 3;
const PENDING_READER_LIFETIME_MS = 5 * 60 * 1000;
const REFRESH_LIFETIME_MS = 60 * 1000;

type Authority = "admin" | "read" | "write";
type InternalAuthority = Exclude<Authority, "read">;
type SecretEnv = { ADMIN_TOKEN_DIGEST?: string; WRITE_TOKEN_DIGEST?: string };
type StoredReader = {
  activated: number;
  last_accepted_at: number | null;
  last_accepted_id: string | null;
  last_completed_id: string | null;
  pending_expires_at: number;
  reader_id: string;
  token_digest: string;
};
type StoredSnapshot = { envelope: string; etag: string; last_sequence: number; publisher_id: string };
type StoredRefreshRequest = { accepted_at: number; expires_at: number; reader_id: string; request_id: string };
type BodyResult = { text: string } | { error: "badRequest" | "payloadTooLarge" };
type ResponseOptions = { bodyLimit?: number; etag?: string; noStore?: boolean };

function success(status: number, body?: string, options: ResponseOptions = {}): Response {
  if (body !== undefined && new TextEncoder().encode(body).byteLength > (options.bodyLimit ?? RESPONSE_LIMIT)) {
    return failure("relayUnavailable");
  }
  const headers = new Headers();
  if (body !== undefined) headers.set("Content-Type", "application/json");
  if (options.etag !== undefined) headers.set("ETag", options.etag);
  if (options.noStore) headers.set("Cache-Control", "no-store");
  return new Response(body, { headers, status });
}

function failure(code: ErrorCode, options: ResponseOptions = {}): Response {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (options.noStore) headers.set("Cache-Control", "no-store");
  return new Response(errorBody(code), { headers, status: statusFor(code) });
}

function statusFor(code: ErrorCode): number {
  switch (code) {
    case "awaitingFirstPublish": case "unknownRoute": return 404;
    case "badRequest": return 400;
    case "payloadTooLarge": return 413;
    case "publisherMismatch": case "readerCapReached": case "requestAlreadyCompleted": case "sequenceConflict": return 409;
    case "quotaLimited": case "requestRateLimited": return 429;
    case "relayUnavailable": return 503;
    case "unauthorized": return 401;
    case "unsupportedVersion": return 422;
  }
}

function fixedRouteAuthority(request: Request): InternalAuthority | undefined {
  const url = new URL(request.url);
  if (url.search !== "") return undefined;
  if (request.method === "PUT" && url.pathname === "/v1/snapshot") return "write";
  if (
    (request.method === "GET" && url.pathname === "/v1/refresh-requests") ||
    (request.method === "DELETE" && /^\/v1\/refresh-requests\/[0-9a-f]{32}$/.test(url.pathname))
  ) return "write";
  if (
    (request.method === "PUT" && /^\/v1\/readers\/[0-9a-f]{32}$/.test(url.pathname)) ||
    (request.method === "GET" && url.pathname === "/v1/readers") ||
    (request.method === "DELETE" && /^\/v1\/readers\/[0-9a-f]{32}$/.test(url.pathname)) ||
    (request.method === "DELETE" && url.pathname === "/v1/relay")
  ) return "admin";
  return undefined;
}

async function isAuthorizedForWorkerRole(request: Request, env: SecretEnv, role: InternalAuthority): Promise<boolean> {
  const expected = role === "write" ? env.WRITE_TOKEN_DIGEST : env.ADMIN_TOKEN_DIGEST;
  const opposite = role === "write" ? env.ADMIN_TOKEN_DIGEST : env.WRITE_TOKEN_DIGEST;
  if (!isDigest(expected) || !isDigest(opposite) || timingSafeDigestEqual(expected, opposite)) return false;
  return timingSafeDigestEqual(await bearerDigest(request), expected);
}

async function readBody(request: Request, limit: number): Promise<BodyResult> {
  if (request.body === null) return { text: "" };
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.byteLength;
      if (size > limit) {
        await reader.cancel();
        return { error: "payloadTooLarge" };
      }
      chunks.push(next.value);
    }
  } catch {
    return { error: "badRequest" };
  }
  const all = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { all.set(chunk, offset); offset += chunk.byteLength; }
  const text = decodeUTF8(all);
  return text === undefined ? { error: "badRequest" } : { text };
}

function validJSONContentType(request: Request): boolean { return request.headers.get("Content-Type") === "application/json"; }
function formatTime(milliseconds: number): string { return new Date(milliseconds).toISOString(); }
function requestHasNoBody(request: Request): Promise<BodyResult> { return readBody(request, 0); }

/** The single authoritative-state object. It persists only ciphertext and protocol metadata. */
export class RelayObject extends DurableObject {
  private readonly secretEnv: SecretEnv;
  private clock: Clock;

  constructor(ctx: DurableObjectState, env: Env & SecretEnv, clock: Clock = new SystemClock()) {
    super(ctx, env);
    this.secretEnv = env;
    this.clock = clock;
  }

  /** Test-only clock injection; production construction always supplies SystemClock. */
  setClockForTesting(milliseconds: number): void {
    this.clock = new FixedClock(milliseconds);
  }

  override async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);
      const schemaState = this.schemaState();
      if (schemaState === "unavailable") return failure("relayUnavailable");
      if (schemaState === "missing") {
        if (this.isInternal(request, "admin") || this.isInternal(request, "write")) {
          if (!this.ensureSchema()) return failure("relayUnavailable");
        } else if (url.search === "" && (
          (request.method === "GET" && url.pathname === "/v1/snapshot") ||
          (request.method === "POST" && (
            url.pathname === "/v1/readers/activate" || url.pathname === "/v1/refresh-requests"
          ))
        )) {
          return failure("unauthorized", { noStore: url.pathname === "/v1/snapshot" });
        }
      }
      if (url.search !== "") return failure("unknownRoute");
      if (request.method === "PUT" && url.pathname === "/v1/snapshot") return this.putSnapshot(request);
      if (request.method === "GET" && url.pathname === "/v1/snapshot") return this.getSnapshot(request);
      if (request.method === "POST" && url.pathname === "/v1/readers/activate") return this.activateReader(request);
      if (request.method === "POST" && url.pathname === "/v1/refresh-requests") return this.postRefreshRequest(request);
      if (request.method === "GET" && url.pathname === "/v1/refresh-requests") return this.listRefreshRequests(request);
      if (request.method === "DELETE" && /^\/v1\/refresh-requests\/[0-9a-f]{32}$/.test(url.pathname)) return this.deleteRefreshRequest(request, url.pathname.split("/").at(-1)!);
      if (request.method === "PUT" && /^\/v1\/readers\/[0-9a-f]{32}$/.test(url.pathname)) return this.registerReader(request, url.pathname.split("/").at(-1)!);
      if (request.method === "GET" && url.pathname === "/v1/readers") return this.listReaders(request);
      if (request.method === "DELETE" && /^\/v1\/readers\/[0-9a-f]{32}$/.test(url.pathname)) return this.deleteReader(request, url.pathname.split("/").at(-1)!);
      if (request.method === "DELETE" && url.pathname === "/v1/relay") return this.destroyRelay(request);
      return failure("unknownRoute");
    } catch {
      return failure("relayUnavailable");
    }
  }

  private ensureSchema(): boolean {
    try {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS relay_schema (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL)");
      const version = this.one<{ version: number }>("SELECT version FROM relay_schema WHERE id = 1");
      if (version === undefined) this.ctx.storage.sql.exec("INSERT INTO relay_schema (id, version) VALUES (1, ?)", SCHEMA_VERSION);
      else if (version.version !== SCHEMA_VERSION) return false;
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS relay_state (id INTEGER PRIMARY KEY CHECK (id = 1), publisher_id TEXT NOT NULL, last_sequence INTEGER NOT NULL, envelope TEXT NOT NULL, etag TEXT NOT NULL, accepted_at INTEGER NOT NULL)");
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS readers (reader_id TEXT PRIMARY KEY, token_digest TEXT NOT NULL UNIQUE, activated INTEGER NOT NULL, pending_expires_at INTEGER NOT NULL, last_accepted_at INTEGER, last_accepted_id TEXT, last_completed_id TEXT)");
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS refresh_requests (request_id TEXT PRIMARY KEY, reader_id TEXT NOT NULL UNIQUE, accepted_at INTEGER NOT NULL, expires_at INTEGER NOT NULL)");
      return true;
    } catch { return false; }
  }

  /**
   * Reader routes must be able to reject an unknown token without materializing
   * a database. A missing schema means an empty/destroyed relay; partial or
   * version-mismatched schema state is unavailable rather than silently reset.
   */
  private schemaState(): "missing" | "ready" | "unavailable" {
    try {
      const tables = this.all<{ name: string }>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('relay_schema', 'relay_state', 'readers', 'refresh_requests')",
      );
      if (!tables.some((table) => table.name === "relay_schema")) {
        return tables.length === 0 ? "missing" : "unavailable";
      }
      const version = this.one<{ version: number }>("SELECT version FROM relay_schema WHERE id = 1");
      return version?.version === SCHEMA_VERSION ? "ready" : "unavailable";
    } catch {
      return "unavailable";
    }
  }

  private one<T extends Record<string, unknown>>(query: string, ...parameters: unknown[]): T | undefined {
    return this.ctx.storage.sql.exec(query, ...parameters as []).toArray()[0] as T | undefined;
  }

  private all<T extends Record<string, unknown>>(query: string, ...parameters: unknown[]): T[] {
    return this.ctx.storage.sql.exec(query, ...parameters as []).toArray() as T[];
  }

  private isInternal(request: Request, authority: InternalAuthority): boolean { return request.headers.get(INTERNAL_AUTHORITY) === authority; }

  private async authenticatedReader(request: Request): Promise<StoredReader | undefined> {
    const digest = await bearerDigest(request);
    if (digest === undefined) return undefined;
    const readers = this.all<StoredReader>("SELECT reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id FROM readers");
    let matched: StoredReader | undefined;
    for (const reader of readers) if (timingSafeDigestEqual(digest, reader.token_digest)) matched = reader;
    return matched;
  }

  private readerIsUsable(reader: StoredReader, now: number): boolean { return reader.activated === 1 || reader.pending_expires_at > now; }

  private async putSnapshot(request: Request): Promise<Response> {
    if (!this.isInternal(request, "write")) return failure("unauthorized");
    const body = await readBody(request, SNAPSHOT_LIMIT);
    if ("error" in body) return failure(body.error);
    if (!validJSONContentType(request)) return failure("badRequest");
    const parsed = parseEnvelope(body.text);
    if ("failure" in parsed) return failure(parsed.failure);
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body.text));
    const etag = `"${[...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("")}"`;
    const acceptedAt = this.clock.now();
    const result = this.ctx.storage.transactionSync(() => {
      const current = this.one<StoredSnapshot>("SELECT publisher_id, last_sequence, envelope, etag FROM relay_state WHERE id = 1");
      if (current !== undefined && current.publisher_id !== parsed.value.publisherID) return "publisherMismatch" as const;
      if (current !== undefined && current.last_sequence >= parsed.value.sequence) return "sequenceConflict" as const;
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO relay_state (id, publisher_id, last_sequence, envelope, etag, accepted_at) VALUES (1, ?, ?, ?, ?, ?)", parsed.value.publisherID, parsed.value.sequence, body.text, etag, acceptedAt);
      return undefined;
    });
    if (result !== undefined) return failure(result);
    return success(200, canonicalJSON({ protocolVersion: 1, sequence: parsed.value.sequence }), { etag });
  }

  private async getSnapshot(request: Request): Promise<Response> {
    const reader = await this.authenticatedReader(request);
    if (reader === undefined || !this.readerIsUsable(reader, this.clock.now())) return failure("unauthorized", { noStore: true });
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error, { noStore: true });
    const snapshot = this.one<StoredSnapshot>("SELECT publisher_id, last_sequence, envelope, etag FROM relay_state WHERE id = 1");
    if (snapshot === undefined) return failure("awaitingFirstPublish", { noStore: true });
    if (request.headers.get("If-None-Match") === snapshot.etag) return success(304, undefined, { etag: snapshot.etag, noStore: true });
    return success(200, snapshot.envelope, {
      bodyLimit: SNAPSHOT_LIMIT,
      etag: snapshot.etag,
      noStore: true,
    });
  }

  private async activateReader(request: Request): Promise<Response> {
    const reader = await this.authenticatedReader(request);
    const now = this.clock.now();
    if (reader === undefined || !this.readerIsUsable(reader, now)) return failure("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error);
    if (reader.activated === 0) this.ctx.storage.sql.exec("UPDATE readers SET activated = 1 WHERE reader_id = ?", reader.reader_id);
    return success(200, canonicalJSON({ activated: true, protocolVersion: 1 }));
  }

  private async registerReader(request: Request, readerID: string): Promise<Response> {
    if (!this.isInternal(request, "admin")) return failure("unauthorized");
    const body = await readBody(request, REGISTRATION_LIMIT);
    if ("error" in body) return failure(body.error);
    if (!validJSONContentType(request)) return failure("badRequest");
    const parsed = parseRegistration(body.text);
    if ("failure" in parsed) return failure(parsed.failure);
    const now = this.clock.now();
    const outcome = this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM readers WHERE activated = 0 AND pending_expires_at <= ?", now);
      const existingID = this.one<StoredReader>("SELECT reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id FROM readers WHERE reader_id = ?", readerID);
      const digestOwner = this.one<StoredReader>("SELECT reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id FROM readers WHERE token_digest = ?", parsed.value.tokenDigest);
      if (timingSafeDigestEqual(parsed.value.tokenDigest, this.secretEnv.WRITE_TOKEN_DIGEST) || timingSafeDigestEqual(parsed.value.tokenDigest, this.secretEnv.ADMIN_TOKEN_DIGEST) || (existingID !== undefined && !timingSafeDigestEqual(existingID.token_digest, parsed.value.tokenDigest)) || (digestOwner !== undefined && digestOwner.reader_id !== readerID)) return { code: "badRequest" as const };
      if (existingID !== undefined) return { expiresAt: existingID.pending_expires_at };
      const count = this.one<{ count: number }>("SELECT COUNT(*) AS count FROM readers")?.count ?? 0;
      if (count >= READER_LIMIT) return { code: "readerCapReached" as const };
      const expiresAt = now + PENDING_READER_LIFETIME_MS;
      this.ctx.storage.sql.exec("INSERT INTO readers (reader_id, token_digest, activated, pending_expires_at) VALUES (?, ?, 0, ?)", readerID, parsed.value.tokenDigest, expiresAt);
      return { expiresAt };
    });
    if ("code" in outcome) return failure(outcome.code!);
    return success(200, canonicalJSON({ expiresAt: formatTime(outcome.expiresAt), protocolVersion: 1 }));
  }

  private async listReaders(request: Request): Promise<Response> {
    if (!this.isInternal(request, "admin")) return failure("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error);
    const now = this.clock.now();
    const readers = this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM readers WHERE activated = 0 AND pending_expires_at <= ?", now);
      return this.all<Pick<StoredReader, "activated" | "reader_id">>("SELECT reader_id, activated FROM readers ORDER BY reader_id ASC");
    });
    return success(200, canonicalJSON({ protocolVersion: 1, readers: readers.map((reader) => ({ activated: reader.activated === 1, readerID: reader.reader_id })) }));
  }

  private async deleteReader(request: Request, readerID: string): Promise<Response> {
    if (!this.isInternal(request, "admin")) return failure("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error);
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM refresh_requests WHERE reader_id = ?", readerID);
      this.ctx.storage.sql.exec("DELETE FROM readers WHERE reader_id = ?", readerID);
    });
    return success(204);
  }

  private async postRefreshRequest(request: Request): Promise<Response> {
    const reader = await this.authenticatedReader(request);
    const now = this.clock.now();
    if (reader === undefined || reader.activated !== 1) return failure("unauthorized");
    const body = await readBody(request, REFRESH_LIMIT);
    if ("error" in body) return failure(body.error);
    if (!validJSONContentType(request)) return failure("badRequest");
    const parsed = parseRefreshRequest(body.text);
    if ("failure" in parsed) return failure(parsed.failure);
    const outcome = this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM refresh_requests WHERE expires_at <= ?", now);
      const current = this.one<StoredReader>("SELECT reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id FROM readers WHERE reader_id = ?", reader.reader_id);
      if (current === undefined || current.activated !== 1) return { code: "unauthorized" as const };
      if (current.last_completed_id === parsed.value.requestID) return { code: "requestAlreadyCompleted" as const };
      const existingID = this.one<StoredRefreshRequest>("SELECT request_id, reader_id, accepted_at, expires_at FROM refresh_requests WHERE request_id = ?", parsed.value.requestID);
      if (existingID !== undefined && existingID.reader_id !== current.reader_id) return { code: "badRequest" as const };
      const currentRequest = this.one<StoredRefreshRequest>("SELECT request_id, reader_id, accepted_at, expires_at FROM refresh_requests WHERE reader_id = ?", current.reader_id);
      if (currentRequest !== undefined && currentRequest.request_id === parsed.value.requestID) return { expiresAt: currentRequest.expires_at };
      if (current.last_accepted_id === parsed.value.requestID) return { code: "badRequest" as const };
      if (current.last_accepted_at !== null && now - current.last_accepted_at < REFRESH_LIFETIME_MS) return { code: "requestRateLimited" as const };
      const expiresAt = now + REFRESH_LIFETIME_MS;
      this.ctx.storage.sql.exec("INSERT INTO refresh_requests (request_id, reader_id, accepted_at, expires_at) VALUES (?, ?, ?, ?)", parsed.value.requestID, current.reader_id, now, expiresAt);
      this.ctx.storage.sql.exec("UPDATE readers SET last_accepted_at = ?, last_accepted_id = ? WHERE reader_id = ?", now, parsed.value.requestID, current.reader_id);
      return { expiresAt };
    });
    if ("code" in outcome) return failure(outcome.code!);
    return success(202, canonicalJSON({ expiresAt: formatTime(outcome.expiresAt), protocolVersion: 1 }));
  }

  private async listRefreshRequests(request: Request): Promise<Response> {
    if (!this.isInternal(request, "write")) return failure("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error, { noStore: true });
    const now = this.clock.now();
    const requests = this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM refresh_requests WHERE expires_at <= ?", now);
      return this.all<StoredRefreshRequest>("SELECT request_id, reader_id, accepted_at, expires_at FROM refresh_requests ORDER BY reader_id ASC, request_id ASC");
    });
    return success(200, canonicalJSON({ protocolVersion: 1, requests: requests.map((item) => ({ expiresAt: formatTime(item.expires_at), readerID: item.reader_id, requestID: item.request_id })) }), { noStore: true });
  }

  private async deleteRefreshRequest(request: Request, requestID: string): Promise<Response> {
    if (!this.isInternal(request, "write")) return failure("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error);
    const now = this.clock.now();
    this.ctx.storage.transactionSync(() => {
      const current = this.one<StoredRefreshRequest>("SELECT request_id, reader_id, accepted_at, expires_at FROM refresh_requests WHERE request_id = ?", requestID);
      if (current === undefined) return;
      this.ctx.storage.sql.exec("DELETE FROM refresh_requests WHERE request_id = ?", requestID);
      if (current.expires_at > now) this.ctx.storage.sql.exec("UPDATE readers SET last_completed_id = ? WHERE reader_id = ?", requestID, current.reader_id);
    });
    return success(204);
  }

  private async destroyRelay(request: Request): Promise<Response> {
    if (!this.isInternal(request, "admin")) return failure("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error);
    await this.ctx.storage.deleteAll();
    return success(204);
  }
}

export default {
  async fetch(request: Request, env: Env & SecretEnv): Promise<Response> {
    const headers = new Headers(request.headers);
    headers.delete(INTERNAL_AUTHORITY);
    const authority = fixedRouteAuthority(request);
    if (authority !== undefined) {
      if (!await isAuthorizedForWorkerRole(request, env, authority)) return failure("unauthorized");
      headers.set(INTERNAL_AUTHORITY, authority);
    }
    const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
    return stub.fetch(new Request(request, { headers }));
  },
} satisfies ExportedHandler<Env & SecretEnv>;
