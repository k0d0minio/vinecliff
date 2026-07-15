import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  ADMIN_SESSION_COOKIE,
  authSecret,
  verifySessionToken,
} from "@/lib/auth/session";

// Gate every /admin route behind a valid session cookie. The login page and
// its assets stay public so an unauthenticated visitor can actually sign in.
// Validation only needs the signing secret, so this runs on the Edge without
// ever touching the database.
export async function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;

  if (pathname === "/admin/login") {
    return NextResponse.next();
  }

  const token = request.cookies.get(ADMIN_SESSION_COOKIE)?.value;
  if (await verifySessionToken(token, authSecret())) {
    return NextResponse.next();
  }

  const loginUrl = request.nextUrl.clone();
  loginUrl.pathname = "/admin/login";
  loginUrl.search = "";
  // Preserve where the visitor was heading so we can send them back after login.
  const target = `${pathname}${search}`;
  if (target && target !== "/admin") {
    loginUrl.searchParams.set("from", target);
  }
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: ["/admin/:path*"],
};
