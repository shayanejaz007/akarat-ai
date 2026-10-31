/**
 * Settings for the AI property advisor (POST /api/ai/advisor).
 *
 * Server-only. Everything here can be tuned from the environment without a
 * code change, the way ADMIN_PASSWORD is: set the variable in Vercel and
 * redeploy. The defaults are the ones the advisor was built and tested with.
 */

import { effortFromEnv, estimateCostUsd as estimate, modelFromEnv, numberFromEnv, type Effort, type UsageLike } from "../ai-models.ts";

const env = (name: string) => (process.env[name] ?? "").trim();

const int = (name: string, fallback: number, min: number, max: number) => {
  const n = Number.parseInt(env(name), 10);
  return Number.isFinite(n) && n >= min && n <= max ? n : fallback;
};

export type { Effort };

/* ── The model, and how much it thinks ──────────────────────────────────
   Claude Sonnet 5.5 by default: half Claude Opus 5.5's price per token, and
   Anthropic's recommended starting point for search and short tool use is
   low effort. Questions about investing (yields, returns, financing, where
   to put money) are routed to high effort, decided by the deterministic test
   below, not by another model. Both are environment settings; the model
   benchmark (scripts/model-benchmark.mts) is how to choose them. */
export const MODEL = modelFromEnv("AI_ADVISOR_MODEL", "claude-sonnet-5-5");
export const EFFORT: Effort = effortFromEnv("AI_ADVISOR_EFFORT", "low");
export const INVESTMENT_EFFORT: Effort = effortFromEnv("AI_ADVISOR_EFFORT_INVESTMENT", "high");

// Questions and answers about investing, financing or where prices are going.
export const INVESTMENT_TALK =
  /\b(invest(ing|ment|or)?s?|yields?|roi|returns? on|rental income|appreciat(e|ion)|capital gains?|mortgages?|financing|forecasts?|price trends?)\b|استثمار|أستثمر|استثمر|عائد|عوائد|تمويل|قرض|رهن|توقعات|ارتفاع الأسعار|اتجاه الأسعار/i;

export type Route = { model: string; effort: Effort; route: "search" | "investment"; maxTokens: number };

/** Which model and effort answer this message. */
export function routeAdvisor(message: string): Route {
  return INVESTMENT_TALK.test(message)
    ? { model: MODEL, effort: INVESTMENT_EFFORT, route: "investment", maxTokens: 12000 }
    : { model: MODEL, effort: EFFORT, route: "search", maxTokens: 8000 };
}

// Per model call, for code that does not route. Thinking counts toward it,
// so it is sized for thinking plus a full reply.
export const MAX_TOKENS = 8000;

/* ── Limits on one turn ─────────────────────────────────────────────────
   A turn is one user message and everything the advisor does to answer it. */
export const TURN = {
  maxModelCalls: 6,
  // Searches and page reads Claude may make inside one model call. The tools
  // list cannot change mid-turn (it would invalidate the turn's own thinking),
  // so the per-turn ceiling is enforced by forcing a final answer instead.
  webSearchesPerCall: 3,
  webFetchesPerCall: 3,
  webSearchesPerTurn: 6,
  webFetchesPerTurn: 4,
  // Output tokens across the whole turn before the advisor is told to answer.
  outputBudget: 14000,
  // Wall clock. The function limit is 60s; past softMs no new research starts,
  // and at hardMs the stream ends with whatever has been written.
  softMs: 38_000,
  hardMs: 54_000,
  // Estimated cost of one answer, in US dollars, past which the advisor is
  // told to stop researching and answer.
  maxCostUsd: numberFromEnv("AI_ADVISOR_MAX_TURN_USD", 0.3, 0.02, 5),
};

/* ── Limits on callers ──────────────────────────────────────────────────── */
export const LIMITS = {
  perMinuteSignedIn: int("AI_ADVISOR_PER_MINUTE_USER", 8, 1, 120),
  perMinuteAnonymous: int("AI_ADVISOR_PER_MINUTE_IP", 5, 1, 120),
  perDaySignedIn: int("AI_ADVISOR_DAILY_PER_USER", 80, 1, 10_000),
  perDayAnonymous: int("AI_ADVISOR_DAILY_PER_IP", 30, 1, 10_000),
  // Every caller together. The ceiling on what a day can cost, whatever
  // happens to traffic; see DEPLOY.md for what a turn costs.
  perDayTotal: int("AI_ADVISOR_DAILY_TOTAL", 600, 1, 1_000_000),
};

