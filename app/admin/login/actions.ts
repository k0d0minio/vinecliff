"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { verifyPassword } from "@/lib/auth/password";
import {
  ADMIN_SESSION_COOKIE,
  ADMIN_SESSION_MAX_AGE,
  authSecret,
  createSessionToken,
} from "@/lib/auth/session";

export type LoginState = { error?: string };

// Only allow redirects back into the admin section, never to arbitrary URLs.
function safeRedirectTarget(raw: FormDataEntryValue | null): string {
  const value = typeof raw === "string" ? raw : "";
  return value.startsWith("/admin") ? value : "/admin";
}

export async function login(
  _prevState: LoginState,
  formData: FormData
): Promise<LoginState> {
  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();
  const password = String(formData.get("password") ?? "");

  const secret = authSecret();
  if (!secret) {
    return {
      error:
        "Admin access is not configured yet. Set the AUTH_SECRET environment variable.",
    };
  }

  if (!email || !password) {
    return { error: "Enter your email and password." };
  }

  const [account] = await db
    .select()
    .from(users)
    .where(eq(users.email, email))
    .limit(1);

  // Verify against the found account, or run a throwaway comparison when no
  // account matches so the response time doesn't reveal which emails exist.
  const passwordValid = account
    ? verifyPassword(password, account.passwordHash)
    : verifyPassword(password, "scrypt$00$00") && false;

  if (!account || !passwordValid) {
    return { error: "Incorrect email or password. Please try again." };
  }

  const store = await cookies();
  store.set(
    ADMIN_SESSION_COOKIE,
    await createSessionToken(account.id, secret),
    {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: ADMIN_SESSION_MAX_AGE,
    }
  );

  redirect(safeRedirectTarget(formData.get("from")));
}
