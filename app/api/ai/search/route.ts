import { NextResponse, type NextRequest } from "next/server";
import { allow } from "@/lib/rate-limit";
import { callerIp, resolveCaller } from "@/lib/caller";

/**
 * POST /api/ai/search
 *
 * The full pipeline, server-side. The browser never holds a provider key and
 * never fetches a third-party page itself.
 *
 *   parse → resolve locations → internal search
 *         → external adapters (parallel, fault tolerant)
 *         → normalise → dedupe → rank → respond
 *
 * The deep links the UI shows today (lib/providers.js) are the honest fallback
 * for sources we have no credential for. This route is what replaces them with
 * individual listings, one source at a time, as agreements land.
 */

export const runtime = "nodejs";

type Constraints = {
  deal: "sale" | "rent" | null;
  city: string | null;
  hood: string | null;
  budgetMin: number | null;
  budgetMax: number | null;
  beds: number | null;
  baths: number | null;
  type: string | null;
  amenities: string[];
  internalOnly?: boolean;
};

export type ExternalPropertyResult = {
  externalId?: string;
  sourceName: string;
  sourceUrl: string;
  title: string;
  transactionType: "sale" | "rent";
  price?: number;
  currency?: string;
  bedrooms?: number;
  bathrooms?: number;
  areaSqm?: number;
  propertyType?: string;
  city?: string;
  neighborhood?: string;
  latitude?: number;
  longitude?: number;
  imageUrl?: string;
  publishedAt?: string;
  discoveredAt: string;
  lastCheckedAt?: string;
  availabilityStatus?: "likely_available" | "unknown" | "unavailable";
};

interface PropertySearchProvider {
  id: string;
  name: string;
  /** Confidence in the SOURCE, not in the property. */
  confidence: number;
  /** Absent credential means the adapter reports itself unavailable. */
  configured(): boolean;
  search(q: Constraints, signal: AbortSignal): Promise<ExternalPropertyResult[]>;
}

/* ── SSRF guard ──────────────────────────────────────────────────────────
   Any URL a provider hands back is untrusted. Only fetch public hosts on
   an explicit allowlist, and never follow a redirect off it.            */
const ALLOWED_HOSTS = new Set<string>([
  // "api.partner.example.jo",
]);

function assertFetchable(raw: string) {
  const u = new URL(raw);
  if (u.protocol !== "https:") throw new Error("scheme not allowed");
  const h = u.hostname.toLowerCase();
  if (
    h === "localhost" ||
    h === "0.0.0.0" ||
    h.endsWith(".local") ||
    h.endsWith(".internal") ||
    /^127\./.test(h) ||
    /^10\./.test(h) ||
    /^192\.168\./.test(h) ||
    /^169\.254\./.test(h) ||            // cloud metadata
    /^172\.(1[6-9]|2\d|3[01])\./.test(h)
  ) throw new Error("private address blocked");
  if (!ALLOWED_HOSTS.has(h)) throw new Error(`host not on allowlist: ${h}`);
  return u;
}

/* ── Adapters ────────────────────────────────────────────────────────────
   One per approved source. Each declares whether it is configured, so a
   missing key degrades that source only and never the whole search.     */

const partnerFeed: PropertySearchProvider = {
  id: "partner_feed",
  name: "Licensed partner feed",
  confidence: 0.92,
  configured: () => !!process.env.PARTNER_FEED_URL && !!process.env.PARTNER_FEED_KEY,
  async search(q, signal) {
    const url = assertFetchable(process.env.PARTNER_FEED_URL!);
    url.searchParams.set("country", "JO");
    if (q.city) url.searchParams.set("city", q.city);
    if (q.deal) url.searchParams.set("type", q.deal);
    if (q.budgetMax) url.searchParams.set("price_max", String(q.budgetMax));
    if (q.beds != null) url.searchParams.set("beds_min", String(q.beds));

    const res = await fetch(url, {
      signal,
      redirect: "error",
      headers: { Authorization: `Bearer ${process.env.PARTNER_FEED_KEY}` },
    });
    if (!res.ok) throw new Error(`${this.name}: HTTP ${res.status}`);
    const body = await res.json();
    return (body.results ?? []).map(normalisePartnerRow);
  },
};

function normalisePartnerRow(row: any): ExternalPropertyResult {
  // Map to our shape explicitly. Never spread a third-party object into a
  // response: unknown fields are how injected content reaches the client.
  return {
    externalId: String(row.id ?? ""),
    sourceName: "Licensed partner feed",
    sourceUrl: String(row.url ?? ""),
    title: String(row.title ?? "").slice(0, 200),
    transactionType: row.listing_type === "rent" ? "rent" : "sale",
    price: num(row.price),
    currency: "JOD",
    bedrooms: num(row.bedrooms),
    bathrooms: num(row.bathrooms),
    areaSqm: num(row.area_sqm),
    propertyType: row.property_type ? String(row.property_type) : undefined,
    city: row.city ? String(row.city) : undefined,
    neighborhood: row.neighborhood ? String(row.neighborhood) : undefined,
    latitude: num(row.lat),
    longitude: num(row.lng),
    imageUrl: row.image ? String(row.image) : undefined,
    publishedAt: row.published_at ?? undefined,
    discoveredAt: new Date().toISOString(),
    lastCheckedAt: new Date().toISOString(),
    availabilityStatus: "unknown",
  };
}

