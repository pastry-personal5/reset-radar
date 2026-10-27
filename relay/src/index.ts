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
  parseReaderProfile,
  parseRegistration,
  REFRESH_PROTOCOL_VERSION,
  REFRESH_LIMIT,
  READER_PROFILE_LIMIT,
  REGISTRATION_LIMIT,
  RESPONSE_LIMIT,
  SNAPSHOT_LIMIT,
  type ErrorCode,
} from "./domain/protocol";

const INTERNAL_AUTHORITY = "X-Reset-Radar-Authority";
const SCHEMA_VERSION = 3;
const READER_LIMIT = 3;
const PENDING_READER_LIFETIME_MS = 5 * 60 * 1000;
const REFRESH_LIFETIME_MS = 60 * 1000;

type Authority = "admin" | "read" | "write";
type InternalAuthority = Exclude<Authority, "read">;
type SecretEnv = { ADMIN_TOKEN_DIGEST?: string; WRITE_TOKEN_DIGEST?: string };
type StoredReader = {
  activated: number;
  activated_at: number | null;
  last_accepted_at: number | null;
  last_accepted_id: string | null;
  last_completed_id: string | null;
  pending_expires_at: number;
  profile_envelope: string | null;
  profile_revision: number | null;
  reader_id: string;
  token_digest: string;
};
type StoredSnapshot = { envelope: string; etag: string; last_sequence: number; publisher_id: string };
type StoredRefreshRequest = {
  accepted_at: number;
  account_id: string | null;
  expires_at: number;
  reader_id: string;
  request_id: string;
  target: "account" | "allCodex";
};
type BodyResult = { text: string } | { error: "badRequest" | "payloadTooLarge" };
type ResponseOptions = {
  bodyLimit?: number;
  etag?: string;
  noStore?: boolean;
  noTransform?: boolean;
  protocolVersion?: 1 | 2;
};

function success(status: number, body?: string, options: ResponseOptions = {}): Response {
  if (body !== undefined && new TextEncoder().encode(body).byteLength > (options.bodyLimit ?? RESPONSE_LIMIT)) {
    return failure("relayUnavailable");
  }
  const headers = new Headers();
  if (body !== undefined) headers.set("Content-Type", "application/json");
  if (options.etag !== undefined) headers.set("ETag", options.etag);
  if (options.noStore) headers.set("Cache-Control", options.noTransform ? "no-store, no-transform" : "no-store");
  return new Response(body, { headers, status });
}

function failure(code: ErrorCode, options: ResponseOptions = {}): Response {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (options.noStore) headers.set("Cache-Control", options.noTransform ? "no-store, no-transform" : "no-store");
  return new Response(errorBody(code, options.protocolVersion), { headers, status: statusFor(code) });
}

