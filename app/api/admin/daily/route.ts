import { NextResponse, type NextRequest } from "next/server";
import { fail, isUuid, paging, people, requireAdmin, searchTerm } from "@/lib/admin";
import { unpackPayload } from "@/lib/listing-server";

/**
 * /api/admin/daily — daily rentals and their review (0019_daily_rentals.sql).
 *
 *   GET   ?review=pending|changed|approved|rejected|suspended&q=&page=
 *         Everything a reviewer needs on one card: every photo, both
 *         descriptions, amenities, the place, the price per night, and the
 *         owner with their email and phone.
 *   PATCH { id, action, note? }
 *         approve | reject (note required) | suspend (note required) |
 *         revoke (back to pending) | reinstate (suspended → approved) |
 *         reviewed (an approved listing's changes have been looked at)
 *
 * The database does the rest: an approved listing becomes public and gets
 * its verified badge, and the owner is notified of every decision.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const PAGE = 20;
const REVIEWS = ["pending", "approved", "rejected", "suspended"];

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);
  const { from, to } = paging(url, PAGE);
  const review = url.searchParams.get("review") || "pending";

  let query = admin.db
    .from("properties")
    .select(
      "id,status,property_type,city_id,neighborhood_id,lat,lng,location_precision,address,price_jod,max_guests,min_nights," +
        "bedrooms,bathrooms,area_sqm,title_en,title_ar,views,saves,owner_id,created_at,updated_at," +
        "daily_review,daily_review_note,daily_reviewed_at,daily_changed_at,payload_gz",
      { count: "exact" },
    )
    .eq("deal", "daily");
  if (review === "changed") query = query.eq("daily_review", "approved").not("daily_changed_at", "is", null);
  else if (REVIEWS.includes(review)) query = query.eq("daily_review", review);
  const q = searchTerm(url);
  if (q) query = isUuid(q) ? query.eq("id", q) : query.or(`title_en.ilike.*${q}*,title_ar.ilike.*${q}*`);
  // The queue is first come, first served; everything else newest first.
  query = review === "pending"
    ? query.order("created_at", { ascending: true })
    : query.order(review === "changed" ? "daily_changed_at" : "updated_at", { ascending: false });

  const { data, error, count } = await query.range(from, to);
  if (error) {
    const missing = /daily_review|deal_type/.test(error.message);
    return fail(missing ? "Run supabase/migrations/0019_daily_rentals.sql first." : error.message, missing ? 501 : 500);
  }
  const rows = (data ?? []) as unknown as Record<string, unknown>[];
  const ids = rows.map(r => r.id as string);

  const [owners, requests] = await Promise.all([
    people(admin.db, rows.map(r => r.owner_id as string)),
    ids.length
      ? admin.db.from("booking_requests").select("property_id,status").in("property_id", ids)
      : Promise.resolve({ data: [] }),
  ]);
  const counts = new Map<string, Record<string, number>>();
  for (const r of (requests.data ?? []) as { property_id: string; status: string }[]) {
    const c = counts.get(r.property_id) ?? {};
    c[r.status] = (c[r.status] ?? 0) + 1;
    counts.set(r.property_id, c);
  }

  const listings = rows.map(({ payload_gz, ...r }) => {
    const p = unpackPayload(payload_gz as string | null);
    return {
      ...r,
      media: (p.images ?? []).map(m => ({ url: m.url, video: m.type === "video" })),
      description_en: p.description_en ?? "",
      description_ar: p.description_ar ?? "",
      amenities: p.amenities ?? [],
      // A daily listing should carry no public phone; shown if one slipped in.
      publicPhone: p.contact?.phone || null,
      owner: owners.get(r.owner_id as string) ?? null,
      requests: counts.get(r.id as string) ?? {},
    };
  });
  return NextResponse.json({ listings, total: count ?? listings.length, pageSize: PAGE });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!isUuid(b.id)) return fail("id required", 400);
  const note = typeof b.note === "string" ? b.note.trim().slice(0, 500) : "";

  const { data: row, error: readError } = await admin.db
    .from("properties")
    .select("daily_review")
    .eq("id", b.id)
    .eq("deal", "daily")
    .maybeSingle();
  if (readError) return fail(readError.message);
  if (!row) return fail("No such daily rental.", 404);

  let changes: Record<string, unknown>;
  switch (b.action) {
    case "approve":
      changes = { daily_review: "approved", daily_review_note: null };
      break;
    case "reject":
      if (!note) return fail("Say why, so the owner can fix it.", 400);
      changes = { daily_review: "rejected", daily_review_note: note };
      break;
    case "suspend":
      if (!note) return fail("Say why, so the owner knows.", 400);
      changes = { daily_review: "suspended", daily_review_note: note };
      break;
    case "revoke":
      if (row.daily_review !== "approved") return fail("Only an approved listing can have its approval taken back.", 400);
      changes = { daily_review: "pending", daily_review_note: note || null };
      break;
    case "reinstate":
      if (row.daily_review !== "suspended") return fail("Only a suspended listing can be reinstated.", 400);
      changes = { daily_review: "approved", daily_review_note: null };
      break;
    case "reviewed":
      if (row.daily_review !== "approved") return fail("Only an approved listing has changes to review.", 400);
      changes = { daily_changed_at: null, daily_reviewed_at: new Date().toISOString() };
      break;
    default:
      return fail("Unknown action", 400);
  }

  const { error } = await admin.db.from("properties").update(changes).eq("id", b.id);
  if (error) return fail(error.message);
  return NextResponse.json({ ok: true });
}
