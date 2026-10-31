/**
 * Reading a source file for the legal library (scripts/legal-ingest.mts).
 *
 * One file per source: a header of "key: value" lines between two "---"
 * lines, then the text. Legislation is split into its articles at lines
 * that begin "المادة" / "مادة" / "Article" and a number; chapter lines
 * ("الفصل", "الباب", "Chapter", "Part") become the heading of the articles
 * that follow. A judgment's text is kept in paragraphs. Nothing here fetches
 * anything: the text is what the team prepared from an official or licensed
 * source, and the header says which, who checked it, and when.
 *
 * The header (data/legal/README.md has the full list):
 *   slug, kind, title_ar, url, publisher, license        always
 *   number, year                                         legislation
 *   court, case_number, year, decision_date              judgments
 *   status, effective_date, repealed_date, repealed_by,
 *   amendments, gazette_ref, title_en, issue, holding,
 *   public_access                                        when known
 *   verification, verified_by, last_verified             once checked
 *
 * Inside the text, a line "[repealed]" or "[amended: by Law No. 22 of 2011]"
 * right after an article's first line marks that article.
 */
import { SOURCE_KINDS, type SourceKind, type Status } from "./library.ts";

export type SourceRow = {
  slug: string;
  kind: SourceKind;
  title_ar: string;
  title_en: string | null;
  number: string | null;
  year: number | null;
  court: string | null;
  case_number: string | null;
  decision_date: string | null;
  issue: string | null;
  holding: string | null;
  status: Status;
  effective_date: string | null;
  repealed_date: string | null;
  repealed_by: string | null;
  amendments: { law?: string; date?: string; gazette?: string; note?: string }[];
  gazette_ref: string | null;
  url: string;
  publisher: string;
  public_access: boolean;
  license: string;
  verification: "verified" | "unverified";
  verified_by: string | null;
  last_verified: string | null;
};

export type PassageRow = {
  ord: number;
  article: string | null;
  article_no: number | null;
  heading: string | null;
  body: string;
  status: Status | null;
  note: string | null;
};

export type Parsed = { source: SourceRow; passages: PassageRow[]; warnings: string[] };

