/**
 * Ask a Lawyer: the model, the limits, the sources it may read, and who may
 * use it. Separate from lib/advisor/config.ts on purpose: the legal assistant
 * has its own instructions, tools, allowances and data, and changing one
 * product's settings must never move the other's.
 */

import { effortFromEnv, modelFromEnv, notCheaper, numberFromEnv, type Effort } from "../ai-models.ts";

/* ── The model, and how much it thinks ──────────────────────────────────
   Claude Sonnet 5.5 at medium effort by default. Questions that need more
   (a document to review, courts and case law, deadlines, criminal or
   inheritance matters, a long account of the facts) get high effort and a
   larger research budget, decided by the deterministic test in routeLegal,
   not by another model.

   Escalation to a stronger model is off unless LEGAL_ESCALATION_MODEL is set
   (for example claude-opus-5-5): it should be switched on only for the
   triggers where the evaluation (scripts/model-benchmark.mts) shows it does
   better. A legal answer is never routed to a cheaper model than MODEL:
   an escalation model priced below it, or one with no known price, is
   ignored and the server log says so. */
export const MODEL = modelFromEnv("LEGAL_AI_MODEL", "claude-sonnet-5-5");
export const EFFORT: Effort = effortFromEnv("LEGAL_AI_EFFORT", "medium");
export const COMPLEX_EFFORT: Effort = effortFromEnv("LEGAL_AI_EFFORT_COMPLEX", "high");

export type Escalation = { model: string; effort: Effort; triggers: string[] };
export const ESCALATION: Escalation = {
  model: process.env.LEGAL_ESCALATION_MODEL ? modelFromEnv("LEGAL_ESCALATION_MODEL", "") : "",
  effort: effortFromEnv("LEGAL_ESCALATION_EFFORT", "medium"),
  // Which complex questions escalate: any of "document", "court", "urgent",
  // "long". Empty means every complex question, once a model is set.
  triggers: (process.env.LEGAL_ESCALATE_ON || "").split(",").map(s => s.trim()).filter(Boolean),
};
if (ESCALATION.model && !notCheaper(ESCALATION.model, MODEL)) {
  console.warn(JSON.stringify({ evt: "legal_escalation_ignored", model: ESCALATION.model, base: MODEL, why: "not known to cost at least as much as the base model" }));
}

export const MAX_TOKENS = 12000;

const COURT = /\b(court|judg(e)?ments?|rulings?|cassation|appeals?|lawsuits?|sue|suing|case law|precedents?|litigation)\b|محكم|حكم|أحكام|قرار قضائي|تمييز|استئناف|دعوى|قضية|قضايا|اجتهاد/i;
// Criminal matters, deadlines, inheritance and evictions: where a wrong or
// thin answer costs the most.
const URGENT = /\b(criminal|arrest(ed)?|detain(ed)?|detention|police|prison|deadline|time limit|statute of limitations|inheritance|estate|evict(ion)?)\b|جزائي|جنائي|توقيف|موقوف|الشرطة|سجن|حبس|مهلة|مدة الطعن|تقادم|ميراث|تركة|إخلاء/i;

export type LegalRoute = {
  model: string;
  effort: Effort;
  route: "standard" | "complex" | "escalated";
  reasons: string[];
  maxTokens: number;
  research: { searchesPerTurn: number; fetchesPerTurn: number };
};

/**
 * Which model, effort and research budget answer this question: a fixed test
 * on the question itself, not another model's guess. `escalation` is for
 * tests; the server uses ESCALATION from the environment.
 */
export function routeLegal(o: { message: string; hasDocuments: boolean }, escalation: Escalation = ESCALATION): LegalRoute {
  const reasons: string[] = [];
  if (o.hasDocuments) reasons.push("document");
  if (COURT.test(o.message)) reasons.push("court");
  if (URGENT.test(o.message)) reasons.push("urgent");
  if (o.message.length > 700) reasons.push("long");
  if (!reasons.length) {
    return { model: MODEL, effort: EFFORT, route: "standard", reasons, maxTokens: MAX_TOKENS, research: { searchesPerTurn: TURN.webSearchesPerTurn, fetchesPerTurn: TURN.webFetchesPerTurn } };
  }
  const research = { searchesPerTurn: TURN.webSearchesPerTurn + 2, fetchesPerTurn: TURN.webFetchesPerTurn + 2 };
  const escalate =
    !!escalation.model &&
    notCheaper(escalation.model, MODEL) &&
    (!escalation.triggers.length || reasons.some(r => escalation.triggers.includes(r)));
  return escalate
    ? { model: escalation.model, effort: escalation.effort, route: "escalated", reasons, maxTokens: 16000, research }
    : { model: MODEL, effort: COMPLEX_EFFORT, route: "complex", reasons, maxTokens: 16000, research };
}

/** One answer: how many model calls, searches and page reads, and how long. */
export const TURN = {
  maxModelCalls: 6,
  webSearchesPerCall: 4,
  webFetchesPerCall: 4,
  webSearchesPerTurn: 6,
  webFetchesPerTurn: 5,
  outputBudget: 20000,
  // Vercel stops the function at 60s. Past softMs no new research starts;
  // at hardMs whatever is in flight is cut and the answer ends as partial.
  softMs: 38_000,
  hardMs: 54_000,
  // Estimated cost of one answer, in US dollars, past which the assistant is
  // told to stop researching and answer.
  maxCostUsd: numberFromEnv("LEGAL_MAX_TURN_USD", 0.8, 0.05, 10),
};

const envInt = (name: string, fallback: number, min: number, max: number) => {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v >= min && v <= max ? Math.round(v) : fallback;
};

