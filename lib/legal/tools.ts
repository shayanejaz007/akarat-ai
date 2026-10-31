/**
 * Ask a Lawyer's tools: their definitions as the model sees them, and what
 * runs when it calls one.
 *
 * Read-only and parameterised, like the advisor's: the model supplies search
 * words, citation parts and short display text; it never writes a query that
 * runs, a URL our server fetches, or anything stored. Definitions are strict
 * and every input is validated again here. Library results go back as
 * search_result blocks, so what the model cites from them comes back as
 * citations the server can tie to a verified passage.
 */
import type {
  BetaSearchResultBlockParam,
  BetaTextBlockParam,
  BetaTool,
  BetaToolUnion,
  BetaWebFetchTool20260209,
  BetaWebSearchTool20260209,
} from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { TURN, WEB_DOMAINS } from "./config.ts";
import { SOURCE_KINDS, lookupCitation, searchLibrary, toSearchResult, type Hit, type LibraryDb, type SourceKind } from "./library.ts";

/** What a tool sends to the page, alongside what it returns to the model. */
export type PageEvent = { t: "urgent"; level: "urgent" | "important"; text: string };

export type ToolOutcome = {
  content: string | BetaSearchResultBlockParam[] | BetaTextBlockParam[];
  isError?: boolean;
  events?: PageEvent[];
  flag?: string;
  /** Library passages this call returned, in the order of its search_result blocks. */
  hits?: Hit[];
};

export type ToolEnv = { db: LibraryDb | null };

const searchTool: BetaTool = {
  name: "search_legal_library",
  description:
    "Search the Akarat legal library: Jordanian legislation, judgments and commentary that a reviewer has verified against the official source. " +
    "Returns passages with their provenance (status, dates, amendments, Official Gazette reference, last verification). " +
    "Write the query in formal Arabic legal terms where you can (for example: إخلاء المأجور بدل الإجارة), adding the user's own words or English if useful. " +
    "kinds narrows the search (for example [\"judgment\"] for case law); null searches everything. limit is 1 to 10, null for 6.",
  strict: true,
  input_schema: {
    type: "object",
    properties: {
      query: { type: "string" },
      kinds: { anyOf: [{ type: "array", items: { type: "string", enum: [...SOURCE_KINDS] } }, { type: "null" }] },
      limit: { anyOf: [{ type: "integer" }, { type: "null" }] },
    },
    required: ["query", "kinds", "limit"],
    additionalProperties: false,
  },
};

const lookupTool: BetaTool = {
  name: "lookup_citation",
  description:
    "Retrieve an exact citation from the Akarat legal library. For legislation give law_number and year, and article for one article " +
    "(or title, part of the official Arabic title, when the number is unknown). For a judgment give case_number (for example \"1234/2019\" or \"1234\" with year) and optionally court. " +
    "Unused fields are null. Finds nothing rather than something close: use it to check a provision or case before relying on it.",
  strict: true,
  input_schema: {
    type: "object",
    properties: {
      law_number: { anyOf: [{ type: "string" }, { type: "null" }] },
      year: { anyOf: [{ type: "integer" }, { type: "null" }] },
      article: { anyOf: [{ type: "integer" }, { type: "null" }] },
      title: { anyOf: [{ type: "string" }, { type: "null" }] },
      case_number: { anyOf: [{ type: "string" }, { type: "null" }] },
      court: { anyOf: [{ type: "string" }, { type: "null" }] },
    },
    required: ["law_number", "year", "article", "title", "case_number", "court"],
    additionalProperties: false,
  },
};

const urgentTool: BetaTool = {
  name: "flag_urgent",
  description:
    "Show the user a prominent notice before your answer, when they face a deadline, an eviction, detention, a safety risk or another serious consequence. " +
    "message: one short sentence in the user's language saying what is urgent and that they should get prompt help from a licensed lawyer or the relevant authority. " +
    "level: \"urgent\" for imminent harm or a deadline within days, otherwise \"important\". Call at most once, before you write your answer.",
  strict: true,
  input_schema: {
    type: "object",
    properties: { level: { type: "string", enum: ["urgent", "important"] }, message: { type: "string" } },
    required: ["level", "message"],
    additionalProperties: false,
  },
};

