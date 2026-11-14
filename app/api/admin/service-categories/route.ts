import { NextResponse, type NextRequest } from "next/server";
import { fail, requireAdmin } from "@/lib/admin";

/**
 * /api/admin/service-categories — what people can ask for (0024).
 *
 *   GET                 every category, switched off ones too, with how many
 *                       requests each has had
 *   POST   { id, name_en, name_ar, examples_en?, examples_ar?, icon?, sort?, custom? }
 *   PATCH  { id, ...any of the above, active? }
 *   DELETE ?id=         only a category nobody has used; one with requests
 *                       is switched off instead, so their history keeps it
 *
 * The website and the apps read the active ones straight from the table, so
 * a change shows everywhere at once, with no release.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ICONS = ["plumbing", "bathroom", "electrical", "ac", "painting", "carpentry", "cleaning", "appliance",
  "water", "maintenance", "renovation", "pest", "moving", "custom"];
const SETUP = "Run supabase/migrations/0024_services.sql first.";
const missing = (code?: string) => code === "42P01" || code === "PGRST205";

function fields(b: Record<string, unknown>, creating: boolean): Record<string, unknown> | string {
  const out: Record<string, unknown> = {};
  const text = (key: string, min: number, max: number) => {
    if (b[key] === undefined) return creating && min > 0 ? `${key} is needed` : null;
    if (typeof b[key] !== "string") return `${key} must be text`;
    const v = (b[key] as string).trim();
    if (v.length < min || v.length > max) return `${key} must be ${min}–${max} characters`;
    out[key] = v;
    return null;
  };
  for (const err of [
    text("name_en", 1, 60), text("name_ar", 1, 60), text("examples_en", 0, 200), text("examples_ar", 0, 200),
  ]) if (err) return err;
  if (b.icon !== undefined) {
    if (typeof b.icon !== "string" || !ICONS.includes(b.icon)) return "Unknown icon";
    out.icon = b.icon;
  }
  if (b.sort !== undefined) {
    if (!Number.isInteger(b.sort) || (b.sort as number) < 0 || (b.sort as number) > 10000) return "sort must be a whole number";
    out.sort = b.sort;
  }
  if (b.custom !== undefined) out.custom = b.custom === true;
  if (b.active !== undefined) out.active = b.active === true;
  return out;
}

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const [cats, used] = await Promise.all([
    admin.db.from("service_categories").select("*").order("sort").order("name_en"),
    admin.db.from("service_requests").select("category_id"),
  ]);
  if (cats.error) return fail(missing(cats.error.code) ? SETUP : cats.error.message, missing(cats.error.code) ? 501 : 500);
  const counts = new Map<string, number>();
  for (const r of (used.data ?? []) as { category_id: string }[]) counts.set(r.category_id, (counts.get(r.category_id) ?? 0) + 1);
  return NextResponse.json({
    categories: (cats.data ?? []).map(c => ({ ...c, requests: counts.get(c.id) ?? 0 })),
    icons: ICONS,
  });
}

export async function POST(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const id = typeof b.id === "string" ? b.id.trim().toLowerCase() : "";
  if (!/^[a-z0-9][a-z0-9_-]{1,40}$/.test(id)) return fail("The id is 2–41 lower-case letters, digits, - or _.", 400);
  const f = fields(b, true);
  if (typeof f === "string") return fail(f, 400);
  const { error } = await admin.db.from("service_categories").insert({ id, sort: 500, ...f });
  if (error) {
    if (error.code === "23505") return fail("A category with that id already exists.", 409);
    return fail(missing(error.code) ? SETUP : error.message, missing(error.code) ? 501 : 500);
  }
  return NextResponse.json({ ok: true, id });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (typeof b.id !== "string" || !b.id) return fail("id required", 400);
  const f = fields(b, false);
  if (typeof f === "string") return fail(f, 400);
  if (!Object.keys(f).length) return fail("Nothing to change", 400);
  const { error, count } = await admin.db
    .from("service_categories")
    .update({ ...f, updated_at: new Date().toISOString() }, { count: "exact" })
    .eq("id", b.id);
  if (error) return fail(error.message);
  if (!count) return fail("No such category.", 404);
  return NextResponse.json({ ok: true });
}

export async function DELETE(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const id = new URL(request.url).searchParams.get("id");
  if (!id) return fail("id required", 400);
  const { count } = await admin.db.from("service_requests").select("id", { count: "exact", head: true }).eq("category_id", id);
  if (count) return fail("People have asked for this service, so it can only be switched off: their requests keep it.", 409);
  const { error } = await admin.db.from("service_categories").delete().eq("id", id);
  if (error) return fail(error.message);
  return NextResponse.json({ ok: true });
}
