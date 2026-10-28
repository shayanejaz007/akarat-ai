import { NextResponse, type NextRequest } from "next/server";
import { fail, requireAdmin } from "@/lib/admin";

/** GET /api/admin/overview — every figure on the panel's first screen, from
 *  admin_overview() (0018_admin_analytics.sql) in one round trip. */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;

  const { data, error } = await admin.db.rpc("admin_overview");
  if (error) {
    // 42883 / PGRST202: the function is not there, i.e. 0018 has not been run.
    const missing = error.code === "42883" || error.code === "PGRST202";
    return fail(missing ? "Run supabase/migrations/0018_admin_analytics.sql first." : error.message, missing ? 501 : 500);
  }
  return NextResponse.json(data);
}
