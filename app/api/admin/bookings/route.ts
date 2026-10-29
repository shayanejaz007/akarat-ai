import { NextResponse, type NextRequest } from "next/server";
import { fail, isUuid, paging, people, requireAdmin, searchTerm } from "@/lib/admin";

/**
 * /api/admin/bookings — every daily-rental booking request
 * (0019_daily_rentals.sql), for watching how requests are handled. Read
 * only: approving, rejecting and confirming belong to the owner.
 *
 *   GET ?status=pending|approved|rejected|cancelled|confirmed&property=&q=&page=
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const PAGE = 50;
const STATUSES = ["pending", "approved", "rejected", "cancelled", "confirmed"];

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);
  const { from, to } = paging(url, PAGE);

  let query = admin.db
    .from("booking_requests")
    .select(
      "id,property_id,owner_id,renter_id,renter_name,check_in,check_out,nights,guests,message,nightly_price,total_price," +
        "status,owner_phone,response_note,closed_reason,cancelled_by,responded_at,created_at," +
        "properties(title_en,title_ar,city_id,status,daily_review)",
      { count: "exact" },
    );
  const status = url.searchParams.get("status");
  if (status && STATUSES.includes(status)) query = query.eq("status", status);
  const property = url.searchParams.get("property");
  if (isUuid(property)) query = query.eq("property_id", property);
  const q = searchTerm(url);
  if (q) query = query.or(`renter_name.ilike.*${q}*,message.ilike.*${q}*`);

  const { data, error, count } = await query.order("created_at", { ascending: false }).range(from, to);
  if (error) {
    const missing = error.code === "42P01" || error.code === "PGRST205" || /booking_requests/.test(error.message);
    return fail(missing ? "Run supabase/migrations/0019_daily_rentals.sql first." : error.message, missing ? 501 : 500);
  }
  const rows = (data ?? []) as unknown as Record<string, unknown>[];
  const who = await people(admin.db, rows.flatMap(r => [r.owner_id as string, r.renter_id as string]));
  const bookings = rows.map(r => ({
    ...r,
    owner: who.get(r.owner_id as string) ?? null,
    renter: who.get(r.renter_id as string) ?? null,
  }));
  return NextResponse.json({ bookings, total: count ?? bookings.length, pageSize: PAGE });
}
