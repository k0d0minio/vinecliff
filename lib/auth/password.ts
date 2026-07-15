// Password hashing for admin accounts.
//
// Uses scrypt from Node's built-in crypto — no third-party dependency, and
// strong by default (N=16384, r=8, p=1). Hashes are stored as
// `scrypt$<saltHex>$<derivedHex>` so the salt travels with the hash and the
// scheme is self-describing for future migrations.
//
// This module is Node-only (it imports `node:crypto`) and must therefore be
// used from server actions / Node scripts, never from Edge middleware.
import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";

const KEY_LENGTH = 64;
const SCHEME = "scrypt";

export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  const derived = scryptSync(password, salt, KEY_LENGTH);
  return `${SCHEME}$${salt.toString("hex")}$${derived.toString("hex")}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const [scheme, saltHex, hashHex] = stored.split("$");
  if (scheme !== SCHEME || !saltHex || !hashHex) return false;

  const expected = Buffer.from(hashHex, "hex");
  const derived = scryptSync(password, Buffer.from(saltHex, "hex"), KEY_LENGTH);
  if (expected.length !== derived.length) return false;
  return timingSafeEqual(expected, derived);
}
