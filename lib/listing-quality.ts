/**
 * Scores listings and stores the result (properties.quality_score, migration
 * 0025). Server-only: it needs the service role, because owners cannot write
 * the score, and it unpacks the gzipped payload, which SQL cannot read.
 *
 * Called three ways:
 *   - /api/listings/score, right after the website or the app saves a
 *     listing, so a new listing is ranked within seconds;
 *   - the nightly maintenance run, for anything that save-time call missed;
 *   - the admin panel's "Re-score all", after the weights change.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { unpackPayload } from "@/lib/listing-server";
import { scoreListing } from "@/lib/listing-score.js";

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

const COLUMNS =
  "id,deal,property_type,city_id,neighborhood_id,lat,lng,price_jod,price_on_request," +
  "bedrooms,bathrooms,area_sqm,land_sqm,year_built,title_en,title_ar,payload_gz,updated_at,quality_scored_at";

/** A service-role client, or null when the deployment has no service key. */
export function serviceClient(): SupabaseClient | null {
  if (!URL_ || !SERVICE) return null;
  return createClient(URL_, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
}

type Row = Record<string, unknown> & { id: string; payload_gz: string | null };

/**
 * Scores these rows and writes the results. Returns how many were written.
 *
 * Only if the listing is still as it was read: an owner who saves while it
 * is being scored keeps their edit "not scored yet", and their own save's
 * call (or the nightly run) scores it. The time written is never earlier
 * than the edit it scored, so a server clock a little behind the database's
 * cannot leave a listing looking edited since.
 */
async function write(db: SupabaseClient, rows: Row[]): Promise<number> {
  let n = 0;
  for (const row of rows) {
    const { score, parts } = scoreListing(row, unpackPayload(row.payload_gz));
    const edited = Date.parse(String(row.updated_at));
    const at = new Date(Math.max(Date.now(), Number.isFinite(edited) ? edited + 1 : 0)).toISOString();
    let req = db.from("properties").update({ quality_score: score, quality_parts: parts, quality_scored_at: at }).eq("id", row.id);
    if (row.updated_at) req = req.eq("updated_at", String(row.updated_at));
    const { data, error } = await req.select("id");
    if (!error && Array.isArray(data) && data.length) n += 1;
  }
  return n;
}

/**
 * Scores one listing if it was never scored or was edited since. A listing
 * already up to date is left alone, so calling this repeatedly costs one read.
 */
export async function scoreOne(db: SupabaseClient, id: string): Promise<{ score: number | null; fresh: boolean }> {
  const { data, error } = await db.from("properties").select(COLUMNS + ",quality_score").eq("id", id).maybeSingle();
  if (error || !data) return { score: null, fresh: false };
  const row = data as unknown as Row & { quality_score: number | null };
  const scoredAt = row.quality_scored_at ? Date.parse(String(row.quality_scored_at)) : NaN;
  const updatedAt = Date.parse(String(row.updated_at));
  if (Number.isFinite(scoredAt) && !(scoredAt < updatedAt)) return { score: row.quality_score, fresh: false };
  const written = await write(db, [row]);
  const { score } = scoreListing(row, unpackPayload(row.payload_gz));
  return { score, fresh: written > 0 };
}

/** Scores up to `limit` listings that need it. Returns how many were scored. */
export async function scoreStale(db: SupabaseClient, limit = 200): Promise<number> {
  const { data: ids, error } = await db.rpc("listings_to_score", { p_limit: limit });
  if (error || !Array.isArray(ids) || !ids.length) return 0;
  const list = ids.map(v => (typeof v === "string" ? v : (v as { listings_to_score?: string }).listings_to_score)).filter(Boolean) as string[];
  let total = 0;
  for (let i = 0; i < list.length; i += 50) {
    const { data } = await db.from("properties").select(COLUMNS).in("id", list.slice(i, i + 50));
    total += await write(db, (data ?? []) as unknown as Row[]);
  }
  return total;
}

/** Re-scores every listing, a page at a time. For the admin panel. */
export async function scoreAll(db: SupabaseClient): Promise<number> {
  let total = 0;
  for (let from = 0; ; from += 200) {
    const { data, error } = await db.from("properties").select(COLUMNS).order("id").range(from, from + 199);
    if (error || !data?.length) break;
    total += await write(db, data as unknown as Row[]);
    if (data.length < 200) break;
  }
  return total;
}
