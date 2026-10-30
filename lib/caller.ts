import type { NextRequest } from "next/server";
import { cookies } from "next/headers";
import { createClient as createSupabaseClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { createClient } from "@/utils/supabase/server";

/* ── Callers ─────────────────────────────────────────────────────────────
   The website calls with its session cookie. The mobile app has no cookies,
   so it sends the Supabase access token as `Authorization: Bearer <jwt>`.
   The token is verified with Supabase before anything trusts it; an invalid
   or expired one is treated as an anonymous caller (a lower rate limit and
   public rows only), never as an error and never as the user it claims.

   Shared by /api/ai/search and /api/ai/advisor. */

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

export async function resolveCaller(request: NextRequest): Promise<{ supabase: SupabaseClient; user: User | null }> {
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

/**
 * The caller's address. x-forwarded-for is a client-to-proxy chain; only the
 * first hop identifies the caller, and taking the whole header lets anyone
 * forge a fresh bucket.
 */
export function callerIp(request: NextRequest): string {
  return (request.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
}