const num = (v: unknown) => {
  const n = typeof v === "string" ? parseFloat(v) : typeof v === "number" ? v : NaN;
  return Number.isFinite(n) ? n : undefined;
};

const PROVIDERS: PropertySearchProvider[] = [partnerFeed];

/* ── Callers ─────────────────────────────────────────────────────────────
   Cookie session on the website, a verified bearer token from the app, or
   anonymous: see lib/caller.ts. */

/* ── Input ───────────────────────────────────────────────────────────────
   Constraints arrive from a client, so each field is checked and copied
   explicitly; anything unexpected is dropped rather than passed to a query. */

const ID = /^[a-z0-9_-]{1,40}$/;

function cleanConstraints(raw: unknown): Constraints | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const id = (v: unknown) => (typeof v === "string" && ID.test(v) ? v : null);
  const count = (v: unknown, max: number) =>
    typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= max ? Math.round(v) : null;
  return {
    deal: r.deal === "sale" || r.deal === "rent" ? r.deal : null,
    city: id(r.city),
    hood: id(r.hood),
    budgetMin: count(r.budgetMin, 2_000_000_000),
    budgetMax: count(r.budgetMax, 2_000_000_000),
    beds: count(r.beds, 50),
    baths: count(r.baths, 50),
    type: id(r.type),
    amenities: Array.isArray(r.amenities)
      ? r.amenities.filter((a): a is string => typeof a === "string" && ID.test(a)).slice(0, 20)
      : [],
    internalOnly: r.internalOnly === true,
  };
}

/* ── Route ───────────────────────────────────────────────────────────── */

export async function POST(request: NextRequest) {
  const { supabase, user } = await resolveCaller(request);

  // Rate limit by user where signed in, by IP otherwise. The counter is shared
  // across instances (see allow() below), so this holds on a real deployment.
  const ip = callerIp(request);
  const key = user?.id ?? (ip || "anon");
  if (!(await allow(key, user ? 60 : 15))) {
    return NextResponse.json({ error: "Too many searches. Try again shortly." }, { status: 429 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Request body must be JSON" }, { status: 400 });
  }
  const constraints = cleanConstraints((body as { constraints?: unknown } | null)?.constraints);
  if (!constraints) return NextResponse.json({ error: "Missing constraints" }, { status: 400 });

  // 1. Our own inventory. RLS keeps this to active listings.
  let internalQuery = supabase.from("properties").select("*").eq("status", "active");
  // Buy and Rent only: a daily rental's price is per night, and it has its
  // own page. Named rather than excluded, so this works before 0019 runs.
  internalQuery = constraints.deal
    ? internalQuery.eq("deal", constraints.deal)
    : internalQuery.in("deal", ["sale", "rent"]);
  if (constraints.city) internalQuery = internalQuery.eq("city_id", constraints.city);
  if (constraints.type) internalQuery = internalQuery.eq("property_type", constraints.type);
  if (constraints.budgetMax) internalQuery = internalQuery.lte("price_jod", Math.round(constraints.budgetMax * 1.15));
  if (constraints.budgetMin) internalQuery = internalQuery.gte("price_jod", constraints.budgetMin);
  if (constraints.beds != null) internalQuery = internalQuery.gte("bedrooms", constraints.beds - 1);

  const { data: internal, error: internalError } = await internalQuery.limit(60);
  if (internalError) {
    return NextResponse.json({ error: "Search is unavailable right now." }, { status: 503 });
  }

  // 2. External sources in parallel. One failure must not sink the search.
  const unavailable: string[] = [];
  let external: ExternalPropertyResult[] = [];

  if (!constraints.internalOnly) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 6000);
    const active = PROVIDERS.filter(p => {
      if (p.configured()) return true;
      unavailable.push(`${p.name}: not configured`);
      return false;
    });

    const settled = await Promise.allSettled(
      active.map(p => p.search(constraints, controller.signal))
    );
    clearTimeout(timer);

    settled.forEach((r, i) => {
      if (r.status === "fulfilled") external = external.concat(r.value);
      else unavailable.push(`${active[i].name}: unavailable`);
    });
  }

  return NextResponse.json({
    internal: internal ?? [],
    external,
    // Stated plainly so the UI can tell the user what was NOT searched,
    // rather than presenting partial coverage as complete.
    coverage: {
      providersQueried: PROVIDERS.filter(p => p.configured()).length,
      providersTotal: PROVIDERS.length,
      unavailable,
    },
  });
}
