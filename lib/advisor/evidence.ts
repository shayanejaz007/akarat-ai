/**
 * What the advisor has actually seen in this turn, and the checks that hold
 * its claims to it.
 *
 * The model is never trusted to say where something came from. A listing card
 * for an Akarat.ai id is drawn from the database row; a card for an outside
 * listing needs its exact URL to have come back from web_search or web_fetch,
 * on an approved portal, and every figure on it must appear on the page that
 * web_fetch read. Anything that fails is left off the card, not guessed at.
 */
import { PORTALS, portalFor, type Portal } from "./config.ts";

export type SeenResult = { url: string; title: string; pageAge: string | null };
export type FetchedPage = { url: string; title: string; text: string; retrievedAt: string | null };

/** Same page, however it was written: no fragment, no tracking, no trailing slash, bare host. */
export function normalizeUrl(raw: string): string | null {
  if (typeof raw !== "string" || raw.length > 2048) return null;
  let u: URL;
  try {
    u = new URL(raw.trim());
  } catch {
    return null;
  }
  if (u.protocol !== "https:" && u.protocol !== "http:") return null;
  if (u.username || u.password) return null;
  u.hash = "";
  u.hostname = u.hostname.toLowerCase().replace(/^www\./, "");
  for (const k of [...u.searchParams.keys()]) {
    if (/^(utm_|fbclid$|gclid$|ref$)/i.test(k)) u.searchParams.delete(k);
  }
  let s = `${u.hostname}${u.pathname.replace(/\/+$/, "")}${u.search}`;
  try {
    s = decodeURI(s);
  } catch {
    /* already decoded, or not decodable: compare as is */
  }
  return s;
}

export class Evidence {
  /** Search results, by normalised URL. */
  readonly results = new Map<string, SeenResult>();
  /** Pages web_fetch read, by normalised URL. */
  readonly pages = new Map<string, FetchedPage>();
  /** Pages web_fetch tried and could not read. */
  readonly failed = new Set<string>();
  /** Akarat.ai ids a tool returned this turn, or that were shown earlier. */
  readonly listingIds = new Set<string>();
  /** External listings shown in earlier turns of this conversation. */
  readonly shownExternal = new Map<string, { url: string; title: string }>();
  /** web_fetch documents in the order they entered the context, for citations. */
  readonly documents: { url: string; title: string }[] = [];

  addResult(r: SeenResult) {
    const k = normalizeUrl(r.url);
    if (k && !this.results.has(k)) this.results.set(k, r);
  }

  addPage(p: FetchedPage) {
    const k = normalizeUrl(p.url);
    if (!k) return;
    this.pages.set(k, p);
    this.failed.delete(k);
    this.documents.push({ url: p.url, title: p.title });
  }

  addFailure(url: string) {
    const k = normalizeUrl(url);
    if (k && !this.pages.has(k)) this.failed.add(k);
  }

  /** Did this exact page come back from a search or a fetch, now or in an earlier turn? */
  known(url: string): boolean {
    const k = normalizeUrl(url);
    return !!k && (this.results.has(k) || this.pages.has(k) || this.shownExternal.has(k));
  }

  page(url: string): FetchedPage | null {
    const k = normalizeUrl(url);
    return (k && this.pages.get(k)) || null;
  }

  result(url: string): SeenResult | null {
    const k = normalizeUrl(url);
    return (k && this.results.get(k)) || null;
  }

  couldNotOpen(url: string): boolean {
    const k = normalizeUrl(url);
    return !!k && this.failed.has(k);
  }
}

/* ── Reading figures off a page ─────────────────────────────────────────
   The page text is whatever the portal printed, in either script. Digits are
   folded to ASCII and separators dropped before looking for a number, and a
   number only counts when it stands alone: 150 must not be found inside
   1500 or 150000. */
const AR_DIGITS = "٠١٢٣٤٥٦٧٨٩";
const FA_DIGITS = "۰۱۲۳۴۵۶۷۸۹";

export function foldDigits(s: string): string {
  return s
    .replace(/[٠-٩]/g, d => String(AR_DIGITS.indexOf(d)))
    .replace(/[۰-۹]/g, d => String(FA_DIGITS.indexOf(d)))
    .replace(/[٬،]/g, ",")
    .replace(/٫/g, ".");
}

