import { NextResponse, type NextRequest } from "next/server";
import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";

/**
 * Gate for every /api/admin/* route the panel (app/admin) calls.
 *
 * The caller sends their Supabase access token as a bearer token, the same
 * way the app does for /api/ai/search. It is verified with Supabase, and the
 * account must have profiles.role = 'admin', which nobody can set on
 * themselves through the API (0013_protect_trust_fields.sql). Only then is
 * the route handed a service-role client, which reads across every owner's
 * rows. Nothing in the browser ever holds that key.
 */

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

export type Admin = { user: User; db: SupabaseClient };

const noSession = { auth: { persistSession: false, autoRefreshToken: false } };

/** The admin and a service-role client, or the response to send instead. */
export async function requireAdmin(request: NextRequest): Promise<Admin | NextResponse> {
  if (!URL_ || !ANON || !SERVICE) {
    return NextResponse.json({ error: "The admin panel is not configured on this deployment." }, { status: 503 });
  }
  const m = /^Bearer\s+([A-Za-z0-9._-]+)$/i.exec(request.headers.get("authorization") ?? "");
  if (!m) return NextResponse.json({ error: "Sign in." }, { status: 401 });

  const { data, error } = await createClient(URL_, ANON, noSession).auth.getUser(m[1]);
  if (error || !data.user) return NextResponse.json({ error: "Sign in again." }, { status: 401 });

  const db = createClient(URL_, SERVICE, noSession);
  const { data: profile } = await db.from("profiles").select("role").eq("id", data.user.id).maybeSingle();
  if (profile?.role !== "admin") {
    return NextResponse.json({ error: "This account is not an admin." }, { status: 403 });
  }
  return { user: data.user, db };
}

export const isUuid = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);

/** page (0-based) and page size from the query string, bounded. */
export function paging(url: URL, size = 50): { from: number; to: number; page: number } {
  const page = Math.max(0, Math.min(1000, Number(url.searchParams.get("page")) || 0));
  return { page, from: page * size, to: page * size + size - 1 };
}

/** For PostgREST `or=(…ilike…)` filters: drops the characters that would
 *  change the filter's meaning rather than the text searched for. */
export function searchTerm(url: URL): string | null {
  const q = (url.searchParams.get("q") ?? "").replace(/[,()*%\\]/g, " ").trim().slice(0, 80);
  return q || null;
}

export function fail(message: string, status = 500) {
  return NextResponse.json({ error: message }, { status });
}
