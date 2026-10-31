/**
 * The checks every Ask a Lawyer route makes, in the same order: configured,
 * signed in, allowed in. Signed in is not optional here: conversations and
 * documents belong to an account, and Row Level Security needs one to keep
 * them apart.
 */
import type { NextRequest } from "next/server";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { resolveCaller } from "@/lib/caller";
import { ACCESS, isReviewer, missingConfig } from "./config";
import { dataKeyReady } from "./crypto";

export type Caller = { supabase: SupabaseClient; user: User; reviewer: boolean };

export const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });

export type GateError = "not_configured" | "sign_in" | "not_open";

const STATUS: Record<GateError, number> = { not_configured: 503, sign_in: 401, not_open: 403 };

/** The caller, or the reason they cannot come in. */
export async function gate(request: NextRequest): Promise<Caller | { error: GateError; status: number }> {
  if (missingConfig().length || !dataKeyReady()) return { error: "not_configured", status: STATUS.not_configured };
  const { supabase, user } = await resolveCaller(request);
  if (!user) return { error: "sign_in", status: STATUS.sign_in };
  const reviewer = isReviewer(user.email);
  if (ACCESS !== "public" && !reviewer) return { error: "not_open", status: STATUS.not_open };
  return { supabase, user, reviewer };
}
