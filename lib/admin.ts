import { NextResponse, type NextRequest } from "next/server";
import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Gate for every /api/admin/* route the panel (app/admin) calls.
 *
 * The panel has one password, ADMIN_PASSWORD, set in Vercel's environment
 * variables. Signing in (app/api/admin/session) checks it and sets an
 * httpOnly cookie carrying an expiry and an HMAC keyed from that password, so
 * changing the password in Vercel and redeploying signs every admin out. Only
 * with a valid cookie is a route handed a service-role client, which reads
 * across every owner's rows. Nothing in the browser ever holds that key.
 */

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

export const COOKIE = "akarat_admin";
export const SESSION_HOURS = 12;

export type Admin = { db: SupabaseClient };

const noSession = { auth: { persistSession: false, autoRefreshToken: false } };

/** The configured password, trimmed, or null when unset. */
export function adminPassword(): string | null {
  return process.env.ADMIN_PASSWORD?.trim() || null;
}

function key(password: string): Buffer {
  // The service key is mixed in so a cookie cannot be minted from the
  // password alone without also knowing the deployment's secret.
  return createHash("sha256").update(`akarat-admin\0${password}\0${SERVICE ?? ""}`).digest();
}

const sign = (password: string, exp: number) => createHmac("sha256", key(password)).update(`admin.${exp}`).digest("base64url");

function same(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

export function checkPassword(given: string): boolean {
  const password = adminPassword();
  if (!password) return false;
  // Compare digests so the comparison takes the same time whatever the length.
  const h = (s: string) => createHash("sha256").update(s).digest("hex");
  return same(h(given.trim()), h(password));
}

/** A fresh cookie value: "<expiry ms>.<signature>". */
export function sessionToken(): string {
  const exp = Date.now() + SESSION_HOURS * 3600_000;
  return `${exp}.${sign(adminPassword()!, exp)}`;
}

export function validSession(request: NextRequest): boolean {
  const password = adminPassword();
  const m = /^(\d{13})\.([A-Za-z0-9_-]+)$/.exec(request.cookies.get(COOKIE)?.value ?? "");
  if (!password || !m) return false;
  const exp = Number(m[1]);
  return exp > Date.now() && same(m[2], sign(password, exp));
}

/** A service-role client, or the response to send instead. */
export async function requireAdmin(request: NextRequest): Promise<Admin | NextResponse> {
  if (!URL_ || !SERVICE || !adminPassword()) {
    return NextResponse.json(
      { error: "The admin panel is not configured: set ADMIN_PASSWORD and SUPABASE_SERVICE_ROLE_KEY in Vercel." },
      { status: 503 },
    );
  }
  if (!validSession(request)) return NextResponse.json({ error: "Sign in." }, { status: 401 });
  return { db: createClient(URL_, SERVICE, noSession) };
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

export type Person = {
  id: string;
  name: string | null;
  email: string | null;
  phone: string | null;
  verified: boolean;
  joined: string | null;
};

/** Name, email and phone for each account id, from the profile and the auth
 *  record. For one page of rows at a time: one auth lookup per distinct id. */
export async function people(db: SupabaseClient, ids: (string | null | undefined)[]): Promise<Map<string, Person>> {
  const unique = [...new Set(ids.filter((v): v is string => !!v))].slice(0, 200);
  if (!unique.length) return new Map();
  const [profiles, users] = await Promise.all([
    db.from("profiles").select("id,full_name,phone,verified").in("id", unique),
    Promise.all(unique.map(id => db.auth.admin.getUserById(id).then(r => r.data.user).catch(() => null))),
  ]);
  const byId = new Map(((profiles.data ?? []) as Record<string, unknown>[]).map(p => [p.id as string, p]));
  const out = new Map<string, Person>();
  unique.forEach((id, i) => {
    const p = byId.get(id);
    const u = users[i];
    out.set(id, {
      id,
      name: (p?.full_name as string) || (u?.user_metadata?.full_name as string) || null,
      email: u?.email ?? null,
      phone: (p?.phone as string) || u?.phone || null,
      verified: p?.verified === true,
      joined: u?.created_at ?? null,
    });
  });
  return out;
}
