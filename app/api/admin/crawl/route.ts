/**
 * Crawl worker.
 *
 * POST /api/admin/crawl        { sourceId?: string, maxPages?: number }
 *
 * Fills external_properties so a user's search never waits on a third-party
 * site. Runs on a schedule (Vercel Cron or Supabase pg_cron calling this route)
 * and is the only writer to the index: it holds the service-role key, which
 * bypasses RLS and must never reach a browser.
 *
 * What it will not do:
 *   - touch a host that is not enabled in external_sources
 *   - ignore robots.txt
 *   - request faster than that source's configured delay
 *   - pass raw page HTML into any reasoning layer
 *   - bypass a CAPTCHA, paywall or login
 *
 * Extraction reads schema.org JSON-LD, which portals publish deliberately for
 * exactly this purpose. It is more reliable than scraping markup and it breaks
 * loudly rather than silently when a site changes.
 */

import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";
export const maxDuration = 60;

const UA =
  "AkaratBot/1.0 (+https://akarat.ai/bot; property indexing; contact: crawler@akarat.ai)";

type SourceRow = {
  id: string;
  name: string;
  host: string;
  kind: string;
  confidence: number;
  enabled: boolean;
  crawl_delay_ms: number;
  requests_per_hour: number;
};

function admin() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Crawler needs NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
  return createClient(url, key, { auth: { persistSession: false } });
}

/* ── robots.txt ──────────────────────────────────────────────────────────
   Parsed per host and cached for the process. Rules for our own agent take
   precedence over the wildcard group, matching the usual convention.      */

type Robots = { disallow: string[]; allow: string[]; delayMs: number | null };
const robotsCache = new Map<string, { at: number; rules: Robots }>();

async function getRobots(host: string): Promise<Robots> {
  const hit = robotsCache.get(host);
  if (hit && Date.now() - hit.at < 6 * 60 * 60 * 1000) return hit.rules;

  const rules: Robots = { disallow: [], allow: [], delayMs: null };
  try {
    const res = await fetch(`https://${host}/robots.txt`, {
      headers: { "User-Agent": UA },
      redirect: "follow",
    });
    if (res.ok) {
      const text = await res.text();
      let appliesToUs = false;
      let appliesToAll = false;
      const ours: Robots = { disallow: [], allow: [], delayMs: null };
      const all: Robots = { disallow: [], allow: [], delayMs: null };

      for (const raw of text.split(/\r?\n/)) {
        const line = raw.replace(/#.*$/, "").trim();
        if (!line) continue;
        const [field, ...rest] = line.split(":");
        const value = rest.join(":").trim();
        const name = field.trim().toLowerCase();

        if (name === "user-agent") {
          const agent = value.toLowerCase();
          appliesToUs = agent === "akaratbot";
          appliesToAll = agent === "*";
          continue;
        }
        const target = appliesToUs ? ours : appliesToAll ? all : null;
        if (!target) continue;
        if (name === "disallow" && value) target.disallow.push(value);
        else if (name === "allow" && value) target.allow.push(value);
        else if (name === "crawl-delay") {
          const secs = parseFloat(value);
          if (Number.isFinite(secs)) target.delayMs = secs * 1000;
        }
      }
      const chosen = ours.disallow.length || ours.allow.length || ours.delayMs != null ? ours : all;
      rules.disallow = chosen.disallow;
      rules.allow = chosen.allow;
      rules.delayMs = chosen.delayMs;
    }
    // A 4xx means no restrictions published. A 5xx is ambiguous, so we treat
    // it as "do not crawl right now" by leaving the caller to see the throw.
    else if (res.status >= 500) throw new Error(`robots.txt HTTP ${res.status}`);
  } catch (e) {
    // Network failure: refuse rather than assume permission.
    throw new Error(`could not read robots.txt for ${host}`);
  }

  robotsCache.set(host, { at: Date.now(), rules });
  return rules;
}

function robotsAllows(rules: Robots, path: string) {
  const match = (pattern: string) => {
    // robots.txt prefix matching, with * and $ as the only wildcards
    const rx = new RegExp(
      "^" +
        pattern
          .replace(/[.+?^${}()|[\]\\]/g, "\\$&")
          .replace(/\*/g, ".*")
          .replace(/\\\$$/, "$") +
        (pattern.endsWith("$") ? "" : "")
    );
    return rx.test(path);
  };
  const longest = (list: string[]) =>
    list.filter(match).sort((a, b) => b.length - a.length)[0] ?? null;

  const allowed = longest(rules.allow);
  const blocked = longest(rules.disallow);
  if (blocked == null) return true;
  if (allowed == null) return false;
  return allowed.length >= blocked.length; // more specific Allow wins
}

/* ── politeness ─────────────────────────────────────────────────────────── */

const lastRequestAt = new Map<string, number>();

async function politeFetch(host: string, url: string, delayMs: number) {
  const prev = lastRequestAt.get(host) ?? 0;
  const wait = Math.max(0, prev + delayMs - Date.now());
  if (wait) await new Promise(r => setTimeout(r, wait));
  lastRequestAt.set(host, Date.now());

  const res = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "text/html,application/xhtml+xml" },
    redirect: "follow",
  });
  // Back off exactly as asked.
  if (res.status === 429 || res.status === 503) {
    const retry = parseInt(res.headers.get("retry-after") ?? "", 10);
    throw new Error(`rate limited, retry after ${Number.isFinite(retry) ? retry : 60}s`);
  }
  return res;
}