// Server tools, called directly so every result comes back with its URL and
// text and can be checked. URLs come from searches and from the user, never
// from our own tool results.
const webSearch: BetaWebSearchTool20260209 = {
  type: "web_search_20260209",
  name: "web_search",
  max_uses: TURN.webSearchesPerCall,
  allowed_domains: WEB_DOMAINS,
  allowed_callers: ["direct"],
};

const webFetch = {
  type: "web_fetch_20260209",
  name: "web_fetch",
  max_uses: TURN.webFetchesPerCall,
  allowed_domains: WEB_DOMAINS,
  allowed_callers: ["direct"],
  max_content_tokens: 12000,
  citations: { enabled: true },
  url_sources: { client_tool_results: { type: "none" } },
} as BetaWebFetchTool20260209;

// Fixed order: the tools array is the front of the cached prefix.
export const TOOLS: BetaToolUnion[] = [searchTool, lookupTool, urgentTool, webSearch, webFetch];

/* ── Input validation ────────────────────────────────────────────────── */
class Invalid extends Error {}

const obj = (v: unknown): Record<string, unknown> => {
  if (!v || typeof v !== "object" || Array.isArray(v)) throw new Invalid("input must be an object");
  return v as Record<string, unknown>;
};

function intOrNull(v: unknown, name: string, min: number, max: number): number | null {
  if (v == null) return null;
  if (typeof v !== "number" || !Number.isFinite(v)) throw new Invalid(`${name} must be a number or null`);
  const n = Math.round(v);
  if (n < min || n > max) throw new Invalid(`${name} must be between ${min} and ${max}`);
  return n;
}

