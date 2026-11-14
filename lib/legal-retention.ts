import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Ask a Lawyer has been removed, but its data still has a retention promise
 * to keep: conversations were to be deleted 90 days after their last
 * message and documents 30 days after upload (0021_legal_ai.sql stamps
 * `expires_at` on every row). The deleting was done by the feature's own
 * routes, now gone, so this keeps it running until nothing is left:
 * legal_sweep() deletes what has expired and returns the stored files to
 * remove with it.
 *
 * Called from the admin overview and from /api/admin/maintenance (a daily
 * Vercel cron). Once supabase/cleanup-legal.sql has been run there is
 * nothing left to sweep, and the call fails quietly.
 */

const BUCKET = "legal-documents";

let service: SupabaseClient | null = null;

function serviceClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  service ??= createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return service;
}

/** Deletes expired legal conversations and documents, and their files. Returns how many files went. */
export async function sweepLegalData(): Promise<number> {
  const sb = serviceClient();
  if (!sb) return 0;
  const { data, error } = await sb.rpc("legal_sweep", { p_limit: 200 });
  if (error || !Array.isArray(data)) return 0;
  const paths = data.map(r => (typeof r === "string" ? r : (r as Record<string, string>).legal_sweep)).filter(Boolean);
  for (let i = 0; i < paths.length; i += 100) await sb.storage.from(BUCKET).remove(paths.slice(i, i + 100));
  return paths.length;
}

/** The same, now and then: cheap enough to call from a route that runs often. */
export function maybeSweepLegalData(chance = 0.05): Promise<number> {
  return Math.random() < chance ? sweepLegalData().catch(() => 0) : Promise.resolve(0);
}