/* ── extraction ─────────────────────────────────────────────────────────── */

type Extracted = {
  sourceListingId?: string;
  sourceUrl: string;
  title: string;
  description?: string;
  price?: number;
  currency?: string;
  transactionType?: "sale" | "rent";
  propertyType?: string;
  bedrooms?: number;
  bathrooms?: number;
  areaSqm?: number;
  latitude?: number;
  longitude?: number;
  imageUrl?: string;
  publishedAt?: string;
};

/** Pull every JSON-LD block. No HTML text ever leaves this function. */
function jsonLdBlocks(html: string): any[] {
  const out: any[] = [];
  const rx = /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let m: RegExpExecArray | null;
  while ((m = rx.exec(html))) {
    try {
      const parsed = JSON.parse(m[1].trim());
      out.push(...(Array.isArray(parsed) ? parsed : [parsed]));
    } catch {
      /* malformed block: skip it rather than guess */
    }
  }
  // @graph is common
  return out.flatMap(n => (n && Array.isArray(n["@graph"]) ? n["@graph"] : [n]));
}

const LISTING_TYPES = new Set([
  "RealEstateListing", "Residence", "Apartment", "House", "SingleFamilyResidence", "Product", "Offer", "Place",
]);

const num = (v: unknown): number | undefined => {
  if (typeof v === "number") return Number.isFinite(v) ? v : undefined;
  if (typeof v === "string") {
    const n = parseFloat(v.replace(/[^\d.]/g, ""));
    return Number.isFinite(n) ? n : undefined;
  }
  if (v && typeof v === "object") return num((v as any).value ?? (v as any)["@value"]);
  return undefined;
};

const str = (v: unknown): string | undefined => {
  if (typeof v === "string") return v.trim() || undefined;
  if (v && typeof v === "object") return str((v as any).name ?? (v as any)["@value"]);
  return undefined;
};

/** schema.org types are capitalised and coarse; map to our own ids so the app
 *  filters and labels them like any other listing. Unknown stays unknown. */
const TYPE_MAP: Record<string, string> = {
  apartment: "apartment", flat: "apartment", residence: "apartment",
  house: "house", singlefamilyresidence: "house",
  villa: "villa", land: "land", office: "office", shop: "shop",
  store: "shop", building: "building", chalet: "chalet",
  warehouse: "warehouse", farm: "farm",
};