const latinDigits = (s: string) =>
  s.replace(/[٠-٩]/g, d => String(d.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, d => String(d.charCodeAt(0) - 0x06f0));

/** Model-written text that reaches the page or a query: plain, one line, bounded. */
export function prose(v: unknown, max: number): string {
  if (typeof v !== "string") return "";
  const s = v
    .replace(/[\u0000-\u0008\u000b-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ue000-\uf8ff]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return s.length > max ? `${s.slice(0, max - 1).trimEnd()}…` : s;
}

function textOrNull(v: unknown, name: string, max: number): string | null {
  if (v == null) return null;
  if (typeof v !== "string") throw new Invalid(`${name} must be a string or null`);
  const s = prose(v, max + 1);
  if (s.length > max) throw new Invalid(`${name} is too long`);
  return s || null;
}

/* ── Execution ───────────────────────────────────────────────────────── */
const fail = (message: string, flag?: string): ToolOutcome => ({ content: JSON.stringify({ error: message }), isError: true, flag });

const note = (text: string): BetaTextBlockParam[] => [{ type: "text", text }];

async function search(input: unknown, env: ToolEnv): Promise<ToolOutcome> {
  const i = obj(input);
  const query = prose(i.query, 400);
  if (query.length < 2) throw new Invalid("query is empty");
  let kinds: SourceKind[] | null = null;
  if (i.kinds != null) {
    if (!Array.isArray(i.kinds)) throw new Invalid("kinds must be an array or null");
    kinds = [...new Set(i.kinds.map(k => {
      if (!SOURCE_KINDS.includes(k as SourceKind)) throw new Invalid(`kinds must be among: ${SOURCE_KINDS.join(", ")}`);
      return k as SourceKind;
    }))];
  }
  const limit = intOrNull(i.limit, "limit", 1, 10) ?? 6;
  if (!env.db) return fail("The legal library is unavailable right now. Use the official websites, and say what you could not verify.", "library_unavailable");
  const hits = await searchLibrary(env.db, query, kinds, limit);
  if (hits === null) return fail("The legal library could not be searched just now. Use the official websites, and say what you could not verify.", "library_unavailable");
  if (!hits.length) {
    return {
      content: note(
        "No verified passage in the Akarat legal library matched this search. Try other formal Arabic legal terms, or read the official websites. " +
          "Do not cite anything this search did not return."
      ),
      hits: [],
    };
  }
  return { content: hits.map(toSearchResult), hits };
}

async function lookup(input: unknown, env: ToolEnv): Promise<ToolOutcome> {
  const i = obj(input);
  let lawNumber = textOrNull(i.law_number, "law_number", 12);
  if (lawNumber) {
    lawNumber = latinDigits(lawNumber).replace(/[^0-9]/g, "") || null;
    if (!lawNumber) throw new Invalid("law_number must be a number");
  }
  let year = intOrNull(i.year, "year", 1900, 2100);
  const article = intOrNull(i.article, "article", 0, 100000);
  const title = textOrNull(i.title, "title", 160);
  const court = textOrNull(i.court, "court", 80);
  let caseNumber = textOrNull(i.case_number, "case_number", 24);
  if (caseNumber) {
    const c = latinDigits(caseNumber);
    const slash = /^\s*(\d{1,6})\s*\/\s*(\d{4})\s*$/.exec(c);
    if (slash) {
      caseNumber = slash[1];
      year ??= Number(slash[2]);
    } else if (/^\s*\d{1,6}\s*$/.test(c)) {
      caseNumber = c.trim();
    } else {
      throw new Invalid("case_number must look like 1234/2019 or 1234");
    }
  }
  if (!lawNumber && !caseNumber && !(title && title.length >= 4)) {
    throw new Invalid("give law_number (with year), a title, or case_number");
  }
  if (!env.db) return fail("The legal library is unavailable right now.", "library_unavailable");
  const hits = await lookupCitation(env.db, { lawNumber, year, article, court, caseNumber, title });
  if (hits === null) return fail("The legal library could not be searched just now.", "library_unavailable");
  if (!hits.length) {
    const asked = caseNumber
      ? `case ${caseNumber}${year ? `/${year}` : ""}${court ? ` (${court})` : ""}`
      : `${title ?? `law ${lawNumber}`}${year ? ` of ${year}` : ""}${article != null ? `, article ${article}` : ""}`;
    return {
      content: note(
        `No verified source in the Akarat legal library matches ${asked}. It may exist but has not been verified here: do not cite it as verified. ` +
          "An official website may have it; otherwise say it could not be verified."
      ),
      hits: [],
    };
  }
  return { content: hits.map(toSearchResult), hits };
}

function urgent(input: unknown): ToolOutcome {
  const i = obj(input);
  const level = i.level === "urgent" || i.level === "important" ? i.level : null;
  if (!level) throw new Invalid('level must be "urgent" or "important"');
  const text = prose(i.message, 240);
  if (text.length < 4) throw new Invalid("message is empty");
  return { content: "Shown to the user above your answer.", events: [{ t: "urgent", level, text }] };
}

/** Runs one tool call. Never throws: a bad call becomes an error result the model can correct. */
export async function runTool(name: string, input: unknown, env: ToolEnv): Promise<ToolOutcome> {
  try {
    switch (name) {
      case "search_legal_library":
        return await search(input, env);
      case "lookup_citation":
        return await lookup(input, env);
      case "flag_urgent":
        return urgent(input);
      default:
        return fail(`There is no tool called ${String(name).slice(0, 60)}.`, "unknown_tool");
    }
  } catch (e) {
    if (e instanceof Invalid) return fail(e.message, "bad_tool_input");
    console.error("legal tool failed", name, e instanceof Error ? e.message : e);
    return fail("That tool failed. Continue without it, and say what you could not check.", "tool_failed");
  }
}
