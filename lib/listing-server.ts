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
  deal: "sale" | "rent";
  property_type: string;
  city_id: string | null;
  neighborhood_id: string | null;
  price_jod: number;
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
  const rows = await rest<Listing[]>(
    `properties?id=eq.${id}&status=eq.active&select=*&limit=1`,
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
