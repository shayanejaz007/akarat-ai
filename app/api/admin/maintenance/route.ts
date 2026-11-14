import { createHash, timingSafeEqual } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { sweepLegalData } from "@/lib/legal-retention";

/**
 * GET /api/admin/maintenance — housekeeping that has to happen whether or
 * not anyone opens the site: today, deleting Ask a Lawyer's expired
 * conversations and documents now that the feature is gone
 * (lib/legal-retention.ts).
 *
 * Run daily by Vercel Cron (vercel.json), which sends
 * `Authorization: Bearer $CRON_SECRET` when CRON_SECRET is set. Anyone else
 * is refused.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const secret = process.env.CRON_SECRET;
  // Hashed first, so the comparison takes the same time whatever was sent.
  const digest = (v: string) => createHash("sha256").update(v).digest();
  const given = request.headers.get("authorization") ?? "";
  if (!secret || !timingSafeEqual(digest(given), digest(`Bearer ${secret}`))) {
    return NextResponse.json({ error: "Not authorised" }, { status: 401 });
  }
  let legalFilesRemoved = 0;
  // A few passes of 200, so a backlog clears in one run without a long request.
  for (let pass = 0; pass < 5; pass++) {
    const n = await sweepLegalData().catch(() => 0);
    legalFilesRemoved += n;
    if (n < 200) break;
  }
  return NextResponse.json({ ok: true, legalFilesRemoved });
}
