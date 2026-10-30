/**
 * Akarat.ai listings, as the advisor's tools read them.
 *
 * Every read goes through the caller's own Supabase client: the publishable
 * key, plus the visitor's access token when they are signed in. Row Level
 * Security therefore decides what exists, exactly as on the website: active
 * listings, closed ones by id, and nothing unpublished, rejected or private.
 * No service-role key is involved anywhere in this file.
 *
 * What leaves this file is built field by field. A database row is never
 * passed through whole, so the model and the browser only ever see the
 * columns named below: no owner id, contact details, address or coordinates.
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import { unpackPayload, type Payload } from "../listing-server.ts";
import { AMENITIES, CITIES, NEIGHBORHOODS, TYPES } from "../reference.ts";
import { SITE_URL } from "./config.ts";

export type Deal = "sale" | "rent" | "daily";
export type Lang = "en" | "ar";

export const TYPE_IDS = TYPES.map(t => t.id);
export const CITY_IDS = CITIES.map(c => c.id);
export const AREA_IDS = NEIGHBORHOODS.map(n => n.id);
export const AMENITY_IDS = AMENITIES.map(a => a.id);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isListingId = (v: unknown): v is string => typeof v === "string" && UUID.test(v);

type Row = {
  id: string;
  status: string;
  deal: Deal;
  property_type: string;
  city_id: string | null;
  neighborhood_id: string | null;
  price_jod: number;
  bedrooms: number | null;
  bathrooms: number | null;
  area_sqm: number | null;
  land_sqm: number | null;
  year_built: number | null;
  title_en: string | null;
  title_ar: string | null;
  verified: boolean | null;
  created_at: string;
  updated_at: string | null;
  published_at: string | null;
  payload_gz: string | null;
  max_guests?: number | null;
  min_nights?: number | null;
};

/** A row with its payload unpacked once, and the derived facts every tool uses. */
export type Listing = {
  id: string;
  status: string;
  deal: Deal;
  type: string;
  cityId: string | null;
  areaId: string | null;
  price: number;
  beds: number | null;
  baths: number | null;
  size: number | null;
  land: number | null;
  yearBuilt: number | null;
  titleEn: string;
  titleAr: string;
  verified: boolean;
  amenities: string[];
  photos: number;
  image: string | null;
  descriptionEn: string;
  descriptionAr: string;
  listedDays: number;
  maxGuests: number | null;
  minNights: number | null;
};

