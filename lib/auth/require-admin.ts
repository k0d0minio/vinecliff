// Session check for admin server actions. The middleware already gates every
// /admin route, but actions re-verify the cookie themselves so a mutation can
// never run without a valid session regardless of how it was invoked.
import { cookies } from "next/headers";
import {
  ADMIN_SESSION_COOKIE,
  authSecret,
  verifySessionToken,
} from "@/lib/auth/session";

export async function requireAdmin(): Promise<string> {
  const store = await cookies();
  const token = store.get(ADMIN_SESSION_COOKIE)?.value;
  const userId = await verifySessionToken(token, authSecret());
  if (!userId) throw new Error("Unauthorized: admin session required.");
  return userId;
}
