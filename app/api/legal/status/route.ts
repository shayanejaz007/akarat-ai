import type { NextRequest } from "next/server";
import { resolveCaller } from "@/lib/caller";
import { ACCESS, DOCS, RETENTION, isReviewer, missingConfig } from "@/lib/legal/config";
import { dataKeyReady } from "@/lib/legal/crypto";
import { json } from "@/lib/legal/http";

/**
 * GET /api/legal/status
 *
 * What the Ask a Lawyer page needs before anyone types: whether the service
 * is running, whether this visitor may use it, and the upload limits to say
 * out loud. No configuration detail beyond "ready or not" reaches the page.
 */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const ready = missingConfig().length === 0 && dataKeyReady();
  const { user } = await resolveCaller(request);
  const reviewer = !!user && isReviewer(user.email);
  // "open": anyone signed in; "review": only reviewers until launch.
  const phase = ACCESS === "public" ? "open" : "review";
  return json(200, {
    ready,
    phase,
    signedIn: !!user,
    allowed: ready && !!user && (phase === "open" || reviewer),
    reviewer,
    limits: { maxBytes: DOCS.maxBytes, maxPages: DOCS.maxPages, maxDocs: DOCS.maxPerConversation },
    retention: RETENTION,
  });
}