function mapType(raw?: string) {
  if (!raw) return undefined;
  return TYPE_MAP[raw.replace(/\s+/g, "").toLowerCase()];
}

function extractListing(node: any, pageUrl: string): Extracted | null {
  const types = ([] as string[]).concat(node?.["@type"] ?? []);
  if (!types.some(t => LISTING_TYPES.has(t))) return null;

  const offer = ([] as any[]).concat(node.offers ?? [])[0] ?? {};
  const geo = node.geo ?? node.location?.geo ?? {};
  const addr = node.address ?? node.location?.address ?? {};

  const title = str(node.name) ?? str(node.headline);
  if (!title) return null; // no title means we did not really parse a listing

  const price = num(offer.price ?? offer.lowPrice ?? node.price);
  const rentHint = JSON.stringify(offer.businessFunction ?? "") + " " + (str(offer.category) ?? "");

  return {
    sourceListingId: str(node.sku) ?? str(node.identifier) ?? str(node["@id"]),
    sourceUrl: str(node.url) ?? pageUrl,
    title: title.slice(0, 200),
    description: str(node.description)?.slice(0, 4000),
    price,
    currency: str(offer.priceCurrency) ?? "JOD",
    transactionType: /lease|rent/i.test(rentHint) ? "rent" : "sale",
    propertyType: mapType(types.find(t => t !== "Product" && t !== "Offer")),
    bedrooms: num(node.numberOfBedrooms ?? node.numberOfRooms),
    bathrooms: num(node.numberOfBathroomsTotal ?? node.numberOfBathrooms),
    areaSqm: num(node.floorSize),
    latitude: num(geo.latitude),
    longitude: num(geo.longitude),
    imageUrl: str(([] as any[]).concat(node.image ?? [])[0]),
    publishedAt: str(node.datePosted ?? node.datePublished),
  };
}

/* ── location resolution ────────────────────────────────────────────────── */

async function locationIndex(sb: ReturnType<typeof admin>) {
  const [{ data: cities }, { data: hoods }] = await Promise.all([
    sb.from("cities").select("id,name_en,name_ar"),
    sb.from("neighborhoods").select("id,city_id,name_en,name_ar,aliases"),
  ]);
  return { cities: cities ?? [], hoods: hoods ?? [] };
}

function resolvePlace(text: string, idx: Awaited<ReturnType<typeof locationIndex>>) {
  const low = text.toLowerCase();
  for (const h of idx.hoods) {
    const names = [h.name_en, h.name_ar, ...((h.aliases as string[]) ?? [])];
    if (names.some(n => n && (low.includes(String(n).toLowerCase()) || text.includes(String(n)))))
      return { city_id: h.city_id, neighborhood_id: h.id };
  }
  for (const c of idx.cities) {
    if (low.includes(c.name_en.toLowerCase()) || text.includes(c.name_ar))
      return { city_id: c.id, neighborhood_id: null };
  }
  return { city_id: null, neighborhood_id: null };
}

/* ── route ──────────────────────────────────────────────────────────────── */