function isV2Route(url: URL): boolean {
  return url.pathname === "/v2/reader-profile" || url.pathname === "/v2/readers" ||
    url.pathname === "/v2/refresh-requests" ||
    /^\/v2\/refresh-requests\/[0-9a-f]{32}$/.test(url.pathname);
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
    (request.method === "GET" && url.pathname === "/v2/refresh-requests") ||
    (request.method === "DELETE" && /^\/v2\/refresh-requests\/[0-9a-f]{32}$/.test(url.pathname))
  ) return "write";
  if (
    (request.method === "PUT" && /^\/v1\/readers\/[0-9a-f]{32}$/.test(url.pathname)) ||
    (request.method === "GET" && url.pathname === "/v1/readers") ||
    (request.method === "GET" && url.pathname === "/v2/readers") ||
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
      const fail = (code: ErrorCode, options: ResponseOptions = {}): Response =>
        failure(code, {
          ...options,
          protocolVersion: isV2Route(url) ? REFRESH_PROTOCOL_VERSION : 1,
        });
      const schemaState = this.schemaState();
      if (schemaState === "unavailable") return fail("relayUnavailable");
      if (schemaState === "migrate" && !this.ensureSchema()) return fail("relayUnavailable");
      if (schemaState === "missing") {
        if (
          url.search === "" && request.method === "DELETE" && url.pathname === "/v1/relay" &&
          this.isInternal(request, "admin")
        ) {
          const empty = await requestHasNoBody(request);
          return "error" in empty ? failure(empty.error) : success(204);
        }
        if (this.isInternal(request, "admin") || this.isInternal(request, "write")) {
          if (!this.ensureSchema()) return fail("relayUnavailable");
        } else if (url.search === "" && (
          (request.method === "GET" && url.pathname === "/v1/snapshot") ||
          (request.method === "PUT" && url.pathname === "/v2/reader-profile") ||
          (request.method === "POST" && (
            url.pathname === "/v1/readers/activate" || url.pathname === "/v2/refresh-requests"
          ))
        )) {
          return fail("unauthorized", {
            noStore: url.pathname === "/v1/snapshot",
            noTransform: url.pathname === "/v1/snapshot",
          });
        }
      }
      if (url.search !== "") return fail("unknownRoute");
      if (request.method === "PUT" && url.pathname === "/v1/snapshot") return this.putSnapshot(request);
      if (request.method === "GET" && url.pathname === "/v1/snapshot") return this.getSnapshot(request);
      if (request.method === "POST" && url.pathname === "/v1/readers/activate") return this.activateReader(request);
      if (request.method === "PUT" && url.pathname === "/v2/reader-profile") return this.putReaderProfile(request);
      if (request.method === "GET" && url.pathname === "/v2/readers") return this.listReadersV2(request);
      if (request.method === "POST" && url.pathname === "/v2/refresh-requests") return this.postRefreshRequest(request);
      if (request.method === "GET" && url.pathname === "/v2/refresh-requests") return this.listRefreshRequests(request);
      if (request.method === "DELETE" && /^\/v2\/refresh-requests\/[0-9a-f]{32}$/.test(url.pathname)) return this.deleteRefreshRequest(request, url.pathname.split("/").at(-1)!);
      if (request.method === "PUT" && /^\/v1\/readers\/[0-9a-f]{32}$/.test(url.pathname)) return this.registerReader(request, url.pathname.split("/").at(-1)!);
      if (request.method === "GET" && url.pathname === "/v1/readers") return this.listReaders(request);
      if (request.method === "DELETE" && /^\/v1\/readers\/[0-9a-f]{32}$/.test(url.pathname)) return this.deleteReader(request, url.pathname.split("/").at(-1)!);
      if (request.method === "DELETE" && url.pathname === "/v1/relay") return this.destroyRelay(request);
      return fail("unknownRoute");
    } catch {
      const url = new URL(request.url);
      return failure("relayUnavailable", {
        protocolVersion: isV2Route(url) ? REFRESH_PROTOCOL_VERSION : 1,
      });
    }
  }

  private ensureSchema(): boolean {
    try {
      return this.ctx.storage.transactionSync(() => {
        this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS relay_schema (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL)");
        const version = this.one<{ version: number }>("SELECT version FROM relay_schema WHERE id = 1");
        if (version !== undefined && ![1, 2, SCHEMA_VERSION].includes(version.version)) {
          return false;
        }
        this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS relay_state (id INTEGER PRIMARY KEY CHECK (id = 1), publisher_id TEXT NOT NULL, last_sequence INTEGER NOT NULL, envelope TEXT NOT NULL, etag TEXT NOT NULL, accepted_at INTEGER NOT NULL)");
        this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS readers (reader_id TEXT PRIMARY KEY, token_digest TEXT NOT NULL UNIQUE, activated INTEGER NOT NULL, pending_expires_at INTEGER NOT NULL, last_accepted_at INTEGER, last_accepted_id TEXT, last_completed_id TEXT)");
        const refreshColumns = new Set(
          this.all<{ name: string }>("PRAGMA table_info(refresh_requests)")
            .map((column) => column.name),
        );
        if (refreshColumns.size > 0 && !refreshColumns.has("target")) {
          this.ctx.storage.sql.exec("ALTER TABLE refresh_requests RENAME TO refresh_requests_v1");
          this.ctx.storage.sql.exec("CREATE TABLE refresh_requests (request_id TEXT PRIMARY KEY, reader_id TEXT NOT NULL UNIQUE, target TEXT NOT NULL CHECK (target IN ('account', 'allCodex')), account_id TEXT, accepted_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, CHECK ((target = 'account' AND account_id IS NOT NULL) OR (target = 'allCodex' AND account_id IS NULL)))");
          this.ctx.storage.sql.exec("INSERT INTO refresh_requests (request_id, reader_id, target, account_id, accepted_at, expires_at) SELECT request_id, reader_id, 'allCodex', NULL, accepted_at, expires_at FROM refresh_requests_v1");
          this.ctx.storage.sql.exec("DROP TABLE refresh_requests_v1");
        } else {
          this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS refresh_requests (request_id TEXT PRIMARY KEY, reader_id TEXT NOT NULL UNIQUE, target TEXT NOT NULL CHECK (target IN ('account', 'allCodex')), account_id TEXT, accepted_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, CHECK ((target = 'account' AND account_id IS NOT NULL) OR (target = 'allCodex' AND account_id IS NULL)))");
        }
        const readerColumns = new Set(
          this.all<{ name: string }>("PRAGMA table_info(readers)").map((column) => column.name),
        );
        if (!readerColumns.has("activated_at")) this.ctx.storage.sql.exec("ALTER TABLE readers ADD COLUMN activated_at INTEGER");
        if (!readerColumns.has("profile_revision")) this.ctx.storage.sql.exec("ALTER TABLE readers ADD COLUMN profile_revision INTEGER");
        if (!readerColumns.has("profile_envelope")) this.ctx.storage.sql.exec("ALTER TABLE readers ADD COLUMN profile_envelope TEXT");
        if (version === undefined) {
          this.ctx.storage.sql.exec(
            "INSERT INTO relay_schema (id, version) VALUES (1, ?)", SCHEMA_VERSION,
          );
        } else if (version.version === 1 || version.version === 2) {
          this.ctx.storage.sql.exec(
            "UPDATE relay_schema SET version = ? WHERE id = 1", SCHEMA_VERSION,
          );
        }
        return true;
      });
    } catch { return false; }
  }

  /**
   * Reader routes must be able to reject an unknown token without materializing
   * a database. A missing schema means an empty/destroyed relay; partial or
   * version-mismatched schema state is unavailable rather than silently reset.
   */
  private schemaState(): "missing" | "migrate" | "ready" | "unavailable" {
    try {
      const tables = this.all<{ name: string }>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('relay_schema', 'relay_state', 'readers', 'refresh_requests')",
      );
      if (!tables.some((table) => table.name === "relay_schema")) {
        return tables.length === 0 ? "missing" : "unavailable";
      }
      const version = this.one<{ version: number }>("SELECT version FROM relay_schema WHERE id = 1");
      if (version?.version === SCHEMA_VERSION) {
        const names = new Set(tables.map((table) => table.name));
        if (!["relay_schema", "relay_state", "readers", "refresh_requests"].every((name) => names.has(name))) {
          return "unavailable";
        }
        const readerColumns = new Set(
          this.all<{ name: string }>("PRAGMA table_info(readers)").map((column) => column.name),
        );
        const refreshColumns = new Set(
          this.all<{ name: string }>("PRAGMA table_info(refresh_requests)")
            .map((column) => column.name),
        );
        if (!["activated_at", "profile_envelope", "profile_revision"].every((name) => readerColumns.has(name)) ||
          !["account_id", "target"].every((name) => refreshColumns.has(name))) {
          return "unavailable";
        }
        return "ready";
      }
      return version?.version === 1 || version?.version === 2 ? "migrate" : "unavailable";
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
    if (reader === undefined || !this.readerIsUsable(reader, this.clock.now())) {
      return failure("unauthorized", { noStore: true, noTransform: true });
    }
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error, { noStore: true, noTransform: true });
    const result = this.ctx.storage.transactionSync(() => {
      const current = this.one<StoredReader>("SELECT reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id FROM readers WHERE reader_id = ?", reader.reader_id);
      if (
        current === undefined ||
        !timingSafeDigestEqual(current.token_digest, reader.token_digest) ||
        !this.readerIsUsable(current, this.clock.now())
      ) {
        return { code: "unauthorized" as const };
      }
      const stored = this.one<StoredSnapshot>("SELECT publisher_id, last_sequence, envelope, etag FROM relay_state WHERE id = 1");
      return stored === undefined ? { code: "awaitingFirstPublish" as const } : { code: "ok" as const, stored };
    });
    if (result.code !== "ok") return failure(result.code, { noStore: true, noTransform: true });
    const snapshot = result.stored;
    if (request.headers.get("If-None-Match") === snapshot.etag) {
      return success(304, undefined, { etag: snapshot.etag, noStore: true, noTransform: true });
    }
    return success(200, snapshot.envelope, {
      bodyLimit: SNAPSHOT_LIMIT,
      etag: snapshot.etag,
      noStore: true,
      noTransform: true,
    });
  }

  private async activateReader(request: Request): Promise<Response> {
    const reader = await this.authenticatedReader(request);
    const now = this.clock.now();
    if (reader === undefined || !this.readerIsUsable(reader, now)) return failure("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error);
    const activated = this.ctx.storage.transactionSync(() => {
      const current = this.one<StoredReader>("SELECT reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id FROM readers WHERE reader_id = ?", reader.reader_id);
      if (
        current === undefined ||
        !timingSafeDigestEqual(current.token_digest, reader.token_digest) ||
        !this.readerIsUsable(current, this.clock.now())
      ) {
        return false;
      }
      if (current.activated === 0) {
        this.ctx.storage.sql.exec(
          "UPDATE readers SET activated = 1, activated_at = COALESCE(activated_at, ?) WHERE reader_id = ?",
          now, current.reader_id,
        );
      }
      return true;
    });
    if (!activated) return failure("unauthorized");
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

  private async putReaderProfile(request: Request): Promise<Response> {
    const fail = (code: ErrorCode): Response => failure(code, { protocolVersion: 2 });
    const reader = await this.authenticatedReader(request);
    if (reader === undefined || reader.activated !== 1) return fail("unauthorized");
    const body = await readBody(request, READER_PROFILE_LIMIT);
    if ("error" in body) return fail(body.error);
    if (!validJSONContentType(request)) return fail("badRequest");
    const parsed = parseReaderProfile(body.text);
    if ("failure" in parsed) return fail(parsed.failure);
    if (parsed.value.readerID !== reader.reader_id) return fail("badRequest");
    const result = this.ctx.storage.transactionSync(() => {
      const current = this.one<Pick<StoredReader, "activated" | "profile_envelope" | "profile_revision" | "reader_id">>(
        "SELECT reader_id, activated, profile_revision, profile_envelope FROM readers WHERE reader_id = ?",
        reader.reader_id,
      );
      if (current === undefined || current.activated !== 1) return "unauthorized" as const;
      if (current.profile_revision !== null && parsed.value.revision < current.profile_revision) {
        return "sequenceConflict" as const;
      }
      if (
        current.profile_revision === parsed.value.revision &&
        current.profile_envelope !== body.text
      ) return "sequenceConflict" as const;
      if (current.profile_revision === null || parsed.value.revision > current.profile_revision) {
        this.ctx.storage.sql.exec(
          "UPDATE readers SET profile_revision = ?, profile_envelope = ? WHERE reader_id = ?",
          parsed.value.revision, body.text, reader.reader_id,
        );
      }
      return undefined;
    });
    if (result !== undefined) return fail(result);
    return success(200, canonicalJSON({ protocolVersion: 2, revision: parsed.value.revision }));
  }

  private async listReadersV2(request: Request): Promise<Response> {
    if (!this.isInternal(request, "admin")) {
      return failure("unauthorized", { protocolVersion: 2 });
    }
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return failure(empty.error, { protocolVersion: 2 });
    const now = this.clock.now();
    const readers = this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM readers WHERE activated = 0 AND pending_expires_at <= ?", now);
      return this.all<Pick<StoredReader, "activated" | "activated_at" | "profile_envelope" | "reader_id">>(
        "SELECT reader_id, activated, activated_at, profile_envelope FROM readers ORDER BY reader_id ASC",
      );
    });
    return success(200, canonicalJSON({
      protocolVersion: 2,
      readers: readers.map((reader) => ({
        activated: reader.activated === 1,
        ...(reader.activated_at === null ? {} : { activatedAt: formatTime(reader.activated_at) }),
        ...(reader.profile_envelope === null
          ? {}
          : { profile: JSON.parse(reader.profile_envelope) as unknown }),
        readerID: reader.reader_id,
      })),
    }), { bodyLimit: 8 * 1024, noStore: true });
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
    const fail = (code: ErrorCode): Response =>
      failure(code, { protocolVersion: REFRESH_PROTOCOL_VERSION });
    const reader = await this.authenticatedReader(request);
    const now = this.clock.now();
    if (reader === undefined || reader.activated !== 1) return fail("unauthorized");
    const body = await readBody(request, REFRESH_LIMIT);
    if ("error" in body) return fail(body.error);
    if (!validJSONContentType(request)) return fail("badRequest");
    const parsed = parseRefreshRequest(body.text);
    if ("failure" in parsed) return fail(parsed.failure);
    const target = parsed.value.target;
    const accountID = target === "account" ? parsed.value.accountID : null;
    const outcome = this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM refresh_requests WHERE expires_at <= ?", now);
      const current = this.one<StoredReader>("SELECT reader_id, token_digest, activated, pending_expires_at, last_accepted_at, last_accepted_id, last_completed_id FROM readers WHERE reader_id = ?", reader.reader_id);
      if (current === undefined || current.activated !== 1) return { code: "unauthorized" as const };
      if (current.last_completed_id === parsed.value.requestID) return { code: "requestAlreadyCompleted" as const };
      const existingID = this.one<StoredRefreshRequest>("SELECT request_id, reader_id, target, account_id, accepted_at, expires_at FROM refresh_requests WHERE request_id = ?", parsed.value.requestID);
      if (existingID !== undefined && existingID.reader_id !== current.reader_id) return { code: "badRequest" as const };
      if (
        existingID !== undefined &&
        (existingID.target !== target || existingID.account_id !== accountID)
      ) return { code: "badRequest" as const };
      const currentRequest = this.one<StoredRefreshRequest>("SELECT request_id, reader_id, target, account_id, accepted_at, expires_at FROM refresh_requests WHERE reader_id = ?", current.reader_id);
      if (currentRequest !== undefined && currentRequest.request_id === parsed.value.requestID) {
        return { expiresAt: currentRequest.expires_at };
      }
      if (current.last_accepted_id === parsed.value.requestID) return { code: "badRequest" as const };
      if (current.last_accepted_at !== null && now - current.last_accepted_at < REFRESH_LIFETIME_MS) return { code: "requestRateLimited" as const };
      const expiresAt = now + REFRESH_LIFETIME_MS;
      this.ctx.storage.sql.exec("INSERT INTO refresh_requests (request_id, reader_id, target, account_id, accepted_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)", parsed.value.requestID, current.reader_id, target, accountID, now, expiresAt);
      this.ctx.storage.sql.exec("UPDATE readers SET last_accepted_at = ?, last_accepted_id = ? WHERE reader_id = ?", now, parsed.value.requestID, current.reader_id);
      return { expiresAt };
    });
    if ("code" in outcome) return fail(outcome.code!);
    return success(202, canonicalJSON({
      expiresAt: formatTime(outcome.expiresAt),
      protocolVersion: REFRESH_PROTOCOL_VERSION,
    }));
  }

  private async listRefreshRequests(request: Request): Promise<Response> {
    const fail = (code: ErrorCode, options: ResponseOptions = {}): Response =>
      failure(code, { ...options, protocolVersion: REFRESH_PROTOCOL_VERSION });
    if (!this.isInternal(request, "write")) return fail("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return fail(empty.error, { noStore: true });
    const now = this.clock.now();
    const requests = this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM refresh_requests WHERE expires_at <= ?", now);
      return this.all<StoredRefreshRequest>("SELECT request_id, reader_id, target, account_id, accepted_at, expires_at FROM refresh_requests ORDER BY reader_id ASC, request_id ASC");
    });
    return success(200, canonicalJSON({
      protocolVersion: REFRESH_PROTOCOL_VERSION,
      requests: requests.map((item) => item.target === "account"
        ? {
          accountID: item.account_id,
          expiresAt: formatTime(item.expires_at),
          readerID: item.reader_id,
          requestID: item.request_id,
          target: item.target,
        }
        : {
          expiresAt: formatTime(item.expires_at),
          readerID: item.reader_id,
          requestID: item.request_id,
          target: item.target,
        }),
    }), { noStore: true });
  }

  private async deleteRefreshRequest(request: Request, requestID: string): Promise<Response> {
    const fail = (code: ErrorCode): Response =>
      failure(code, { protocolVersion: REFRESH_PROTOCOL_VERSION });
    if (!this.isInternal(request, "write")) return fail("unauthorized");
    const empty = await requestHasNoBody(request);
    if ("error" in empty) return fail(empty.error);
    const now = this.clock.now();
    this.ctx.storage.transactionSync(() => {
      const current = this.one<StoredRefreshRequest>("SELECT request_id, reader_id, target, account_id, accepted_at, expires_at FROM refresh_requests WHERE request_id = ?", requestID);
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
      if (!await isAuthorizedForWorkerRole(request, env, authority)) {
        return failure("unauthorized", {
          protocolVersion: isV2Route(new URL(request.url))
            ? REFRESH_PROTOCOL_VERSION
            : 1,
        });
      }
      headers.set(INTERNAL_AUTHORITY, authority);
    }
    const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
    return stub.fetch(new Request(request, { headers }));
  },
} satisfies ExportedHandler<Env & SecretEnv>;
