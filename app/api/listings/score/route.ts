import { NextResponse, type NextRequest } from "next/server";
import { isUuid } from "@/lib/admin";
import { scoreOne, serviceClient } from "@/lib/listing-quality";

/**
 * POST /api/listings/score  { id }
 *
 * Called by the website and the app straight after a listing is saved, so a
 * new or edited listing takes its place in the ranking within seconds rather
 * than at the nightly run. It works the score out from what is stored and
 * nothing the caller sends, so anyone may call it: the worst it can do is
 * score a listing that was already going to be scored, and a listing that is
 * up to date costs one read.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  let id: unknown;
  try {
    id = (await request.json())?.id;
  } catch {
    return NextResponse.json({ error: "bad_request" }, { status: 400 });
  }
  if (!isUuid(id)) return NextResponse.json({ error: "bad_request" }, { status: 400 });
  const db = serviceClient();
  if (!db) return NextResponse.json({ error: "not_configured" }, { status: 503 });
  try {
    const { score } = await scoreOne(db, id);
    return NextResponse.json({ score }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "unavailable" }, { status: 503 });
  }
}
