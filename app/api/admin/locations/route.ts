import { NextResponse, type NextRequest } from "next/server";
import { fail, paging, requireAdmin, searchTerm } from "@/lib/admin";

/**
 * /api/admin/locations — governorates, cities and neighbourhoods (0023).
 *
 *   GET   ?level=gov|city|hood&q=&gov=&city=&edited=1&inactive=1&page=
 *   POST  { level: "city"|"hood", governorate_id | city_id, name_en, name_ar, aliases?, lat?, lng? }
 *         A place the dataset is missing. The id is made from the English name.
 *   PATCH { level, id, name_en?, name_ar?, aliases?, active?, lat?, lng?, governorate_id? | city_id? }
 *
 * Every change marks the row `edited`, so regenerating 0023 from GeoNames
 * never undoes it, and the website and the apps lay edited rows over the
 * file they ship with. Nothing is ever deleted: listings point at these ids,
 * and deleting a city would empty their location. A wrong place is switched
 * off instead, which hides it from pickers and leaves old listings readable.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const PAGE = 50;
const SETUP = "Run supabase/migrations/0023_locations.sql first.";
const missing = (code?: string) => code === "42P01" || code === "PGRST205" || code === "42703" || code === "PGRST204";
const TABLE = { gov: "governorates", city: "cities", hood: "neighborhoods" } as const;
type Level = keyof typeof TABLE;
const isLevel = (v: unknown): v is Level => v === "gov" || v === "city" || v === "hood";
const isId = (v: unknown): v is string => typeof v === "string" && /^[a-z0-9][a-z0-9-]{1,40}$/.test(v);

const slug = (s: string) =>
  s.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/['’`]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 36);

function fields(b: Record<string, unknown>, level: Level, creating: boolean): Record<string, unknown> | string {
  const out: Record<string, unknown> = {};
  for (const key of ["name_en", "name_ar"] as const) {
    if (b[key] === undefined) { if (creating) return `${key} is needed`; continue; }
    if (typeof b[key] !== "string" || !(b[key] as string).trim() || (b[key] as string).trim().length > 80) return `${key} must be 1–80 characters`;
    out[key] = (b[key] as string).trim();
  }
  if (b.aliases !== undefined) {
    if (!Array.isArray(b.aliases) || b.aliases.length > 20 || b.aliases.some(a => typeof a !== "string" || !a.trim() || a.length > 80)) {
      return "aliases: up to 20 spellings, each 1–80 characters";
    }
    out.aliases = [...new Set((b.aliases as string[]).map(a => a.trim()))];
  }
  for (const [key, lo, hi] of [["lat", 29, 33.5], ["lng", 34.8, 39.4]] as const) {
    if (b[key] === undefined) continue;
    if (b[key] === null) { out[key] = null; continue; }
    if (typeof b[key] !== "number" || !Number.isFinite(b[key]) || (b[key] as number) < lo || (b[key] as number) > hi) {
      return `${key} must be inside Jordan`;
    }
    out[key] = b[key];
  }
  if (b.active !== undefined) out.active = b.active === true;
  if (level === "city" && b.governorate_id !== undefined) {
    if (!isId(b.governorate_id)) return "Unknown governorate";
    out.governorate_id = b.governorate_id;
  }
  if (level === "hood" && b.city_id !== undefined) {
    if (!isId(b.city_id)) return "Unknown city";
    out.city_id = b.city_id;
  }
  return out;
}

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);
  const level = url.searchParams.get("level") ?? "city";
  if (!isLevel(level)) return fail("level is gov, city or hood", 400);
  const { from, to } = paging(url, PAGE);

  let query = admin.db.from(TABLE[level]).select("*", { count: "exact" });
  const gov = url.searchParams.get("gov");
  const city = url.searchParams.get("city");
  if (level === "city" && isId(gov)) query = query.eq("governorate_id", gov);
  if (level === "hood" && isId(city)) query = query.eq("city_id", city);
  if (url.searchParams.get("edited") === "1") query = query.eq("edited", true);
  if (url.searchParams.get("inactive") === "1") query = query.eq("active", false);
  const q = searchTerm(url);
  if (q) query = query.or(`id.ilike.*${q}*,name_en.ilike.*${q}*,name_ar.ilike.*${q}*`);
  query = level === "gov" ? query.order("sort").order("name_en") : query.order("name_en");

  const { data, error, count } = await query.range(from, to);
  if (error) return fail(missing(error.code) ? SETUP : error.message, missing(error.code) ? 501 : 500);
  const rows = (data ?? []) as Record<string, unknown>[];

  // How many listings use each place on this page, so an admin sees what a
  // change touches before making it.
  const uses = new Map<string, number>();
  if (rows.length && level !== "gov") {
    const column = level === "city" ? "city_id" : "neighborhood_id";
    const ids = rows.map(r => r.id as string);
    const { data: used } = await admin.db.from("properties").select(column).in(column, ids).limit(5000);
    for (const r of (used ?? []) as unknown as Record<string, string>[]) uses.set(r[column], (uses.get(r[column]) ?? 0) + 1);
  }
  return NextResponse.json({
    level,
    rows: rows.map(r => ({ ...r, listings: uses.get(r.id as string) ?? 0 })),
    total: count ?? rows.length,
    pageSize: PAGE,
  });
}

export async function POST(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (b.level !== "city" && b.level !== "hood") return fail("A new place is a city or a neighbourhood.", 400);
  const level = b.level;
  const f = fields(b, level, true);
  if (typeof f === "string") return fail(f, 400);
  const parent = level === "city" ? f.governorate_id : f.city_id;
  if (!parent) return fail(level === "city" ? "Choose the governorate." : "Choose the city.", 400);
  const { data: up } = await admin.db.from(level === "city" ? "governorates" : "cities").select("id").eq("id", parent).maybeSingle();
  if (!up) return fail(level === "city" ? "Unknown governorate" : "Unknown city", 400);

  const base = slug(f.name_en as string) || `place-${Date.now().toString(36)}`;
  const { data: taken } = await admin.db.from(TABLE[level]).select("id").like("id", `${base}%`).limit(200);
  const used = new Set(((taken ?? []) as { id: string }[]).map(r => r.id));
  let id = base.length >= 2 ? base : `${base}-1`;
  for (let n = 2; used.has(id); n++) id = `${base}-${n}`;

  const { error } = await admin.db.from(TABLE[level]).insert({ id, ...f, active: true, edited: true });
  if (error) return fail(missing(error.code) ? SETUP : error.message, missing(error.code) ? 501 : 500);
  return NextResponse.json({ ok: true, id });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!isLevel(b.level)) return fail("level is gov, city or hood", 400);
  if (!isId(b.id)) return fail("id required", 400);
  const f = fields(b, b.level, false);
  if (typeof f === "string") return fail(f, 400);
  if (!Object.keys(f).length) return fail("Nothing to change", 400);
  const { error, count } = await admin.db
    .from(TABLE[b.level])
    .update({ ...f, edited: true, updated_at: new Date().toISOString() }, { count: "exact" })
    .eq("id", b.id);
  if (error) {
    if (error.code === "23503") return fail(b.level === "city" ? "Unknown governorate" : "Unknown city", 400);
    return fail(missing(error.code) ? SETUP : error.message, missing(error.code) ? 501 : 500);
  }
  if (!count) return fail("No such place.", 404);
  return NextResponse.json({ ok: true });
}
