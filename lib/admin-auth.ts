// Password-gated admin access.
//
// There is no user database — access is guarded by a single shared password
// supplied via the `ADMIN_PASSWORD` environment variable. On a successful
// login we store a deterministic session token in an httpOnly cookie. The
// token is derived from the password itself, so rotating (or unsetting)
// `ADMIN_PASSWORD` automatically invalidates every existing session.
//
// All helpers here use the Web Crypto API so they run identically in the
// Edge middleware and in Node server actions.

export const ADMIN_SESSION_COOKIE = "vc_admin_session";

// One week. The cookie is refreshed on each successful login.
export const ADMIN_SESSION_MAX_AGE = 60 * 60 * 24 * 7;

const encoder = new TextEncoder();

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(input));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Derive the session token for a given password. The static prefix namespaces
 * the hash so the cookie value can never be mistaken for the raw password.
 */
export async function adminSessionToken(password: string): Promise<string> {
  return sha256Hex(`vinecliff-admin::v1::${password}`);
}

/** The token a valid session cookie must hold, or `null` if unconfigured. */
export async function expectedAdminToken(): Promise<string | null> {
  const password = process.env.ADMIN_PASSWORD;
  if (!password) return null;
  return adminSessionToken(password);
}

/** Length-safe comparison to avoid leaking token contents via timing. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

/** True when the supplied cookie value corresponds to the current password. */
export async function isValidAdminSession(
  token: string | undefined
): Promise<boolean> {
  if (!token) return false;
  const expected = await expectedAdminToken();
  if (!expected) return false;
  return safeEqual(token, expected);
}
