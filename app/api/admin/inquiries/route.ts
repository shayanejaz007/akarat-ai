import { NextResponse, type NextRequest } from "next/server";
import { fail, isUuid, paging, requireAdmin, searchTerm } from "@/lib/admin";

/**
 * /api/admin/inquiries — every inquiry sent on any listing, newest first.
 *
 *   GET    ?q=&status=&property=&page=
 *   PATCH  { id, status }
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const STATUSES = ["new", "read", "replied", "closed"];
const PAGE = 50;

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);
  const { from, to } = paging(url, PAGE);

  let query = admin.db
    .from("inquiries")
    .select("id,property_id,sender_id,owner_id,name,email,phone,message,status,created_at,properties(title_en,title_ar,status)", {
      count: "exact",
    });
  const status = url.searchParams.get("status");
  if (status && STATUSES.includes(status)) query = query.eq("status", status);
  const property = url.searchParams.get("property");
  if (isUuid(property)) query = query.eq("property_id", property);
  const q = searchTerm(url);
  if (q) query = query.or(`name.ilike.*${q}*,email.ilike.*${q}*,phone.ilike.*${q}*,message.ilike.*${q}*`);

  const { data, error, count } = await query.order("created_at", { ascending: false }).range(from, to);
  if (error) return fail(error.message);
  const rows = (data ?? []) as unknown as Record<string, unknown>[];

  const owners = [...new Set(rows.map(r => r.owner_id as string))];
  const { data: people } = owners.length
    ? await admin.db.from("profiles").select("id,full_name,phone").in("id", owners)
    : { data: [] };
  const ownerBy = new Map((people ?? []).map(p => [p.id, p]));

  return NextResponse.json({
    inquiries: rows.map(r => ({ ...r, owner: ownerBy.get(r.owner_id) ?? null })),
    total: count ?? rows.length,
    pageSize: PAGE,
  });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!isUuid(b.id)) return fail("id required", 400);
  if (typeof b.status !== "string" || !STATUSES.includes(b.status)) return fail("Unknown status", 400);
  const { error } = await admin.db.from("inquiries").update({ status: b.status }).eq("id", b.id);
  if (error) return fail(error.message);
  return NextResponse.json({ ok: true });
}
