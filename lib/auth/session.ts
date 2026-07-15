// Stateless admin session tokens.
//
// After a successful login we hand the browser an httpOnly cookie holding a
// signed token: `base64url(payload).hmacSignature`, where the payload is
// `<userId>.<expiryUnixSeconds>`. The signature is an HMAC-SHA256 over the
// payload keyed by `AUTH_SECRET`.
//
// Because verification only needs the secret (never the database), the Edge
// middleware can authorise every `/admin` request without a round-trip. All
// crypto here uses the Web Crypto API so it behaves identically in the Edge
// runtime and in Node server actions.

export const ADMIN_SESSION_COOKIE = "vc_admin_session";

// One week. The cookie is refreshed on each successful login.
export const ADMIN_SESSION_MAX_AGE = 60 * 60 * 24 * 7;

const encoder = new TextEncoder();

function base64urlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function sign(payload: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(payload)
  );
  return base64urlEncode(new Uint8Array(signature));
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

/** Read the signing secret, or `null` when the app is not yet configured. */
export function authSecret(): string | null {
  return process.env.AUTH_SECRET || null;
}

/** Mint a signed session token for the given user id. */
export async function createSessionToken(
  userId: string,
  secret: string,
  maxAgeSeconds: number = ADMIN_SESSION_MAX_AGE,
  nowSeconds: number = Math.floor(Date.now() / 1000)
): Promise<string> {
  const expiry = nowSeconds + maxAgeSeconds;
  const payload = `${userId}.${expiry}`;
  const signature = await sign(payload, secret);
  const encodedPayload = base64urlEncode(encoder.encode(payload));
  return `${encodedPayload}.${signature}`;
}

/**
 * Validate a session token and return the user id it carries, or `null` if the
 * token is missing, malformed, expired, or signed with a different secret.
 */
export async function verifySessionToken(
  token: string | undefined,
  secret: string | null,
  nowSeconds: number = Math.floor(Date.now() / 1000)
): Promise<string | null> {
  if (!token || !secret) return null;

  const [encodedPayload, signature] = token.split(".");
  if (!encodedPayload || !signature) return null;

  let payload: string;
  try {
    payload = new TextDecoder().decode(base64urlDecode(encodedPayload));
  } catch {
    return null;
  }

  const expectedSignature = await sign(payload, secret);
  if (!safeEqual(signature, expectedSignature)) return null;

  const [userId, expiryRaw] = payload.split(".");
  const expiry = Number(expiryRaw);
  if (!userId || !Number.isFinite(expiry) || expiry <= nowSeconds) return null;

  return userId;
}