const SUPABASE_HOST = (() => {
  try {
    return new URL(process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").hostname;
  } catch {
    return "";
  }
})();

// A cover photo is only ever one of our own storage objects. An owner who
// wrote some other URL into their payload does not get it loaded in every
// visitor's browser from the chat.
function storageImage(p: Payload): string | null {
  for (const m of p.images ?? []) {
    if (!m || typeof m.url !== "string" || m.type === "video") continue;
    if (/\.(mp4|webm|mov|m4v)(\?|#|$)/i.test(m.url)) continue;
    try {
      const u = new URL(m.url);
      if (u.protocol === "https:" && (u.hostname === SUPABASE_HOST || u.hostname.endsWith(".supabase.co"))) return u.toString();
    } catch {
      /* not a URL */
    }
  }
  return null;
}

const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);

function toListing(r: Row, now: number): Listing {
  const p = unpackPayload(r.payload_gz);
  const stamp = r.updated_at || r.published_at || r.created_at;
  const amen = Array.isArray(p.amenities) ? p.amenities.filter(a => AMENITY_IDS.includes(a)) : [];
  return {
    id: r.id,
    status: r.status,
    deal: r.deal,
    type: r.property_type,
    cityId: r.city_id,
    areaId: r.neighborhood_id,
    price: Number(r.price_jod) || 0,
    beds: num(r.bedrooms),
    baths: num(r.bathrooms),
    size: num(r.area_sqm),
    land: num(r.land_sqm),
    yearBuilt: num(r.year_built),
    titleEn: (r.title_en || r.title_ar || "").trim(),
    titleAr: (r.title_ar || r.title_en || "").trim(),
    verified: !!r.verified,
    amenities: amen,
    photos: (p.images ?? []).filter(m => m && m.url).length,
    image: storageImage(p),
    descriptionEn: (p.description_en ?? "").trim(),
    descriptionAr: (p.description_ar ?? "").trim(),
    listedDays: stamp ? Math.max(0, Math.floor((now - new Date(stamp).getTime()) / 86_400_000)) : 0,
    maxGuests: num(r.max_guests),
    minNights: num(r.min_nights),
  };
}

const nameOf = (list: { id: string; en: string; ar: string }[], id: string | null) => {
  const hit = id ? list.find(x => x.id === id) : undefined;
  return hit ? { en: hit.en, ar: hit.ar } : null;
};
export const cityName = (id: string | null) => nameOf(CITIES, id);
export const areaName = (id: string | null) => nameOf(NEIGHBORHOODS, id);
export const typeName = (id: string | null) => nameOf(TYPES, id);
export const amenityName = (id: string) => nameOf(AMENITIES, id);
export const cityOfArea = (id: string) => NEIGHBORHOODS.find(n => n.id === id)?.city ?? null;

export function locationLine(l: Pick<Listing, "cityId" | "areaId">, lang: Lang): string {
  const a = areaName(l.areaId);
  const c = cityName(l.cityId);
  return [a?.[lang], c?.[lang]].filter(Boolean).join(lang === "ar" ? "، " : ", ") || (lang === "ar" ? "الأردن" : "Jordan");
}

export const listingUrl = (id: string, lang: Lang) => `${SITE_URL}/${lang}/property/${id}`;

/* ── Reads ──────────────────────────────────────────────────────────────
   Thin wrappers over PostgREST. Each throws ListingsUnavailable on a
   transport or schema failure so a tool can say "search is down" instead of
   "nothing matched", which would be a false answer. */
export class ListingsUnavailable extends Error {}

// A database that has not run 0019 yet has no 'daily' deal value; asking for
// it fails on the enum rather than returning nothing. That is "no daily
// rentals here", not an outage.
const NOT_MIGRATED = new Set(["22P02", "42703", "PGRST204"]);

export type Query = {
  deal: Deal | "any";
  types: string[];
  cityId: string | null;
  priceMin: number | null;
  priceMax: number | null;
  bedsMin: number | null;
};

export interface ListingsDb {
  find(q: Query, limit: number): Promise<Listing[]>;
  byIds(ids: string[]): Promise<Listing[]>;
  prices(q: { deal: Deal; type: string | null; cityId: string | null; areaId: string | null }): Promise<
    { price: number; size: number | null }[]
  >;
}

export function supabaseListings(sb: SupabaseClient, now = () => Date.now()): ListingsDb {
  return {
    async find(q, limit) {
      let req = sb.from("properties").select("*").eq("status", "active");
      // A daily rental is priced per night and has its own page: it only
      // comes back when someone asks for one.
      req = q.deal === "any" ? req.in("deal", ["sale", "rent"]) : req.eq("deal", q.deal);
      if (q.types.length) req = req.in("property_type", q.types);
      if (q.cityId) req = req.eq("city_id", q.cityId);
      if (q.priceMax != null) req = req.lte("price_jod", q.priceMax);
      if (q.priceMin != null) req = req.gte("price_jod", q.priceMin);
      if (q.bedsMin != null) req = req.gte("bedrooms", q.bedsMin);
      const { data, error } = await req.order("created_at", { ascending: false }).limit(limit);
      if (error) {
        if (q.deal === "daily" && NOT_MIGRATED.has(error.code ?? "")) return [];
        throw new ListingsUnavailable(error.message);
      }
      const t = now();
      return (data as Row[]).map(r => toListing(r, t));
    },
    async byIds(ids) {
      const clean = ids.filter(isListingId).slice(0, 24);
      if (!clean.length) return [];
      // Closed listings are readable by id (0011_sold_visible.sql) so the
      // advisor can say a listing it showed earlier has since sold.
      const { data, error } = await sb
        .from("properties")
        .select("*")
        .in("id", clean)
        .in("status", ["active", "sold", "rented"]);
      if (error) throw new ListingsUnavailable(error.message);
      const t = now();
      return (data as Row[]).map(r => toListing(r, t));
    },
    async prices(q) {
      let req = sb.from("properties").select("price_jod,area_sqm").eq("status", "active").eq("deal", q.deal);
      if (q.type) req = req.eq("property_type", q.type);
      if (q.areaId) req = req.eq("neighborhood_id", q.areaId);
      else if (q.cityId) req = req.eq("city_id", q.cityId);
      const { data, error } = await req.limit(2000);
      if (error) {
        if (q.deal === "daily" && NOT_MIGRATED.has(error.code ?? "")) return [];
        throw new ListingsUnavailable(error.message);
      }
      return (data as { price_jod: number; area_sqm: number | null }[]).map(r => ({
        price: Number(r.price_jod) || 0,
        size: num(r.area_sqm),
      }));
    },
  };
}

/* ── Matching ───────────────────────────────────────────────────────────
   The database narrows by the indexed columns with some slack; the exact
   requirements are applied here, so a listing that misses one of them comes
   back as a near match that says what it misses, instead of disappearing. */
export type Criteria = {
  deal: Deal | "any";
  types: string[];
  cityId: string | null;
  areaIds: string[];
  budgetMin: number | null;
  budgetMax: number | null;
  bedsMin: number | null;
  bathsMin: number | null;
  sizeMin: number | null;
  amenities: string[];
  sort: "best_match" | "price_low" | "price_high" | "newest" | "largest";
};

export type Match = { listing: Listing; differences: string[] };

const pct = (a: number, b: number) => Math.round((a / b - 1) * 100);

export function differences(l: Listing, c: Criteria): string[] {
  const out: string[] = [];
  if (c.deal !== "any" && l.deal !== c.deal) out.push(`listed for ${l.deal}, not ${c.deal}`);
  if (c.types.length && !c.types.includes(l.type)) out.push(`a ${l.type}, not ${c.types.join(" or ")}`);
  if (c.areaIds.length && (!l.areaId || !c.areaIds.includes(l.areaId))) {
    const where = areaName(l.areaId)?.en ?? cityName(l.cityId)?.en ?? "an unstated area";
    out.push(`in ${where}, not ${c.areaIds.map(a => areaName(a)?.en ?? a).join(" or ")}`);
  } else if (!c.areaIds.length && c.cityId && l.cityId !== c.cityId) {
    out.push(`in ${cityName(l.cityId)?.en ?? "another city"}, not ${cityName(c.cityId)?.en ?? c.cityId}`);
  }
  if (c.budgetMax != null && l.price > c.budgetMax) out.push(`${pct(l.price, c.budgetMax)}% over the maximum budget`);
  if (c.budgetMin != null && l.price < c.budgetMin) out.push(`${-pct(l.price, c.budgetMin)}% below the minimum budget`);
  if (c.bedsMin != null) {
    if (l.beds == null) out.push("bedrooms not stated");
    else if (l.beds < c.bedsMin) out.push(`${l.beds} bedrooms, not ${c.bedsMin}+`);
  }
  if (c.bathsMin != null) {
    if (l.baths == null) out.push("bathrooms not stated");
    else if (l.baths < c.bathsMin) out.push(`${l.baths} bathrooms, not ${c.bathsMin}+`);
  }
  if (c.sizeMin != null) {
    if (l.size == null) out.push("size not stated");
    else if (l.size < c.sizeMin) out.push(`${l.size} m², under ${c.sizeMin} m²`);
  }
  const missing = c.amenities.filter(a => !l.amenities.includes(a));
  if (missing.length) out.push(`no ${missing.map(a => amenityName(a)?.en.toLowerCase() ?? a).join(", ")} listed`);
  return out;
}

// Exact matches are ordered by how much can be trusted and how fresh they are;
// price is a tiebreak toward the budget, never a reason to rank above that.
function quality(l: Listing, c: Criteria): number {
  let s = 0;
  if (l.verified) s += 3;
  s += l.listedDays <= 7 ? 3 : l.listedDays <= 30 ? 2 : l.listedDays <= 90 ? 1 : 0;
  if (l.photos > 0) s += 1;
  if (c.budgetMax != null && l.price <= c.budgetMax) s += 1;
  return s;
}

export function rank(rows: Listing[], c: Criteria): { exact: Listing[]; near: Match[] } {
  const exact: Listing[] = [];
  const near: Match[] = [];
  for (const l of rows) {
    const d = differences(l, c);
    if (!d.length) exact.push(l);
    else near.push({ listing: l, differences: d });
  }
  const by: Record<Criteria["sort"], (a: Listing, b: Listing) => number> = {
    best_match: (a, b) => quality(b, c) - quality(a, c) || a.listedDays - b.listedDays,
    price_low: (a, b) => a.price - b.price,
    price_high: (a, b) => b.price - a.price,
    newest: (a, b) => a.listedDays - b.listedDays,
    largest: (a, b) => (b.size ?? 0) - (a.size ?? 0),
  };
  exact.sort(by[c.sort]);
  // Fewest compromises first, then the same order as the exact matches.
  near.sort((a, b) => a.differences.length - b.differences.length || by[c.sort](a.listing, b.listing));
  return { exact, near };
}

/**
 * The slack the database query gets around each requirement, so near matches
 * exist to be found. A quarter over budget, one bedroom short, and the whole
 * city when particular neighbourhoods were asked for.
 */
export function looseQuery(c: Criteria): Query {
  const cityId = c.cityId ?? (c.areaIds.length ? cityOfArea(c.areaIds[0]) : null);
  return {
    deal: c.deal,
    types: c.types,
    cityId,
    priceMax: c.budgetMax != null ? Math.round(c.budgetMax * 1.25) : null,
    priceMin: c.budgetMin != null ? Math.floor(c.budgetMin * 0.8) : null,
    bedsMin: c.bedsMin != null ? Math.max(0, c.bedsMin - 1) : null,
  };
}

/* ── What the model reads ───────────────────────────────────────────────
   Compact, and explicit about which text is the owner's. */
export function forModel(l: Listing) {
  const loc = { en: locationLine(l, "en"), ar: locationLine(l, "ar") };
  return {
    id: l.id,
    title_en: l.titleEn.slice(0, 160),
    title_ar: l.titleAr.slice(0, 160),
    deal: l.deal,
    price_jod: l.price,
    price_basis: l.deal === "rent" ? "per month" : l.deal === "daily" ? "per night" : "total",
    type: l.type,
    location_en: loc.en,
    location_ar: loc.ar,
    city_id: l.cityId,
    area_id: l.areaId,
    bedrooms: l.beds,
    bathrooms: l.baths,
    size_sqm: l.size,
    land_sqm: l.land,
    price_per_sqm: l.size && l.deal === "sale" ? Math.round(l.price / l.size) : null,
    amenities: l.amenities,
    verified_by_akarat: l.verified,
    photos: l.photos,
    listed_days_ago: l.listedDays,
    ...(l.deal === "daily" ? { max_guests: l.maxGuests, min_nights: l.minNights } : {}),
    ...(l.status !== "active" ? { status: l.status } : {}),
  };
}

export function detailForModel(l: Listing) {
  return {
    ...forModel(l),
    status: l.status,
    year_built: l.yearBuilt,
    // Owner-written. Truncated: a listing is not a place to hide a novel.
    owner_description_en: l.descriptionEn.slice(0, 1500),
    owner_description_ar: l.descriptionAr.slice(0, 1500),
  };
}

/* ── What the page shows ──────────────────────────────────────────────── */
export type AkaratCard = {
  key: string;
  kind: "akarat";
  id: string;
  url: string;
  title: { en: string; ar: string };
  deal: Deal;
  type: string;
  price: number;
  basis: "total" | "month" | "night";
  beds: number | null;
  baths: number | null;
  size: number | null;
  land: number | null;
  location: { en: string; ar: string };
  verified: boolean;
  image: string | null;
  photos: number;
  listedDays: number;
  why: string;
};

export function akaratCard(l: Listing, why: string, lang: Lang): AkaratCard {
  return {
    key: `akarat:${l.id}`,
    kind: "akarat",
    id: l.id,
    url: listingUrl(l.id, lang),
    title: { en: l.titleEn, ar: l.titleAr },
    deal: l.deal,
    type: l.type,
    price: l.price,
    basis: l.deal === "rent" ? "month" : l.deal === "daily" ? "night" : "total",
    beds: l.beds,
    baths: l.baths,
    size: l.size,
    land: l.land,
    location: { en: locationLine(l, "en"), ar: locationLine(l, "ar") },
    verified: l.verified,
    image: l.image,
    photos: l.photos,
    listedDays: l.listedDays,
    why,
  };
}

/* ── Asking-price statistics ─────────────────────────────────────────── */
const quantile = (sorted: number[], q: number) => {
  if (!sorted.length) return null;
  const pos = (sorted.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return Math.round(sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo));
};

export function priceStats(rows: { price: number; size: number | null }[]) {
  const prices = rows.map(r => r.price).filter(p => p > 0).sort((a, b) => a - b);
  const perSqm = rows
    .filter(r => r.price > 0 && r.size && r.size >= 10)
    .map(r => r.price / (r.size as number))
    .sort((a, b) => a - b);
  if (prices.length < 5) {
    return { listings: prices.length, statistics: null, note: "Fewer than 5 matching listings: too few for meaningful statistics." };
  }
  return {
    listings: prices.length,
    statistics: {
      median_jod: quantile(prices, 0.5),
      p25_jod: quantile(prices, 0.25),
      p75_jod: quantile(prices, 0.75),
      min_jod: prices[0],
      max_jod: prices[prices.length - 1],
      median_jod_per_sqm: perSqm.length >= 5 ? quantile(perSqm, 0.5) : null,
      listings_with_size: perSqm.length,
    },
    note: "Asking prices of active listings on Akarat.ai only. Not transaction prices, and not the whole market.",
  };
}
