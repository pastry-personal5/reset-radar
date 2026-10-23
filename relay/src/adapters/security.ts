import { decodeBase64URL, encodeBase64URL, isDigest } from "../domain/protocol";

export async function bearerDigest(request: Request): Promise<string | undefined> {
  const authorization = request.headers.get("Authorization");
  if (authorization === null || !authorization.startsWith("Bearer ")) {
    return undefined;
  }
  const token = authorization.slice("Bearer ".length);
  if (!/^[A-Za-z0-9_-]+$/.test(token) || token.length % 4 === 1) {
    return undefined;
  }
  try {
    const raw = decodeBase64URL(token);
    if (raw.byteLength !== 32 || encodeBase64URL(raw) !== token) {
      return undefined;
    }
    return bytesToHex(await crypto.subtle.digest("SHA-256", raw));
  } catch {
    return undefined;
  }
}

export function timingSafeDigestEqual(left: string | undefined, right: string | undefined): boolean {
  if (left === undefined || right === undefined || !isDigest(left) || !isDigest(right)) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export function bytesToHex(value: ArrayBuffer): string {
  return [...new Uint8Array(value)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