const latin = (s: string) =>
  s.replace(/[٠-٩]/g, d => String(d.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, d => String(d.charCodeAt(0) - 0x06f0));

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_BODY = 18000;

function header(text: string): { fields: Map<string, string>; body: string } | null {
  const raw = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  const t = raw.replace(/\r\n?/g, "\n");
  if (!t.startsWith("---\n")) return null;
  const end = t.indexOf("\n---", 4);
  if (end < 0) return null;
  const fields = new Map<string, string>();
  for (const line of t.slice(4, end).split("\n")) {
    const m = /^([a-z_]+)\s*:\s*(.*)$/.exec(line.trim());
    if (m) fields.set(m[1], m[2].trim().replace(/^"(.*)"$/, "$1"));
  }
  return { fields, body: t.slice(t.indexOf("\n", end + 1) + 1) };
}

function amendments(v: string | undefined): SourceRow["amendments"] {
  if (!v) return [];
  // JSON, or "law | date | gazette; law | date | gazette".
  try {
    const j = JSON.parse(v);
    if (Array.isArray(j)) return j.filter(x => x && typeof x === "object").slice(0, 50);
  } catch {
    /* the short form */
  }
  return v
    .split(";")
    .map(part => part.split("|").map(x => x.trim()))
    .filter(p => p[0])
    .map(([law, date, gazette]) => ({ law, ...(date ? { date } : {}), ...(gazette ? { gazette } : {}) }));
}

const ARTICLE = /^\s*(?:المادة|مادة|Article)\s*\(?\s*([0-9٠-٩۰-۹]{1,5})\s*\)?\s*(مكرر[ةه]?|bis)?\s*[:：.\-–—]?\s*(.*)$/i;
// A chapter line names its place: "الفصل الأول", "الباب (2)", "Chapter 3".
// "الفصل في النزاع" (adjudicating the dispute) is text, not a chapter.
const CHAPTER = /^\s*(?:(?:الفصل|الباب|القسم)\s+(?:ال[ء-ي]{2,}|\(?[0-9٠-٩]+\)?)|(?:Chapter|Part)\s+[0-9IVXLC]+\b)/i;
const MARK = /^\s*\[(repealed|amended)(?::\s*(.+?))?\]\s*$/i;

/** One file in, the rows for it out, or every reason it cannot go in. */
export function parseSourceFile(text: string): Parsed | { errors: string[] } {
  const h = header(text);
  if (!h) return { errors: ["The file must start with a header between two lines of ---."] };
  const f = h.fields;
  const errors: string[] = [];
  const warnings: string[] = [];
  const get = (k: string) => (f.get(k) || "").trim() || null;

  const kind = get("kind") as SourceKind | null;
  if (!kind || !SOURCE_KINDS.includes(kind)) errors.push(`kind must be one of: ${SOURCE_KINDS.join(", ")}`);
  const slug = get("slug");
  if (!slug || !/^[a-z0-9][a-z0-9-]{1,80}$/.test(slug)) errors.push("slug: lower-case letters, digits and hyphens, 2 to 81 characters");
  const title = get("title_ar");
  if (!title || title.length < 2) errors.push("title_ar is required: the official Arabic title");
  const url = get("url");
  if (!url || !/^https:\/\/[^\s]+$/.test(url)) errors.push("url is required and must be https: the permanent link to the source");
  const publisher = get("publisher");
  if (!publisher) errors.push("publisher is required (for example ديوان التشريع والرأي)");
  const license = get("license");
  if (!license) errors.push("license is required: \"official public text\", or the licence or permission the text is held under");

  const yearRaw = get("year");
  const year = yearRaw ? Number(latin(yearRaw)) : null;
  if (yearRaw && (!Number.isInteger(year) || year! < 1900 || year! > 2100)) errors.push("year must be a four-digit year");
  const number = get("number") ? latin(get("number")!) : null;

  for (const k of ["decision_date", "effective_date", "repealed_date", "last_verified"]) {
    const v = get(k);
    if (v && !DATE.test(v)) errors.push(`${k} must be YYYY-MM-DD`);
  }

  if (kind === "judgment") {
    if (!get("court")) errors.push("a judgment needs court");
    if (!get("case_number")) errors.push("a judgment needs case_number");
    if (!year) errors.push("a judgment needs year");
  } else if (kind && kind !== "commentary" && (!number || !year)) {
    warnings.push("no number and year: exact citation lookups will not find this source, only searches");
  }

  const status = (get("status") || "unknown") as Status;
  if (!["in_force", "amended", "repealed", "unknown"].includes(status)) errors.push("status must be in_force, amended, repealed or unknown");
  const verification = get("verification") === "verified" ? "verified" : "unverified";
  if (verification === "verified" && (!get("verified_by") || !get("last_verified"))) {
    errors.push("verified sources need verified_by (who checked it against the official text) and last_verified (when)");
  }
  if (verification === "unverified") warnings.push("unverified: it is stored but never searched until a reviewer marks it verified");

  const caseNumber = get("case_number");
  const source: SourceRow = {
    slug: slug ?? "",
    kind: (kind ?? "law") as SourceKind,
    title_ar: title ?? "",
    title_en: get("title_en"),
    number,
    year,
    court: get("court"),
    case_number: caseNumber ? latin(caseNumber).replace(/\s/g, "").replace(/\/\d{4}$/, "") : null,
    decision_date: get("decision_date"),
    issue: get("issue"),
    holding: get("holding"),
    status,
    effective_date: get("effective_date"),
    repealed_date: get("repealed_date"),
    repealed_by: get("repealed_by"),
    amendments: amendments(f.get("amendments")),
    gazette_ref: get("gazette_ref"),
    url: url ?? "",
    publisher: publisher ?? "",
    public_access: get("public_access") !== "false",
    license: license ?? "",
    verification,
    verified_by: get("verified_by"),
    last_verified: get("last_verified"),
  };

  const passages: PassageRow[] = [];
  const push = (p: Omit<PassageRow, "ord">) => {
    const body = p.body.replace(/\n{3,}/g, "\n\n").trim();
    if (!body) return;
    // Over-long passages are cut at paragraph breaks, keeping their article.
    let rest = body;
    while (rest.length > MAX_BODY) {
      const cut = rest.lastIndexOf("\n", MAX_BODY) > MAX_BODY / 2 ? rest.lastIndexOf("\n", MAX_BODY) : MAX_BODY;
      passages.push({ ...p, ord: passages.length, body: rest.slice(0, cut).trim() });
      rest = rest.slice(cut).trim();
    }
    passages.push({ ...p, ord: passages.length, body: rest });
  };

  const lines = h.body.replace(/\r\n?/g, "\n").split("\n");
  if (kind === "judgment" || kind === "commentary") {
    let para: string[] = [];
    const flush = () => {
      if (para.length) push({ article: null, article_no: null, heading: null, body: para.join("\n"), status: null, note: null });
      para = [];
    };
    for (const line of lines) {
      if (!line.trim()) flush();
      else para.push(line);
    }
    flush();
  } else {
    let heading: string | null = null;
    let cur: Omit<PassageRow, "ord"> | null = null;
    let preamble: string[] = [];
    let justStarted = false;
    const labels = new Set<string>();
    for (const line of lines) {
      const a = ARTICLE.exec(line);
      if (a) {
        if (cur) push(cur);
        else if (preamble.join("").trim()) push({ article: null, article_no: null, heading: null, body: preamble.join("\n"), status: null, note: null });
        const no = Number(latin(a[1]));
        const label = `المادة ${no}${a[2] ? ` ${a[2]}` : ""}`;
        if (labels.has(label)) warnings.push(`${label} appears more than once`);
        labels.add(label);
        cur = {
          article: label,
          article_no: no,
          heading,
          body: a[3] ? a[3] : "",
          status: null,
          note: null,
        };
        justStarted = true;
        continue;
      }
      const mark = MARK.exec(line);
      if (cur && mark && justStarted) {
        cur.status = mark[1].toLowerCase() === "repealed" ? "repealed" : "amended";
        cur.note = mark[2] ?? null;
        continue;
      }
      justStarted = false;
      if (CHAPTER.test(line)) {
        heading = line.trim().slice(0, 400);
        continue;
      }
      if (cur) cur.body += (cur.body ? "\n" : "") + line;
      else preamble.push(line);
    }
    if (cur) push(cur);
    else if (preamble.join("").trim()) push({ article: null, article_no: null, heading: null, body: preamble.join("\n"), status: null, note: null });
    if (!labels.size && kind !== "official_guidance") warnings.push("no articles found: check the article lines begin with المادة, مادة or Article and a number");
  }
  if (!passages.length) errors.push("the file has no text after its header");

  return errors.length ? { errors } : { source, passages, warnings };
}
