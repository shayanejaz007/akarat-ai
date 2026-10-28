import { NextResponse, type NextRequest } from "next/server";
import { fail, isUuid, paging, requireAdmin } from "@/lib/admin";

/**
 * /api/admin/reports — listings people reported from the app
 * (0015_listing_reports.sql). Both app stores expect someone to act on these
 * promptly.
 *
 *   GET    ?status=open|reviewed|removed|dismissed&page=
 *   PATCH  { id, status, pauseListing? }
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const STATUSES = ["open", "reviewed", "removed", "dismissed"];
const PAGE = 50;

const missing = (code?: string) => code === "42P01" || code === "PGRST205";

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);
  const { from, to } = paging(url, PAGE);

  let query = admin.db
    .from("listing_reports")
    .select("id,property_id,reporter_id,reason,details,status,created_at,properties(title_en,title_ar,status,owner_id)", {
      count: "exact",
    });
  const status = url.searchParams.get("status");
  if (status && STATUSES.includes(status)) query = query.eq("status", status);

  const { data, error, count } = await query.order("created_at", { ascending: false }).range(from, to);
  if (error) {
    if (missing(error.code)) return NextResponse.json({ reports: [], total: 0, pageSize: PAGE, notSetUp: true });
    return fail(error.message);
  }
  return NextResponse.json({ reports: data ?? [], total: count ?? 0, pageSize: PAGE });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!isUuid(b.id)) return fail("id required", 400);
  if (typeof b.status !== "string" || !STATUSES.includes(b.status)) return fail("Unknown status", 400);

  const { data: report, error } = await admin.db
    .from("listing_reports")
    .update({ status: b.status })
    .eq("id", b.id)
    .select("property_id")
    .single();
  if (error) return fail(error.message);

  // "Removed" takes the listing off the site without deleting the owner's work.
  if (b.pauseListing === true || b.status === "removed") {
    const { error: e2 } = await admin.db.from("properties").update({ status: "paused" }).eq("id", report.property_id);
    if (e2) return fail(e2.message);
  }
  return NextResponse.json({ ok: true });
}
