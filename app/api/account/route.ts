import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";

/**
 * DELETE /api/account        { "confirm": true }
 *
 * Deletes the caller's own account. Both app stores require that an app which
 * lets people create an account also lets them delete it from inside the app,
 * and deleting an auth user needs the service-role key — so it can only
 * happen here, on the server, never in a client.
 *
 * Who is deleted is decided by the access token alone: the caller's Supabase
 * JWT is verified with Supabase, and the user it belongs to is the only one
 * this route will ever delete. No user id is read from the request.
 *
 * What goes, through the foreign keys in the migrations:
 *   auth.users row → profiles, properties (and with them their inquiries and
 *   exact locations), saved_searches, favorites, inquiries addressed to them.
 *   Inquiries they SENT stay with their recipients; sender_id is set null.
 * Then their folder in the listing-photos bucket is emptied, best effort.
 */

export const runtime = "nodejs";

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = "listing-photos";

function bearerToken(request: NextRequest): string | null {
  const m = /^Bearer\s+([A-Za-z0-9._-]+)$/i.exec(request.headers.get("authorization") ?? "");
  return m ? m[1] : null;
}

export async function DELETE(request: NextRequest) {
  if (!URL_ || !ANON || !SERVICE) {
    return NextResponse.json({ error: "Account deletion is not available right now." }, { status: 503 });
  }

  const token = bearerToken(request);
  if (!token) return NextResponse.json({ error: "Sign in again to delete your account." }, { status: 401 });

  let body: unknown = null;
  try {
    body = await request.json();
  } catch {
    /* handled below */
  }
  if (!body || (body as { confirm?: unknown }).confirm !== true) {
    return NextResponse.json({ error: "Deletion must be confirmed." }, { status: 400 });
  }

  const verifier = createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await verifier.auth.getUser(token);
  const user = data?.user;
  if (error || !user) return NextResponse.json({ error: "Sign in again to delete your account." }, { status: 401 });

  const admin = createClient(URL_, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });

  const emptyFolder = async () => {
    try {
      for (let page = 0; page < 50; page++) {
        const { data: files } = await admin.storage.from(BUCKET).list(user.id, { limit: 100 });
        if (!files || files.length === 0) break;
        await admin.storage.from(BUCKET).remove(files.map((f) => `${user.id}/${f.name}`));
        if (files.length < 100) break;
      }
    } catch {
      /* best effort: orphaned files cost storage, not correctness */
    }
  };

  // The account first, so a failure leaves the listings and their photos
  // intact. Projects created before Supabase dropped the storage.objects
  // owner foreign key refuse to delete a user who still owns files; in that
  // case the folder is emptied and the deletion tried once more.
  let { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    await emptyFolder();
    ({ error: deleteError } = await admin.auth.admin.deleteUser(user.id));
    if (deleteError) {
      return NextResponse.json({ error: "We could not delete the account. Try again, or email privacy@akarat.ai." }, { status: 500 });
    }
    return NextResponse.json({ deleted: true });
  }

  await emptyFolder();
  return NextResponse.json({ deleted: true });
}