// Thousands separators of every kind between digit groups.
const plainNumbers = (s: string) => foldDigits(s).replace(/(\d)[,.\s  '](?=\d{3}(?!\d))/g, "$1");

function standsAlone(text: string, n: string): boolean {
  return new RegExp(`(^|[^\\d.])${n}(?![\\d]|[.,]\\d)`).test(text);
}

export function pageMentionsPrice(text: string, price: number): boolean {
  if (!Number.isFinite(price) || price <= 0) return false;
  const t = plainNumbers(text);
  if (standsAlone(t, String(Math.round(price)))) return true;
  // "150 ألف" / "150K" / "150 thousand" for 150,000.
  if (price >= 1000 && price % 1000 === 0) {
    const k = String(price / 1000);
    if (new RegExp(`(^|[^\\d.])${k}\\s*(k\\b|K\\b|thousand|ألف|الف|آلاف)`, "i").test(t)) return true;
  }
  // "1.2 million" / "1.2 مليون".
  if (price >= 100_000) {
    const m = (price / 1_000_000).toString();
    if (new RegExp(`(^|[^\\d.])${m.replace(".", "\\.")}\\s*(m\\b|M\\b|million|مليون)`, "i").test(t)) return true;
  }
  return false;
}

// \b is defined over ASCII word characters and never fires beside Arabic, so
// the Arabic units end on "not followed by another Arabic letter" instead.
const UNIT = {
  beds: "(?:bed(?:room)?s?|br\\b|غرف(?:ة)?(?:\\s*(?:ال)?نوم)?|غرفتين|غرفتان)",
  baths: "(?:bath(?:room)?s?|حمام(?:ات)?|حمامين|حمامان)",
  size: "(?:m²|m2|sqm|sq\\.?\\s*m|square\\s*met(?:er|re)s?|متر(?:\\s*مربع)?|م²|م2|م(?![\\u0600-\\u06FF]))",
};

/** "3 bedrooms", "Bedrooms: 3", "3 غرف نوم", "غرف النوم 3" all count; a stray 3 does not. */
export function pageMentionsCount(text: string, n: number, kind: keyof typeof UNIT): boolean {
  if (!Number.isFinite(n) || n < 0) return false;
  const t = plainNumbers(text);
  const v = kind === "size" ? String(Math.round(n)) : String(n);
  const unit = UNIT[kind];
  const after = new RegExp(`(^|[^\\d.])${v}\\s*[-:]?\\s*${unit}`, "i");
  const before = new RegExp(`${unit}\\s*[:\\-–]?\\s*${v}(?![\\d]|[.,]\\d)`, "i");
  return after.test(t) || before.test(t);
}

// Phrases portals print on a listing that has gone. Checked case-insensitively
// against the page text, in both languages.
const GONE = [
  /this (?:ad|listing|property) (?:is )?no longer available/i,
  /(?:ad|listing|property) (?:has been |was )?(?:removed|deleted|expired)/i,
  /this (?:ad|listing) has expired/i,
  /الإعلان غير (?:متوفر|متاح)/,
  /الاعلان غير (?:متوفر|متاح)/,
  /(?:انتهت صلاحية|تم حذف|تم إزالة) (?:هذا )?الإعلان/,
  /هذا العقار (?:لم يعد|غير) متاح/,
];

export const pageSaysGone = (text: string) => GONE.some(re => re.test(text));

export type ExternalCard = {
  key: string;
  kind: "external";
  url: string;
  source: { name: string; nameAr: string; host: string };
  title: string;
  price: number | null;
  basis: "total" | "month" | "night" | null;
  beds: number | null;
  baths: number | null;
  size: number | null;
  location: string | null;
  // True when the figures shown were each found on the page itself.
  checked: boolean;
  seen: string | null;
  why: string;
};

export type ExternalClaim = {
  url: string;
  title: string | null;
  price: number | null;
  basis: "total" | "month" | "night" | null;
  beds: number | null;
  baths: number | null;
  size: number | null;
  location: string | null;
  why: string;
};

export type Verdict = { card: ExternalCard; dropped: string[] } | { error: string };

/**
 * Turns the model's description of an outside listing into a card, keeping
 * only what the evidence supports. Returns an error the model can act on when
 * the listing cannot be shown at all.
 */
export function verifyExternal(claim: ExternalClaim, ev: Evidence): Verdict {
  const portal: Portal | null = portalFor(claim.url);
  if (!portal) {
    return { error: `${claim.url} is not on an approved listing portal (${PORTALS.map(p => p.host).join(", ")}). Only listings from those portals can be shown as cards.` };
  }
  if (!ev.known(claim.url)) {
    return { error: `${claim.url} did not appear in any web_search or web_fetch result in this conversation. Present only exact URLs returned by those tools.` };
  }
  if (ev.couldNotOpen(claim.url)) {
    return { error: `The page ${claim.url} could not be opened, so it cannot be confirmed that the listing still exists. Leave it out.` };
  }
  const page = ev.page(claim.url);
  if (page && pageSaysGone(page.text)) {
    return { error: `The page ${claim.url} says the listing is no longer available. Leave it out.` };
  }

  const dropped: string[] = [];
  const keep = <T>(value: T | null, ok: (v: T) => boolean, label: string): T | null => {
    if (value == null) return null;
    if (page && ok(value)) return value;
    dropped.push(page ? `${label} (not found on the page)` : `${label} (page not read with web_fetch)`);
    return null;
  };

  const price = keep(claim.price, p => pageMentionsPrice(page!.text, p), "price");
  const beds = keep(claim.beds, n => pageMentionsCount(page!.text, n, "beds"), "bedrooms");
  const baths = keep(claim.baths, n => pageMentionsCount(page!.text, n, "baths"), "bathrooms");
  const size = keep(claim.size, n => pageMentionsCount(page!.text, n, "size"), "size");
  const location = keep(
    claim.location?.trim() || null,
    loc => {
      const words = loc.split(/[\s,،\-]+/).filter(w => w.length >= 3);
      const hay = page!.text.toLowerCase();
      return words.length > 0 && words.some(w => hay.includes(w.toLowerCase()));
    },
    "location"
  );

  const result = ev.result(claim.url);
  const title = (claim.title?.trim() || page?.title || result?.title || portal.name).slice(0, 140);

  return {
    card: {
      key: `ext:${normalizeUrl(claim.url)}`,
      kind: "external",
      url: claim.url,
      source: { name: portal.name, nameAr: portal.nameAr, host: portal.host },
      title,
      price,
      basis: price != null ? claim.basis ?? "total" : null,
      beds,
      baths,
      size,
      location: location ? location.slice(0, 80) : null,
      checked: !!page,
      seen: page?.retrievedAt ?? result?.pageAge ?? null,
      why: claim.why,
    },
    dropped,
  };
}
