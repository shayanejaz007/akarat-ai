import { NextResponse, type NextRequest } from "next/server";
import { COOKIE, SESSION_HOURS, adminPassword, checkPassword, fail, sessionToken, validSession } from "@/lib/admin";
import { allow } from "@/lib/rate-limit";

/* Sign in to, check, and sign out of the admin panel. The password is
   ADMIN_PASSWORD in Vercel's environment variables (see lib/admin.ts). */

export const dynamic = "force-dynamic";

const cookie = (value: string, maxAge: number) => ({
  name: COOKIE,
  value,
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "strict" as const,
  path: "/api/admin",
  maxAge,
});

export async function GET(request: NextRequest) {
  if (!adminPassword()) return fail("The admin panel is not configured: set ADMIN_PASSWORD in Vercel.", 503);
  return validSession(request) ? NextResponse.json({ ok: true }) : fail("Sign in.", 401);
}

export async function POST(request: NextRequest) {
  if (!adminPassword()) return fail("The admin panel is not configured: set ADMIN_PASSWORD in Vercel.", 503);

  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  if (!(await allow(`admin-login:${ip}`, 5))) return fail("Too many attempts. Wait a minute and try again.", 429);

  const b = (await request.json().catch(() => ({}))) as { password?: unknown };
  if (typeof b.password !== "string" || !checkPassword(b.password)) return fail("Wrong password.", 401);

  const res = NextResponse.json({ ok: true });
  res.cookies.set(cookie(sessionToken(), SESSION_HOURS * 3600));
  return res;
}

export async function DELETE() {
  const res = NextResponse.json({ ok: true });
  res.cookies.set(cookie("", 0));
  return res;
}
