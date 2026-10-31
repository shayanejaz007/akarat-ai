/**
 * Daily quotas and usage records for the advisor.
 *
 * Per-minute limits use lib/rate-limit.ts like every other route. The daily
 * ones live here, because they need a counter that survives an hour (the
 * shared rate_limits table sweeps anything older) and because each turn has a
 * cost worth recording: tokens, web searches, and anything flagged.
 *
 * Both talk to functions from 0020_ai_advisor.sql with the service-role key.
 * Until that migration runs they fall back to a counter in this process,
 * which is weaker (each warm instance counts on its own) but is not nothing,
 * the same trade lib/rate-limit.ts makes.
 */
import { createHash } from "node:crypto";

export type Verdict = "ok" | "user" | "global";

export type TurnUsage = {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  searches: number;
  fetches: number;
};

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

/** A caller's key: their user id, or a hash of their IP. Raw IPs are never stored. */
export function callerKey(userId: string | null, ip: string): string {
  if (userId) return `u:${userId}`;
  const salt = SERVICE ?? process.env.ANTHROPIC_API_KEY ?? "akarat";
  return `ip:${createHash("sha256").update(`${salt}:${ip || "anon"}`).digest("hex").slice(0, 24)}`;
}

async function rpc(fn: string, args: Record<string, unknown>, timeoutMs: number): Promise<Response | null> {
  if (!URL_ || !SERVICE) return null;
  try {
    return await fetch(`${URL_}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
      body: JSON.stringify(args),
      cache: "no-store",
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {
    return null;
  }
}

/**
 * Which counters a turn is charged to. The advisor's are in 0020; Ask a
 * Lawyer keeps its own (0021) so neither product's allowance or figures
 * move with the other's traffic.
 */
export type Pool = { name: string; take: string; record: string };
export const ADVISOR_POOL: Pool = { name: "advisor", take: "ai_usage_take", record: "ai_usage_record" };
export const LEGAL_POOL: Pool = { name: "legal", take: "legal_usage_take", record: "legal_usage_record" };

const local = new Map<string, number>();

function takeLocally(pool: Pool, key: string, perDay: number, total: number): Verdict {
  const day = new Date().toISOString().slice(0, 10);
  if (local.size > 20_000) {
    for (const k of local.keys()) if (!k.startsWith(day)) local.delete(k);
  }
  const g = `${day}|${pool.name}|global`;
  const u = `${day}|${pool.name}|${key}`;
  if ((local.get(g) ?? 0) >= total) return "global";
  if ((local.get(u) ?? 0) >= perDay) return "user";
  local.set(g, (local.get(g) ?? 0) + 1);
  local.set(u, (local.get(u) ?? 0) + 1);
  return "ok";
}

/** Counts one turn against today's allowance, or says whose allowance is spent. */
export async function takeTurn(key: string, perDay: number, total: number, pool: Pool = ADVISOR_POOL): Promise<Verdict> {
  const res = await rpc(pool.take, { p_key: key, p_limit: perDay, p_global_limit: total }, 2500);
  if (!res) return URL_ && SERVICE ? "ok" : takeLocally(pool, key, perDay, total);
  // Not installed or not permitted: configuration, so the local counter
  // stands in. Anything else is transient and fails open, as rate-limit.ts
  // does: a quota check that takes the advisor down is worse than one turn.
  if (res.status === 404 || res.status === 401 || res.status === 403) return takeLocally(pool, key, perDay, total);
  if (!res.ok) return "ok";
  const v = await res.json().catch(() => "ok");
  return v === "user" || v === "global" ? v : "ok";
}

/** Adds a finished turn's cost and flags to today's record. Never throws. */
export async function recordTurn(
  key: string,
  u: TurnUsage,
  flags: string[],
  pool: Pool = ADVISOR_POOL,
  // The turn's estimated cost and the model and effort that answered it
  // ("claude-sonnet-5-5|low"), recorded once 0022_ai_cost.sql has run.
  measured?: { costUsd: number | null; route: string }
): Promise<void> {
  const base = {
    p_key: key,
    p_input: u.input,
    p_output: u.output,
    p_cache_read: u.cacheRead,
    p_cache_write: u.cacheWrite,
    p_searches: u.searches,
    p_fetches: u.fetches,
    p_flags: [...new Set(flags)].filter(f => /^[a-z_]{1,40}$/.test(f)),
  };
  if (!measured) {
    await rpc(pool.record, base, 2500);
    return;
  }
  const route = measured.route.toLowerCase().replace(/[^a-z0-9.|_-]/g, "").slice(0, 80);
  const res = await rpc(pool.record, { ...base, p_cost_micros: Math.max(0, Math.round((measured.costUsd ?? 0) * 1_000_000)), p_route: route || null }, 2500);
  // Before 0022 the function takes no cost or route: PostgREST cannot find
  // that signature (404), and the turn is recorded without them.
  if (res && res.status === 404) await rpc(pool.record, base, 2500);
}