export async function POST(request: NextRequest) {
  // Cron secret, so the crawler cannot be triggered by the public.
  const auth = request.headers.get("authorization");
  if (!process.env.CRON_SECRET || auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Not authorised" }, { status: 401 });
  }

  const sb = admin();
  const body = await request.json().catch(() => ({}));
  const { sourceId, maxPages = 4 } = body as { sourceId?: string; maxPages?: number };

  let q = sb.from("external_sources").select("*").eq("enabled", true);
  if (sourceId) q = q.eq("id", sourceId);
  const { data: sources, error } = await q;
  if (error) return NextResponse.json({ error: "Could not read sources" }, { status: 503 });
  if (!sources?.length) {
    return NextResponse.json({
      crawled: 0,
      note: "No enabled sources. Review robots.txt and terms, then set enabled = true.",
    });
  }

  const idx = await locationIndex(sb);
  const report: Record<string, unknown>[] = [];

  for (const src of sources as SourceRow[]) {
    const started = Date.now();
    let robots: Robots;
    try {
      robots = await getRobots(src.host);
    } catch (e: any) {
      report.push({ source: src.id, skipped: e.message });
      continue;
    }
    const delay = Math.max(src.crawl_delay_ms, robots.delayMs ?? 0);

    // Seed paths: the portal's own public listing pages. Keep the set small and
    // let the schedule cover breadth over time rather than hammering the host.
    const seeds = seedPaths(src.id).slice(0, maxPages);
    let found = 0, written = 0, blocked = 0;

    for (const path of seeds) {
      if (!robotsAllows(robots, path)) { blocked++; continue; }
      let html: string;
      try {
        const res = await politeFetch(src.host, `https://${src.host}${path}`, delay);
        if (!res.ok) continue;
        const type = res.headers.get("content-type") ?? "";
        if (!/html/i.test(type)) continue;
        html = await res.text();
      } catch (e: any) {
        report.push({ source: src.id, path, error: e.message });
        continue;
      }

      const rows = jsonLdBlocks(html)
        .map(n => extractListing(n, `https://${src.host}${path}`))
        .filter((r): r is Extracted => !!r);
      found += rows.length;

      for (const r of rows) {
        const place = resolvePlace(`${r.title} ${r.description ?? ""}`, idx);
        const { error: upsertError } = await sb.from("external_properties").upsert(
          {
            source_id: src.id,
            source_listing_id: r.sourceListingId ?? r.sourceUrl,
            source_url: r.sourceUrl,
            title: r.title,
            description: r.description ?? null,
            price: r.price != null ? Math.round(r.price) : null,
            currency: r.currency ?? "JOD",
            transaction_type: r.transactionType ?? null,
            property_type: r.propertyType ?? null,
            bedrooms: r.bedrooms != null ? Math.round(r.bedrooms) : null,
            bathrooms: r.bathrooms != null ? Math.round(r.bathrooms) : null,
            area_sqm: r.areaSqm != null ? Math.round(r.areaSqm) : null,
            city_id: place.city_id,
            neighborhood_id: place.neighborhood_id,
            latitude: r.latitude ?? null,
            longitude: r.longitude ?? null,
            image_url: r.imageUrl ?? null,
            source_published_at: r.publishedAt ?? null,
            last_checked_at: new Date().toISOString(),
            last_seen_at: new Date().toISOString(),
            availability_status: "likely_available",
            raw_metadata: { extractedBy: "json-ld" },
          },
          { onConflict: "source_id,source_listing_id" }
        );
        if (!upsertError) written++;
      }
    }

    report.push({
      source: src.id, found, written, blockedByRobots: blocked,
      ms: Date.now() - started,
      note: found === 0
        ? "No JSON-LD listings on the seed pages. Ask the source for a feed, or add an extractor for their markup."
        : undefined,
    });
  }

  // Group duplicates, then retire anything long unseen.
  const { data: grouped } = await sb.rpc("group_external_duplicates");
  const { data: expired } = await sb.rpc("expire_stale_external", { stale_days: 21 });

  return NextResponse.json({ report, grouped: grouped ?? null, expired: expired ?? 0 });
}

/** Public listing paths per source, using grammar already verified by hand. */
function seedPaths(sourceId: string): string[] {
  if (sourceId === "opensooq") {
    return [
      "/en/amman/property/apartments-for-sale",
      "/en/amman/property/apartments-for-rent",
      "/en/amman/property/property-for-sale",
      "/en/irbid/property/apartments-for-sale",
      "/en/aqaba/property/property-for-sale",
    ];
  }
  if (sourceId === "bayut") {
    return [
      "/en/amman/apartments-for-sale/",
      "/en/amman/apartments-for-rent/",
      "/en/amman/villas-for-sale/",
      "/en/irbid/apartments-for-sale/",
      "/en/jordan/properties-for-sale/",
    ];
  }
  return [];
}
