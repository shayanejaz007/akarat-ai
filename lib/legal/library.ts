/**
 * The Akarat legal library: retrieval from legal_sources / legal_passages
 * (0021_legal_ai.sql) through its two functions, with the service-role key.
 *
 *   search   hybrid: Arabic full text, and meaning (pgvector) once passages
 *            have embeddings, fused by reciprocal rank in the database;
 *            then, when a Voyage key is set, reranked for relevance.
 *   lookup   exact: an article of a numbered law, or a judgment by case
 *            number and year. Nothing fuzzy.
 *
 * Only sources a reviewer marked verified are ever returned; the database
 * functions enforce it, not this file. Embeddings and reranking are optional
 * (VOYAGE_API_KEY): without them retrieval is full text and exact citation,
 * and any failure there falls back the same way rather than failing the
 * answer.
 */
import type { BetaSearchResultBlockParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { VOYAGE } from "./config.ts";

export type SourceKind =
  | "constitution"
  | "law"
  | "temporary_law"
  | "regulation"
  | "instructions"
  | "decision"
  | "judgment"
  | "official_guidance"
  | "commentary";

export const SOURCE_KINDS: readonly SourceKind[] = [
  "constitution",
  "law",
  "temporary_law",
  "regulation",
  "instructions",
  "decision",
  "judgment",
  "official_guidance",
  "commentary",
];

export type Status = "in_force" | "amended" | "repealed" | "unknown";

export type Hit = {
  passageId: number;
  sourceId: string;
  slug: string;
  kind: SourceKind;
  tier: "primary" | "secondary";
  titleAr: string;
  titleEn: string | null;
  number: string | null;
  year: number | null;
  court: string | null;
  caseNumber: string | null;
  decisionDate: string | null;
  issue: string | null;
  holding: string | null;
  status: Status;
  passageStatus: Status | null;
  effectiveDate: string | null;
  repealedDate: string | null;
  repealedBy: string | null;
  amendments: { law?: string; date?: string; gazette?: string; note?: string }[];
  gazetteRef: string | null;
  url: string;
  publisher: string;
  publicAccess: boolean;
  verifiedBy: string | null;
  lastVerified: string | null;
  article: string | null;
  articleNo: number | null;
  heading: string | null;
  body: string;
  note: string | null;
};

/** The database calls this file needs; a fake in tests, PostgREST in production. */
export type LibraryDb = {
  rpc(fn: "legal_search" | "legal_lookup", args: Record<string, unknown>): Promise<{ data: unknown; error: unknown }>;
  counts(): Promise<{ kind: string }[] | null>;
};

const str = (v: unknown): string | null => (typeof v === "string" && v.trim() ? v : null);
const int = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

function toHit(r: Record<string, unknown>): Hit | null {
  const url = str(r.url);
  const body = str(r.body);
  if (!url || !/^https:\/\//.test(url) || !body) return null;
  const kind = SOURCE_KINDS.includes(r.kind as SourceKind) ? (r.kind as SourceKind) : null;
  if (!kind) return null;
  const status = (s: unknown): Status | null =>
    s === "in_force" || s === "amended" || s === "repealed" || s === "unknown" ? s : null;
  return {
    passageId: Number(r.passage_id),
    sourceId: String(r.source_id),
    slug: String(r.slug),
    kind,
    tier: r.tier === "secondary" ? "secondary" : "primary",
    titleAr: String(r.title_ar ?? ""),
    titleEn: str(r.title_en),
    number: str(r.number),
    year: int(r.year),
    court: str(r.court),
    caseNumber: str(r.case_number),
    decisionDate: str(r.decision_date),
    issue: str(r.issue),
    holding: str(r.holding),
    status: status(r.status) ?? "unknown",
    passageStatus: status(r.passage_status),
    effectiveDate: str(r.effective_date),
    repealedDate: str(r.repealed_date),
    repealedBy: str(r.repealed_by),
    amendments: Array.isArray(r.amendments) ? (r.amendments as Hit["amendments"]).slice(0, 20) : [],
    gazetteRef: str(r.gazette_ref),
    url,
    publisher: String(r.publisher ?? ""),
    publicAccess: r.public_access !== false,
    verifiedBy: str(r.verified_by),
    lastVerified: str(r.last_verified),
    article: str(r.article),
    articleNo: int(r.article_no),
    heading: str(r.heading),
    body,
    note: str(r.note),
  };
}

function rows(data: unknown): Hit[] {
  return Array.isArray(data) ? data.map(r => toHit(r as Record<string, unknown>)).filter((h): h is Hit => !!h) : [];
}

/* ── Embeddings and reranking (optional) ─────────────────────────────── */

const VOYAGE_URL = "https://api.voyageai.com/v1";

async function voyage(path: string, body: Record<string, unknown>, timeoutMs: number): Promise<Record<string, unknown> | null> {
  if (!VOYAGE.key) return null;
  try {
    const res = await fetch(`${VOYAGE_URL}/${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${VOYAGE.key}` },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) return null;
    return (await res.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

const isVector = (v: unknown): v is number[] =>
  Array.isArray(v) && v.length === VOYAGE.dimensions && v.every(x => typeof x === "number" && Number.isFinite(x));

/** Embeddings for texts, or null. "query" for a search, "document" for passages being stored. */
export async function embed(texts: string[], inputType: "query" | "document"): Promise<number[][] | null> {
  if (!texts.length) return [];
  const j = await voyage("embeddings", { input: texts, model: VOYAGE.embedModel, input_type: inputType }, inputType === "query" ? 4000 : 60000);
  const data = Array.isArray(j?.data) ? (j!.data as { index?: number; embedding?: unknown }[]) : null;
  if (!data || data.length !== texts.length) return null;
  const out: number[][] = new Array(texts.length);
  for (const d of data) {
    if (typeof d.index !== "number" || !isVector(d.embedding)) return null;
    out[d.index] = d.embedding;
  }
  return out.every(Boolean) ? out : null;
}

async function rerank(query: string, hits: Hit[], top: number): Promise<Hit[]> {
  if (hits.length < 2) return hits;
  const j = await voyage(
    "rerank",
    { query, documents: hits.map(h => `${h.titleAr} ${h.article ?? ""}\n${h.body}`.slice(0, 4000)), model: VOYAGE.rerankModel, top_k: top },
    4000
  );
  const data = Array.isArray(j?.data) ? (j!.data as { index?: number }[]) : null;
  if (!data) return hits.slice(0, top);
  const order = data.map(d => d.index).filter((i): i is number => typeof i === "number" && i >= 0 && i < hits.length);
  return order.length ? [...new Set(order)].map(i => hits[i]) : hits.slice(0, top);
}

/* ── Retrieval ───────────────────────────────────────────────────────── */

export async function searchLibrary(db: LibraryDb, query: string, kinds: SourceKind[] | null, limit: number): Promise<Hit[] | null> {
  const vector = (await embed([query], "query"))?.[0] ?? null;
  // Fetch more than asked when there is a reranker to choose among them.
  const want = VOYAGE.key ? Math.min(limit * 3, 20) : limit;
  const { data, error } = await db.rpc("legal_search", {
    p_query: query,
    p_embedding: vector ? `[${vector.join(",")}]` : null,
    p_kinds: kinds && kinds.length ? kinds : null,
    p_limit: want,
  });
  if (error) return null;
  const hits = rows(data);
  return VOYAGE.key ? rerank(query, hits, limit) : hits.slice(0, limit);
}

export type Lookup = {
  lawNumber: string | null;
  year: number | null;
  article: number | null;
  court: string | null;
  caseNumber: string | null;
  title: string | null;
};

export async function lookupCitation(db: LibraryDb, q: Lookup): Promise<Hit[] | null> {
  const { data, error } = await db.rpc("legal_lookup", {
    p_number: q.lawNumber,
    p_year: q.year,
    p_article: q.article,
    p_court: q.court,
    p_case_number: q.caseNumber,
    p_title: q.title ? q.title.replace(/[%_]/g, " ") : null,
  });
  return error ? null : rows(data);
}

let countsCache: { at: number; value: { total: number; legislation: number; judgments: number; commentary: number } | null } | null = null;

/** How much the library holds, for the model's context. Cached for five minutes. */
export async function libraryCounts(db: LibraryDb) {
  if (countsCache && Date.now() - countsCache.at < 300_000) return countsCache.value;
  const list = await db.counts();
  const value = list
    ? {
        total: list.length,
        judgments: list.filter(r => r.kind === "judgment").length,
        commentary: list.filter(r => r.kind === "commentary").length,
        legislation: list.filter(r => r.kind !== "judgment" && r.kind !== "commentary").length,
      }
    : null;
  countsCache = { at: Date.now(), value };
  return value;
}

/** For tests. */
export function resetLibraryCache() {
  countsCache = null;
}

/* ── Presenting a hit ────────────────────────────────────────────────── */

const STATUS_EN: Record<Status, string> = { in_force: "in force", amended: "amended", repealed: "repealed", unknown: "status not recorded" };

/** How a hit is named: the citation a reader would recognise. */
export function citationTitle(h: Hit): string {
  if (h.kind === "judgment") {
    return [h.court, h.caseNumber && h.year ? `${h.caseNumber}/${h.year}` : null, h.decisionDate ? `(${h.decisionDate})` : null]
      .filter(Boolean)
      .join(" ");
  }
  const law = h.number && h.year ? `${h.titleAr} رقم ${h.number} لسنة ${h.year}` : h.titleAr;
  return h.article ? `${law} — ${h.article}` : law;
}

/**
 * A hit as the model receives it: a search result whose first block is the
 * provenance (status, dates, amendments, publication, who verified it and
 * when) and whose second is the text itself. Both can be cited.
 */
export function toSearchResult(h: Hit): BetaSearchResultBlockParam {
  const meta: string[] = [];
  meta.push(`Source: Akarat legal library, verified copy (${h.tier === "secondary" ? "secondary: commentary, not law" : "primary"}).`);
  if (h.kind === "judgment") {
    meta.push(`Judgment of ${h.court ?? "unknown court"}, case ${h.caseNumber ?? "?"}/${h.year ?? "?"}${h.decisionDate ? `, decided ${h.decisionDate}` : ""}.`);
    if (h.issue) meta.push(`Issue: ${h.issue}`);
    if (h.holding) meta.push(`Holding: ${h.holding}`);
  } else {
    const st = h.passageStatus ?? h.status;
    meta.push(`Kind: ${h.kind.replace("_", " ")}. Status of this ${h.article ? "provision" : "instrument"}: ${STATUS_EN[st]}.`);
    if (h.passageStatus && h.passageStatus !== h.status) meta.push(`The instrument as a whole is ${STATUS_EN[h.status]}.`);
    if (h.effectiveDate) meta.push(`In force from ${h.effectiveDate}.`);
    if (h.repealedDate || h.repealedBy) meta.push(`Repealed${h.repealedDate ? ` on ${h.repealedDate}` : ""}${h.repealedBy ? ` by ${h.repealedBy}` : ""}.`);
    if (h.amendments.length) {
      meta.push(
        `Amendments: ${h.amendments
          .map(a => [a.law, a.date, a.gazette].filter(Boolean).join(", "))
          .filter(Boolean)
          .join("; ")}.`
      );
    }
    if (h.note) meta.push(`Note: ${h.note}`);
  }
  if (h.gazetteRef) meta.push(`Official Gazette: ${h.gazetteRef}.`);
  meta.push(`Publisher: ${h.publisher}. Last verified ${h.lastVerified ?? "?"}${h.verifiedBy ? ` by ${h.verifiedBy}` : ""}.`);
  if (!h.publicAccess) meta.push("Held under licence: cite it, but readers cannot open the source themselves.");
  const text = [h.article, h.heading].filter(Boolean).join(" — ");
  return {
    type: "search_result",
    source: h.url,
    title: citationTitle(h).slice(0, 300),
    content: [
      { type: "text", text: meta.join(" ") },
      { type: "text", text: text ? `${text}\n${h.body}` : h.body },
    ],
    citations: { enabled: true },
  };
}
