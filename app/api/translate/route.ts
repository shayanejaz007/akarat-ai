import { NextResponse, type NextRequest } from "next/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { allow } from "@/lib/rate-limit";
import {
  translateListing,
  TranslationUnavailable,
  MAX_DESCRIPTION,
  MAX_TITLE,
  type Lang,
} from "@/lib/translate";

/**
 * POST /api/translate
 *
 *   { from: "en" | "ar", title?: string, description?: string }
 *   → { title, description } in the other language
 *
 * Called by the listing forms on the website and in the app to fill the
 * language the owner did not write in. Signed-in callers only: listing is the
 * only reason to translate, and an open endpoint would be a free translator
 * billed to us. Both clients send the Supabase access token as a bearer token.
 *
 * Failure is never fatal to the form: a 503 (no key configured) or any error
 * leaves the other field for the owner to fill, as before.
 */

export const runtime = "nodejs";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

function bearerToken(request: NextRequest): string | null {
  const m = /^Bearer\s+([A-Za-z0-9._-]+)$/i.exec(request.headers.get("authorization") ?? "");
  return m ? m[1] : null;
}

export async function POST(request: NextRequest) {
  const token = bearerToken(request);
  if (!token || !SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return NextResponse.json({ error: "Sign in to translate." }, { status: 401 });
  }
  const verifier = createSupabaseClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await verifier.auth.getUser(token);
  if (error || !data.user) {
    return NextResponse.json({ error: "Sign in to translate." }, { status: 401 });
  }

  // Generous for someone filling in a form; tight for anyone scripting it.
  if (!(await allow(`translate:${data.user.id}`, 20))) {
    return NextResponse.json({ error: "Too many translations. Try again shortly." }, { status: 429 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Expected JSON." }, { status: 400 });
  }
  const b = (body ?? {}) as Record<string, unknown>;
  const from: Lang | null = b.from === "en" || b.from === "ar" ? b.from : null;
  const title = typeof b.title === "string" ? b.title : "";
  const description = typeof b.description === "string" ? b.description : "";
  if (!from) return NextResponse.json({ error: "from must be en or ar." }, { status: 400 });
  if (title.length > MAX_TITLE || description.length > MAX_DESCRIPTION) {
    return NextResponse.json({ error: "Text too long to translate." }, { status: 413 });
  }

  try {
    return NextResponse.json(await translateListing({ title, description }, from));
  } catch (e) {
    if (e instanceof TranslationUnavailable) {
      return NextResponse.json({ error: "Translation is not available right now." }, { status: 503 });
    }
    console.error("translate failed", e);
    return NextResponse.json({ error: "Translation failed." }, { status: 502 });
  }
}
