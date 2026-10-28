import { NextResponse, type NextRequest } from "next/server";
import { fail, isUuid, paging, requireAdmin, searchTerm } from "@/lib/admin";
import { unpackPayload } from "@/lib/listing-server";

/**
 * /api/admin/listings — every listing, whatever its status or owner.
 *
 *   GET    ?q=&status=&sort=created|views|inquiries|saves|price&page=
 *   PATCH  { id, status?, featured?, verified? }
 *   DELETE ?id=
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const STATUSES = ["draft", "pending", "active", "rejected", "paused", "sold", "rented", "archived"];
const SORTS: Record<string, string> = {
  created: "created_at",
  views: "views",
  inquiries: "inquiries_count",
  saves: "saves",
  price: "price_jod",
};
const PAGE = 40;

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);
  const { from, to } = paging(url, PAGE);

  let query = admin.db
    .from("properties")
    .select(
      "id,status,deal,property_type,city_id,neighborhood_id,price_jod,bedrooms,bathrooms,area_sqm," +
        "title_en,title_ar,views,saves,inquiries_count,featured,verified,owner_id,created_at,updated_at,payload_gz",
      { count: "exact" },
    );
  const status = url.searchParams.get("status");
  if (status && STATUSES.includes(status)) query = query.eq("status", status);
  const q = searchTerm(url);
  if (q) query = isUuid(q) ? query.eq("id", q) : query.or(`title_en.ilike.*${q}*,title_ar.ilike.*${q}*`);
  const sort = SORTS[url.searchParams.get("sort") ?? ""] ?? "created_at";
  query = query.order(sort, { ascending: false }).order("created_at", { ascending: false }).range(from, to);

  const { data, error, count } = await query;
  if (error) return fail(error.message);
  const rows = (data ?? []) as unknown as Record<string, unknown>[];

  const ids = rows.map(r => r.id as string);
  const owners = [...new Set(rows.map(r => r.owner_id as string))];
  const [stats, people] = await Promise.all([
    ids.length ? admin.db.rpc("admin_listing_stats", { p_ids: ids }) : Promise.resolve({ data: [] }),
    owners.length
      ? admin.db.from("profiles").select("id,full_name,phone,role,verified").in("id", owners)
      : Promise.resolve({ data: [] }),
  ]);
  const statBy = new Map(((stats.data ?? []) as Record<string, unknown>[]).map(s => [s.property_id, s]));
  const ownerBy = new Map(((people.data ?? []) as Record<string, unknown>[]).map(p => [p.id, p]));

  const listings = rows.map(({ payload_gz, ...r }) => {
    const p = unpackPayload(payload_gz as string | null);
    const s = statBy.get(r.id) as Record<string, unknown> | undefined;
    return {
      ...r,
      cover: p.images?.find(m => m.type !== "video")?.url ?? null,
      media: p.images?.length ?? 0,
      phone: p.contact?.phone ?? null,
      views7d: Number(s?.views_7d ?? 0),
      views30d: Number(s?.views_30d ?? 0),
      lastInquiry: s?.last_inquiry ?? null,
      owner: ownerBy.get(r.owner_id) ?? null,
    };
  });
  return NextResponse.json({ listings, total: count ?? listings.length, pageSize: PAGE });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!isUuid(b.id)) return fail("id required", 400);

  const changes: Record<string, unknown> = {};
  if (typeof b.status === "string") {
    if (!STATUSES.includes(b.status)) return fail("Unknown status", 400);
    changes.status = b.status;
    if (b.status === "active") changes.published_at = new Date().toISOString();
  }
  if (typeof b.featured === "boolean") changes.featured = b.featured;
  if (typeof b.verified === "boolean") changes.verified = b.verified;
  if (!Object.keys(changes).length) return fail("Nothing to change", 400);

  const { error } = await admin.db.from("properties").update(changes).eq("id", b.id);
  if (error) return fail(error.message);
  return NextResponse.json({ ok: true });
}

export async function DELETE(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const id = new URL(request.url).searchParams.get("id");
  if (!isUuid(id)) return fail("id required", 400);
  // Inquiries, views, saves and reports on it go with it (on delete cascade).
  const { error } = await admin.db.from("properties").delete().eq("id", id);
  if (error) return fail(error.message);
  return NextResponse.json({ ok: true });
}
