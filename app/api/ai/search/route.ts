import { NextResponse, type NextRequest } from "next/server";
import { cookies } from "next/headers";
import { createClient as createSupabaseClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { createClient } from "@/utils/supabase/server";

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
   The website calls with its session cookie. The mobile app has no cookies,
   so it sends the Supabase access token as `Authorization: Bearer <jwt>`.
   The token is verified with Supabase before anything trusts it; an invalid
   or expired one is treated as an anonymous caller (a lower rate limit and
   public rows only), never as an error and never as the user it claims. */

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

function bearerToken(request: NextRequest): string | null {
  const m = /^Bearer\s+([A-Za-z0-9._-]+)$/i.exec(request.headers.get("authorization") ?? "");
  return m ? m[1] : null;
}

function publishableClient(token?: string): SupabaseClient {
  return createSupabaseClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: token ? { headers: { Authorization: `Bearer ${token}` } } : undefined,
  });
}

async function resolveCaller(request: NextRequest): Promise<{ supabase: SupabaseClient; user: User | null }> {
  const token = bearerToken(request);
  if (token && SUPABASE_URL && SUPABASE_ANON_KEY) {
    const { data, error } = await publishableClient().auth.getUser(token);
    if (!error && data.user) return { supabase: publishableClient(token), user: data.user };
    return { supabase: publishableClient(), user: null };
  }
  const supabase = createClient(await cookies()) as unknown as SupabaseClient;
  const { data: { user } } = await supabase.auth.getUser();
  return { supabase, user };
}

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
  const forwarded = request.headers.get("x-forwarded-for") ?? "";
  // x-forwarded-for is a client-to-proxy chain; only the first hop identifies
  // the caller, and taking the whole header lets anyone forge a fresh bucket.
  const ip = forwarded.split(",")[0].trim();
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
  if (constraints.deal) internalQuery = internalQuery.eq("deal", constraints.deal);
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

/* A counter in Postgres rather than in this process. Every serverless
   instance gets its own module scope, so the Map this replaced reset on each
   cold start and was never shared between concurrent instances — the limit it
   appeared to enforce was mostly decorative.

   Failing open is deliberate: a rate limiter that takes search down when the
   database hiccups is worse than the abuse it prevents. */
/* Per-instance fallback, used only when the shared counter is unavailable
   because it was never configured. Weaker than the Postgres one — each
   serverless instance keeps its own map, so the effective limit is this
   number times however many instances are warm — but it bounds a single
   caller hammering one instance, which an unconfigured deployment otherwise
   has no answer to at all. */
const localHits = new Map<string, number[]>();

function allowLocally(key: string, perMinute: number): boolean {
  const now = Date.now();
  const recent = (localHits.get(key) ?? []).filter(t => now - t < 60_000);
  recent.push(now);
  localHits.set(key, recent);
  // Unbounded growth would be its own denial of service.
  if (localHits.size > 5000) {
    for (const [k, v] of localHits) {
      if (!v.length || now - v[v.length - 1] > 60_000) localHits.delete(k);
    }
  }
  return recent.length <= perMinute;
}

async function allow(key: string, perMinute: number): Promise<boolean> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  // Not configured is not the same as temporarily broken. Returning true here
  // meant a deployment that never set SUPABASE_SERVICE_ROLE_KEY had no limit
  // at all, permanently and silently: an audit of the live site ran 25
  // searches in a few seconds past a documented limit of 15 a minute without
  // one being refused. Fall back to the in-process counter, not to nothing.
  if (!url || !serviceKey) return allowLocally(key, perMinute);

  try {
    const res = await fetch(`${url}/rest/v1/rpc/check_rate_limit`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ p_key: key, p_limit: perMinute, p_window_seconds: 60 }),
      cache: "no-store",
    });
    // 404 means the function was never installed (0008_hardening.sql has not
    // been run); 401/403 that the key is wrong. Those are configuration, not
    // a hiccup, so they get the fallback rather than a free pass.
    if (res.status === 404 || res.status === 401 || res.status === 403) {
      return allowLocally(key, perMinute);
    }
    // Anything else — a timeout, a 500 — is transient, and failing open there
    // is deliberate: taking search down when the database stumbles is worse
    // than the abuse it would prevent.
    if (!res.ok) return true;
    return (await res.json()) !== false;
  } catch {
    return true;
  }
}
