import { NextResponse, type NextRequest } from "next/server";
import { fail, requireAdmin } from "@/lib/admin";
import { LIMITS, MODEL, estimateCostUsd } from "@/lib/advisor/config";

/** GET /api/admin/overview — every figure on the panel's first screen, from
 *  admin_overview() (0018_admin_analytics.sql) in one round trip. */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type AiDay = { day: string; turns: number; input: number; output: number; cacheRead: number; cacheWrite: number; searches: number; fetches: number; flagged: number };
type AiOverview = {
  today: Omit<AiDay, "day"> & { people: number };
  days: AiDay[];
  flags: { kind: string; count: number }[];
};

const ammanDay = (d: Date) =>
  new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Amman", year: "numeric", month: "2-digit", day: "2-digit" }).format(d);

/** The AI advisor's month, every day present (a quiet day is a zero, not a gap), with a cost estimate. */
function advisor(raw: AiOverview) {
  const byDay = new Map(raw.days.map(d => [String(d.day).slice(0, 10), d]));
  const days = Array.from({ length: 30 }, (_, i) => {
    const day = ammanDay(new Date(Date.now() - (29 - i) * 86_400_000));
    const d = byDay.get(day);
    const cost = d ? estimateCostUsd(d) : 0;
    return { day, turns: d?.turns ?? 0, cost: cost == null ? null : Math.round(cost * 100) / 100 };
  });
  const cost = estimateCostUsd(raw.today);
  const month = days.reduce((sum, d) => sum + (d.cost ?? 0), 0);
  return {
    model: MODEL,
    limits: LIMITS,
    today: { ...raw.today, cost: cost == null ? null : Math.round(cost * 100) / 100 },
    month: { turns: days.reduce((n, d) => n + d.turns, 0), cost: Math.round(month * 100) / 100 },
    days,
    flags: raw.flags,
  };
}

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;

  const [{ data, error }, daily, ai] = await Promise.all([
    admin.db.rpc("admin_overview"),
    // Daily rentals (0019) and the AI advisor (0020). Each is absent until its
    // migration runs; the rest of the overview does not wait for either.
    admin.db.rpc("admin_daily_overview"),
    admin.db.rpc("admin_ai_overview"),
  ]);
  if (error) {
    // 42883 / PGRST202: the function is not there, i.e. 0018 has not been run.
    const missing = error.code === "42883" || error.code === "PGRST202";
    return fail(missing ? "Run supabase/migrations/0018_admin_analytics.sql first." : error.message, missing ? 501 : 500);
  }
  return NextResponse.json({
    ...data,
    dailyRentals: daily.error ? null : daily.data,
    advisor: ai.error || !ai.data ? null : advisor(ai.data as AiOverview),
  });
}
