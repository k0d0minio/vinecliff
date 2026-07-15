"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import {
  ADMIN_SESSION_COOKIE,
  ADMIN_SESSION_MAX_AGE,
  adminSessionToken,
} from "@/lib/admin-auth";

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
  const password = String(formData.get("password") ?? "");
  const configured = process.env.ADMIN_PASSWORD;

  if (!configured) {
    return {
      error:
        "Admin access is not configured yet. Set the ADMIN_PASSWORD environment variable.",
    };
  }

  if (!password || password !== configured) {
    return { error: "Incorrect password. Please try again." };
  }

  const store = await cookies();
  store.set(ADMIN_SESSION_COOKIE, await adminSessionToken(password), {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: ADMIN_SESSION_MAX_AGE,
  });

  redirect(safeRedirectTarget(formData.get("from")));
}