/** Allowances. Signed in only: there is no anonymous use of this feature. */
export const LIMITS = {
  perMinute: envInt("LEGAL_PER_MINUTE", 4, 1, 60),
  perDay: envInt("LEGAL_PER_DAY", 30, 1, 1000),
  perDayTotal: envInt("LEGAL_PER_DAY_TOTAL", 300, 1, 100000),
  uploadsPerMinute: envInt("LEGAL_UPLOADS_PER_MINUTE", 4, 1, 60),
};

export const INPUT = {
  maxMessageChars: 4000,
  // Earlier exchanges sent back with each question: the newest ones, up to
  // this many and this much text.
  maxTurnsKept: 12,
  maxHistoryChars: 60_000,
  maxConversations: 200,
};

/**
 * Documents. 4 MB keeps an upload inside Vercel's 4.5 MB request limit. The
 * token caps are what the model is actually charged for reading them; they
 * are counted with the API before a document is accepted.
 */
export const DOCS = {
  maxBytes: 4_000_000,
  maxPages: 30,
  maxTokensPerDoc: 90_000,
  maxTokensAll: 140_000,
  maxPerConversation: 4,
  maxTextChars: 250_000,
};

/** How long things are kept. Enforced by triggers in 0021_legal_ai.sql. */
export const RETENTION = { conversationDays: 90, documentDays: 30 };

/**
 * Where the assistant may search and read. Official: Jordanian government
 * and judiciary sites, checked to be live and to be what they say they are
 * (Legislation and Opinion Bureau, Ministry of Justice, Judicial Council,
 * Constitutional Court, Prime Ministry (Official Gazette), Senate, the
 * e-government portal, and the departments and regulators whose rules
 * people ask about). Secondary: the Bar Association and established news
 * outlets, which report new laws and amendments but are never the law
 * itself. Extend with LEGAL_OFFICIAL_DOMAINS / LEGAL_SECONDARY_DOMAINS
 * (comma-separated hosts).
 */
const extra = (name: string) =>
  (process.env[name] || "")
    .split(",")
    .map(s => s.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "").replace(/^www\./, ""))
    .filter(s => /^[a-z0-9.-]+\.[a-z]{2,}$/.test(s));

export const OFFICIAL_DOMAINS = [
  ...new Set([
    "lob.gov.jo",
    "moj.gov.jo",
    "jc.jo",
    "cco.gov.jo",
    "pm.gov.jo",
    "senate.jo",
    "jordan.gov.jo",
    "dls.gov.jo",
    "mpwh.gov.jo",
    "mola.gov.jo",
    "ammancity.gov.jo",
    "mit.gov.jo",
    "ccd.gov.jo",
    "mol.gov.jo",
    "ssc.gov.jo",
    "istd.gov.jo",
    "cbj.gov.jo",
    "jsc.gov.jo",
    "moi.gov.jo",
    "customs.gov.jo",
    ...extra("LEGAL_OFFICIAL_DOMAINS"),
  ]),
];

export const SECONDARY_DOMAINS = [
  ...new Set([
    "jba.org.jo",
    "petra.gov.jo",
    "jordantimes.com",
    "alrai.com",
    "alghad.com",
    "addustour.com",
    "ammonnews.net",
    "royanews.tv",
    "almamlakatv.com",
    ...extra("LEGAL_SECONDARY_DOMAINS"),
  ]),
].filter(d => !OFFICIAL_DOMAINS.includes(d));

export const WEB_DOMAINS = [...OFFICIAL_DOMAINS, ...SECONDARY_DOMAINS];

const within = (host: string, list: string[]) => {
  const h = host.toLowerCase().replace(/^www\./, "");
  return list.some(d => h === d || h.endsWith(`.${d}`));
};

/** Which kind of source a web page is, by its host. null: not one we read. */
export function tierOfHost(host: string): "official" | "secondary" | null {
  if (within(host, OFFICIAL_DOMAINS)) return "official";
  if (within(host, SECONDARY_DOMAINS)) return "secondary";
  return null;
}

/**
 * Who may ask. Until a licensed Jordanian lawyer has reviewed the assistant
 * (LEGAL-AI.md, "Before launch"), only the reviewers listed in
 * LEGAL_REVIEWERS can use it; LEGAL_ACCESS=public opens it to every
 * signed-in account.
 */
export const ACCESS: "public" | "reviewers" = process.env.LEGAL_ACCESS === "public" ? "public" : "reviewers";

export const REVIEWERS = (process.env.LEGAL_REVIEWERS || "")
  .split(",")
  .map(s => s.trim().toLowerCase())
  .filter(s => s.includes("@"));

export function isReviewer(email: string | null | undefined): boolean {
  return !!email && REVIEWERS.includes(email.toLowerCase());
}

/** What is missing for the feature to run at all. Empty when it can. */
export function missingConfig(): string[] {
  const missing: string[] = [];
  if (!process.env.ANTHROPIC_API_KEY) missing.push("ANTHROPIC_API_KEY");
  if (!process.env.LEGAL_DATA_KEY) missing.push("LEGAL_DATA_KEY");
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL) missing.push("NEXT_PUBLIC_SUPABASE_URL");
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  return missing;
}

/** Optional: embeddings and reranking. Without a key, retrieval is full text and exact citation. */
export const VOYAGE = {
  key: process.env.VOYAGE_API_KEY || "",
  embedModel: process.env.LEGAL_EMBED_MODEL || "voyage-3.5",
  rerankModel: process.env.LEGAL_RERANK_MODEL || "rerank-2.5",
  dimensions: 1024,
};

export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL || "https://www.akarat.ai").replace(/\/$/, "");
