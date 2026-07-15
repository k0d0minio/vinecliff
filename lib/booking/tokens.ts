// Booking references and secret tokens. Server-only (node:crypto).
import { randomBytes, randomInt } from "node:crypto";

// No 0/O/1/I/L — these get read over the phone.
const REFERENCE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/** Human-friendly booking reference, e.g. "VC-7KMQ4". Uniqueness is enforced
 * by the database; callers retry on the (vanishingly rare) collision. */
export function makeReference(): string {
  let code = "";
  for (let i = 0; i < 5; i++) {
    code += REFERENCE_ALPHABET[randomInt(REFERENCE_ALPHABET.length)];
  }
  return `VC-${code}`;
}

/** URL-safe secret for the guest's private booking status page. */
export function makeManageToken(): string {
  return randomBytes(24).toString("base64url");
}
