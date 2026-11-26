/**
 * Server-side listing access for the rendered pages.
 *
 * The browser reads listings through lib/supabase.js. That module unpacks
 * payload_gz with DecompressionStream, which does not exist in Node, so the
 * server needs its own unpack — hence this file rather than a shared one.
 *
 * Reads go through the REST endpoint with the publishable key, so Row Level
 * Security applies exactly as it does in the browser: only active listings
 * come back. No service-role key is involved.
 */
import { gunzipSync } from "node:zlib";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SUPABASE_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export type Media = { url: string; path?: string; type?: "image" | "video" };

export type Payload = {
  description_en?: string;
  description_ar?: string;
  amenities?: string[];
  images?: Media[];
  contact?: Record<string, string>;
};

export type Listing = {
  id: string;
  status: string;
  deal: "sale" | "rent" | "daily";
  property_type: string;
  city_id: string | null;
  neighborhood_id: string | null;
  price_jod: number;
  /** 0025: no price published; price_jod is 0. Absent before 0025 runs. */
  price_on_request?: boolean | null;
  bedrooms: number | null;
  bathrooms: number | null;
  area_sqm: number | null;
  land_sqm: number | null;
  year_built: number | null;
  title_en: string;
  title_ar: string | null;
  verified: boolean;
  created_at: string;
  updated_at: string | null;
  published_at: string | null;
  payload_gz: string | null;
  payload: Payload;
};

/** Mirrors packPayload() in lib/supabase.js: "gz:<base64>" or "raw:<base64>". */
export function unpackPayload(packed: string | null): Payload {
  if (!packed) return {};
  try {
    if (packed.startsWith("gz:")) {
      const buf = Buffer.from(packed.slice(3), "base64");
      return JSON.parse(gunzipSync(buf).toString("utf8"));
    }
    if (packed.startsWith("raw:")) {
      return JSON.parse(Buffer.from(packed.slice(4), "base64").toString("utf8"));
    }
    return JSON.parse(packed);
  } catch {
    // A listing with an unreadable payload should still render its columns
    // rather than take the whole page down.
    return {};
  }
}

const isVideo = (m: Media) => m.type === "video" || /\.(mp4|webm|mov|m4v)(\?|#|$)/i.test(m.url || "");

/** A listing's photos and videos, cover first, as stored. For the admin panel. */
export function mediaOf(packed: string | null): { url: string; video: boolean }[] {
  const images = unpackPayload(packed).images ?? [];
  return images.filter(m => m && m.url).map(m => ({ url: m.url, video: isVideo(m) }));
}

/** The first photo (not a video): what the site shows as the cover. */
export function coverOf(packed: string | null): string | null {
  return mediaOf(packed).find(m => !m.video)?.url ?? null;
}

/** A joined `properties(…, payload_gz)` turned into `properties(…, cover)`. */
export function withCover<T extends Record<string, unknown>>(row: T): T {
  const p = row.properties as Record<string, unknown> | null | undefined;
  if (!p) return row;
  const { payload_gz, ...rest } = p;
  return { ...row, properties: { ...rest, cover: coverOf((payload_gz as string | null) ?? null) } };
}

/**
 * Throws on a transport failure rather than returning null.
 *
 * That distinction matters more than it looks. If a database blip made this
 * return null, the page would call notFound(), and Next caches that 404 for
 * the whole revalidate window — a listing would disappear from search results
 * for five minutes because of a one-second outage. Throwing produces an error
 * response instead, which Next does not cache.
 *
 * null is reserved for "the query worked and there is genuinely no such row".
 */
async function rest<T>(path: string, revalidate: number): Promise<T | null> {
  if (!SUPABASE_URL || !SUPABASE_KEY) return null;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    next: { revalidate },
  });
  if (!res.ok) throw new Error(`Supabase REST ${res.status} for ${path}`);
  return (await res.json()) as T;
}

/** Same call, but a failure is not worth taking a page down for. */
async function restSoft<T>(path: string, revalidate: number): Promise<T | null> {
  try {
    return await rest<T>(path, revalidate);
  } catch {
    return null;
  }
}

export async function getListing(id: string): Promise<Listing | null> {
  // Reject anything that is not a uuid before it reaches the query string.
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    return null;
  }
  // Sold and rented are included alongside active: a listing that closed
  // keeps its page rather than 404ing the link everyone already shared. The
  // page itself greys the photographs and marks it. The statuses left out —
  // draft, pending, paused, rejected, archived — match the public read policy
  // in 0011_sold_visible.sql, which is what actually enforces this.
  const rows = await rest<Listing[]>(
    `properties?id=eq.${id}&status=in.(active,sold,rented)&select=*&limit=1`,
    300
  );
  const row = rows?.[0];
  if (!row) return null;
  return { ...row, payload: unpackPayload(row.payload_gz) };
}

export async function listActiveListings(limit = 5000) {
  // A sitemap that 500s is worse than a sitemap missing today's listings.
  const rows = await restSoft<
    Pick<Listing, "id" | "updated_at" | "created_at" | "published_at">[]
  >(
    `properties?status=eq.active&select=id,updated_at,created_at,published_at`
      + `&order=created_at.desc&limit=${limit}`,
    3600
  );
  return rows ?? [];
}
