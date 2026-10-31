import { NextResponse, type NextRequest } from "next/server";
import { fail, requireAdmin } from "@/lib/admin";
import { LIMITS, MODEL, estimateCostUsd } from "@/lib/advisor/config";
import { ACCESS, LIMITS as LEGAL_LIMITS, MODEL as LEGAL_MODEL, REVIEWERS } from "@/lib/legal/config";
import { AAD, openText } from "@/lib/legal/crypto";

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

/** A month of an assistant's use, every day present (a quiet day is a zero, not a gap), with a cost estimate. */
function usage(raw: AiOverview, model: string) {
  const byDay = new Map(raw.days.map(d => [String(d.day).slice(0, 10), d]));
  const days = Array.from({ length: 30 }, (_, i) => {
    const day = ammanDay(new Date(Date.now() - (29 - i) * 86_400_000));
    const d = byDay.get(day);
    const cost = d ? estimateCostUsd(d, model) : 0;
    return { day, turns: d?.turns ?? 0, cost: cost == null ? null : Math.round(cost * 100) / 100 };
  });
  const cost = estimateCostUsd(raw.today, model);
  const month = days.reduce((sum, d) => sum + (d.cost ?? 0), 0);
  return {
    model,
    today: { ...raw.today, cost: cost == null ? null : Math.round(cost * 100) / 100 },
    month: { turns: days.reduce((n, d) => n + d.turns, 0), cost: Math.round(month * 100) / 100 },
    days,
    flags: raw.flags,
  };
}

const advisor = (raw: AiOverview) => ({ ...usage(raw, MODEL), limits: LIMITS });

type CostSummary = { todayMicros: number; monthMicros: number; days: { day: string; micros: number }[]; mix: Record<string, number> };

/** What each assistant actually recorded per answer (0022), in dollars, with the model and effort mix. */
function measured(r: { data: unknown; error: unknown }) {
  if (r.error || !r.data) return null;
  const c = r.data as CostSummary;
  const usd = (micros: number) => Math.round(Number(micros) / 10_000) / 100;
  return {
    today: usd(c.todayMicros),
    month: usd(c.monthMicros),
    mix: Object.entries(c.mix ?? {}).map(([route, n]) => ({ route, n: Number(n) })).sort((a, b) => b.n - a.n),
  };
}

type LegalOverview = AiOverview & {
  answers: { total: number; withCitations: number; withUnverified: number; cited: number; unverified: number };
  library: {
    sources: number; verified: number; judgments: number; legislation: number; commentary: number;
    repealed: number; stale: number; oldestCheck: string | null; passages: number; embedded: number;
  };
  feedback: {
    counts: { kind: string; count: number }[];
    recent: { id: number; at: string; kind: string; reviewer: boolean; ref: number; note: string | null; snapshot: string | null }[];
  };
};

/**
 * Ask a Lawyer: use and cost, how many answers carried a reference nothing
 * retrieved could support, how much of the library is verified and how
 * fresh, and the reports from the launch review. Report notes and reviewers'
 * snapshots are opened here, for the panel only; they are sealed everywhere
 * else.
 */
function legal(raw: LegalOverview) {
  const open = (sealed: string | null, aad: string) => (sealed ? openText(sealed, aad) : null);
  return {
    ...usage(raw, LEGAL_MODEL),
    limits: LEGAL_LIMITS,
    access: ACCESS,
    reviewers: REVIEWERS.length,
    answers: raw.answers,
    library: raw.library,
    feedback: {
      counts: raw.feedback.counts,
      recent: raw.feedback.recent.map(r => {
        const snapshot = open(r.snapshot, AAD.snapshot(r.ref));
        let parsed: { question: string; answer: string; sources: { kind: string; title: string; url: string; status: string | null }[]; unverified: string[] } | null = null;
        try {
          parsed = snapshot ? JSON.parse(snapshot) : null;
        } catch {
          parsed = null;
        }
        return {
          id: r.id,
          at: r.at,
          kind: r.kind,
          reviewer: r.reviewer,
          note: r.note ? open(r.note, AAD.feedbackNote(r.ref)) ?? "(sealed with a key this server does not have)" : null,
          snapshot: parsed,
        };
      }),
    },
  };
}

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;

  const [{ data, error }, daily, ai, law, aiCost, lawCost] = await Promise.all([
    admin.db.rpc("admin_overview"),
    // Daily rentals (0019), the AI advisor (0020) and Ask a Lawyer (0021).
    // Each is absent until its migration runs; the rest of the overview does
    // not wait for any of them.
    admin.db.rpc("admin_daily_overview"),
    admin.db.rpc("admin_ai_overview"),
    admin.db.rpc("admin_legal_overview"),
    // Measured cost and model mix (0022); absent before it runs.
    admin.db.rpc("ai_cost_summary", { p_table: "ai_usage_daily" }),
    admin.db.rpc("ai_cost_summary", { p_table: "legal_usage_daily" }),
  ]);
  if (error) {
    // 42883 / PGRST202: the function is not there, i.e. 0018 has not been run.
    const missing = error.code === "42883" || error.code === "PGRST202";
    return fail(missing ? "Run supabase/migrations/0018_admin_analytics.sql first." : error.message, missing ? 501 : 500);
  }
  return NextResponse.json({
    ...data,
    dailyRentals: daily.error ? null : daily.data,
    advisor: ai.error || !ai.data ? null : { ...advisor(ai.data as AiOverview), measured: measured(aiCost) },
    legal: law.error || !law.data ? null : { ...legal(law.data as LegalOverview), measured: measured(lawCost) },
  });
}