export const INPUT = {
  maxMessageChars: 2000,
  // The signed conversation the browser sends back each turn.
  maxTranscriptBytes: 160_000,
  maxTurnsKept: 16,
  maxTranscriptChars: 40_000,
};

/* ── Where the advisor may look outside Akarat.ai ───────────────────────
   Two lists, both enforced by Anthropic's web tools (allowed_domains) and
   again here before anything found is shown as a listing.

   PORTALS are where external LISTINGS may come from. Both were checked live
   (October 2026) and have listing pages that load without JavaScript. Only
   search and per-request page reads are used: no crawling, and Anthropic's
   fetcher honours each site's robots.txt.

   RESEARCH sites are where market facts may come from: the official sources
   for transactions, fees and statistics, and the national and business press
   that reports them. Nothing outside these two lists can be searched or read. */
export type Portal = { host: string; name: string; nameAr: string };

const DEFAULT_PORTALS: Portal[] = [
  { host: "jo.opensooq.com", name: "OpenSooq", nameAr: "السوق المفتوح" },
  { host: "bayut.jo", name: "Bayut", nameAr: "بيوت" },
];

const DEFAULT_RESEARCH = [
  "dls.gov.jo",          // Department of Lands and Survey: transactions, fees
  "dos.gov.jo",          // Department of Statistics
  "cbj.gov.jo",          // Central Bank of Jordan: rates, lending
  "ammancity.gov.jo",    // Greater Amman Municipality: planning, projects
  "aseza.jo",            // Aqaba Special Economic Zone Authority
  "petra.gov.jo",        // Jordan News Agency
  "jordantimes.com",
  "jordannews.jo",
  "ammonnews.net",
  "royanews.tv",
  "almamlakatv.com",
  "alghad.com",
  "alrai.com",
  "addustour.com",
  "zawya.com",
  "globalpropertyguide.com",
];

const hostList = (raw: string) =>
  raw
    .split(",")
    .map(h => h.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, ""))
    .filter(h => /^[a-z0-9.-]+\.[a-z]{2,}$/.test(h));

// AI_ADVISOR_PORTALS adds portals as host=Name pairs: "example.jo=Example".
export const PORTALS: Portal[] = (() => {
  const extra = env("AI_ADVISOR_PORTALS")
    .split(",")
    .map(pair => {
      const [h, name] = pair.split("=");
      const [host] = hostList(h ?? "");
      return host ? { host, name: (name ?? host).trim().slice(0, 40), nameAr: (name ?? host).trim().slice(0, 40) } : null;
    })
    .filter((p): p is Portal => !!p);
  const all = [...DEFAULT_PORTALS, ...extra];
  return all.filter((p, i) => all.findIndex(q => q.host === p.host) === i);
})();

export const RESEARCH_DOMAINS: string[] = [...new Set([...DEFAULT_RESEARCH, ...hostList(env("AI_ADVISOR_RESEARCH_DOMAINS"))])];

export const WEB_DOMAINS: string[] = [...new Set([...PORTALS.map(p => p.host), ...RESEARCH_DOMAINS])];

/** "www.bayut.jo" and "bayut.jo" are the same site; a subdomain of an allowed host is allowed. */
export function hostAllowed(host: string, list: string[]): boolean {
  const h = host.toLowerCase().replace(/^www\./, "");
  return list.some(d => h === d || h.endsWith("." + d));
}

export function portalFor(url: string): Portal | null {
  let host: string;
  try {
    host = new URL(url).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return null;
  }
  return PORTALS.find(p => host === p.host || host.endsWith("." + p.host)) ?? null;
}

export const SITE_URL = (env("NEXT_PUBLIC_SITE_URL") || "https://akarat.ai").replace(/\/+$/, "");

/* ── What a turn costs ───────────────────────────────────────────────────
   Prices live in lib/ai-models.ts, shared with Ask a Lawyer. */
export function estimateCostUsd(u: UsageLike, model = MODEL): number | null {
  return estimate(u, model);
}
