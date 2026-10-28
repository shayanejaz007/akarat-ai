import { NextResponse, type NextRequest } from "next/server";
import { gzipSync, gunzipSync } from "node:zlib";
import { translateListing, TranslationUnavailable, type Lang } from "@/lib/translate";

/**
 * POST /api/admin/backfill-translations
 *
 * One-time: gives every listing saved before /api/translate existed its
 * missing language. Before translation, a listing written in one language was
 * saved with that title copied into the other title column and one
 * description left empty, so readers of the other language saw the owner's.
 *
 * Runs here rather than on a laptop because it needs the service-role key to
 * update every owner's rows, and that key already lives in Vercel. Driven by
 * scripts/backfill-translations.mts, a page of listings per call so no single
 * call outlives the function timeout:
 *
 *   Authorization: Bearer <BACKFILL_SECRET>
 *   { apply?: boolean, after?: string, limit?: number }
 *   → { lines: string[], next: string | null }
 *
 * Dry run unless `apply` is true. Safe to repeat: a listing that already has
 * both languages is skipped.
 */

export const runtime = "nodejs";
export const maxDuration = 60;

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

type Row = { id: string; title_en: string | null; title_ar: string | null; payload_gz: string | null };
type Payload = Record<string, unknown> & { description_en?: string; description_ar?: string };

// Mirrors packPayload / unpackPayload in lib/supabase.js.
function unpack(stored: string | null): Payload | null {
  if (!stored) return {};
  try {
    if (stored.startsWith("raw:")) return JSON.parse(Buffer.from(stored.slice(4), "base64").toString("utf8"));
    const b64 = stored.startsWith("gz:") ? stored.slice(3) : stored;
    return JSON.parse(gunzipSync(Buffer.from(b64, "base64")).toString("utf8"));
  } catch {
    return null; // unreadable: leave the row alone rather than overwrite it
  }
}

function pack(obj: Payload) {
  const raw = Buffer.from(JSON.stringify(obj), "utf8");
  const b64 = gzipSync(raw).toString("base64");
  return { payload_gz: "gz:" + b64, payload_bytes: b64.length, raw_bytes: raw.length };
}

const isArabic = (s: string) => /[؀-ۿ]/.test(s);

function headers() {
  return { apikey: SERVICE!, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" };
}

async function fix(row: Row, apply: boolean): Promise<string | null> {
  const payload = unpack(row.payload_gz);
  if (!payload) return `skipped ${row.id}: payload unreadable`;

  const t = {
    title_en: (row.title_en ?? "").trim(),
    title_ar: (row.title_ar ?? "").trim(),
    description_en: String(payload.description_en ?? "").trim(),
    description_ar: String(payload.description_ar ?? "").trim(),
  };

  // A title copied across: whichever script it is written in is the source.
  if (t.title_en && t.title_en === t.title_ar) {
    if (isArabic(t.title_en)) t.title_en = "";
    else t.title_ar = "";
  }

  const before = { ...t };
  for (const [from, to] of [["en", "ar"], ["ar", "en"]] as [Lang, Lang][]) {
    const needTitle = !!t[`title_${from}`] && !t[`title_${to}`];
    const needDesc = !!t[`description_${from}`] && !t[`description_${to}`];
    if (!needTitle && !needDesc) continue;
    const out = await translateListing(
      { title: needTitle ? t[`title_${from}`] : "", description: needDesc ? t[`description_${from}`] : "" },
      from,
    );
    if (needTitle) t[`title_${to}`] = out.title;
    if (needDesc) t[`description_${to}`] = out.description;
  }

  const changed = (Object.keys(t) as (keyof typeof t)[]).filter(k => t[k] && t[k] !== before[k]);
  if (!changed.length) return null;

  const update = {
    // Neither title may end up empty; fall back to the other as the forms do.
    title_en: t.title_en || t.title_ar,
    title_ar: t.title_ar || t.title_en,
    ...(changed.some(k => k.startsWith("description"))
      ? pack({ ...payload, description_en: t.description_en, description_ar: t.description_ar })
      : {}),
  };
  const summary = `${row.id}: ${changed.join(", ")} → "${update.title_en}" / "${update.title_ar}"`;
  if (!apply) return `would update ${summary}`;

  const res = await fetch(`${URL_}/rest/v1/properties?id=eq.${row.id}`, {
    method: "PATCH",
    headers: { ...headers(), Prefer: "return=minimal" },
    body: JSON.stringify(update),
    cache: "no-store",
  });
  if (!res.ok) return `FAILED ${row.id}: ${res.status} ${await res.text()}`;
  return `updated ${summary}`;
}

export async function POST(request: NextRequest) {
  // Trimmed: a value pasted into Vercel easily carries a trailing newline.
  const secret = process.env.BACKFILL_SECRET?.trim();
  if (!secret) {
    return NextResponse.json({ error: "BACKFILL_SECRET is not set on this deployment." }, { status: 503 });
  }
  if (request.headers.get("authorization")?.trim() !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Not authorised" }, { status: 401 });
  }
  if (!URL_ || !SERVICE) {
    return NextResponse.json({ error: "SUPABASE_SERVICE_ROLE_KEY is not set on this deployment." }, { status: 503 });
  }

  const body = (await request.json().catch(() => ({}))) as { apply?: boolean; after?: string; limit?: number };
  const apply = body.apply === true;
  const limit = Math.min(Math.max(Math.round(Number(body.limit) || 8), 1), 20);
  const after = typeof body.after === "string" && /^[0-9a-f-]{36}$/i.test(body.after) ? body.after : null;

  const res = await fetch(
    `${URL_}/rest/v1/properties?select=id,title_en,title_ar,payload_gz&order=id.asc&limit=${limit}` +
      (after ? `&id=gt.${after}` : ""),
    { headers: headers(), cache: "no-store" },
  );
  if (!res.ok) {
    // Supabase's own message: behind the secret, and the only way to tell a
    // wrong key from a missing grant without access to the dashboard.
    const detail = (await res.text()).slice(0, 300);
    return NextResponse.json({ error: `Reading listings failed: ${res.status} ${detail}` }, { status: 502 });
  }
  const rows = (await res.json()) as Row[];

  const lines: string[] = [];
  for (const row of rows) {
    try {
      const line = await fix(row, apply);
      lines.push(line ?? `ok ${row.id}: already in both languages`);
    } catch (e) {
      if (e instanceof TranslationUnavailable) {
        return NextResponse.json({ error: "ANTHROPIC_API_KEY is not set on this deployment." }, { status: 503 });
      }
      lines.push(`FAILED ${row.id}: ${(e as Error).message}`);
    }
  }

  return NextResponse.json({ lines, next: rows.length === limit ? rows[rows.length - 1].id : null });
}
