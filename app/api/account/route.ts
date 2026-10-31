import { createPrivateKey, sign } from "node:crypto";
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
 *
 * An account that signs in with Apple also loses Akarat.ai's access to the
 * Apple ID first, as Apple requires (see revokeApple below).
 */

export const runtime = "nodejs";
// Apple's two calls, before the deletion itself.
export const maxDuration = 30;

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
// Each keeps one folder per account: listing photos, and Ask a Lawyer's
// sealed documents (0021_legal_ai.sql), whose rows the database deletes
// with the account but whose files it cannot.
const BUCKETS = ["listing-photos", "legal-documents"];

function bearerToken(request: NextRequest): string | null {
  const m = /^Bearer\s+([A-Za-z0-9._-]+)$/i.exec(request.headers.get("authorization") ?? "");
  return m ? m[1] : null;
}

/* ── Sign in with Apple ───────────────────────────────────────────────────
   Apple requires an app that offers Sign in with Apple to revoke its access
   when someone deletes their account. The iPhone app sends a fresh one-time
   code from Apple's sheet; it is exchanged here for a token, which is then
   revoked. It takes the Sign in with Apple key from the Apple Developer
   account (the one Supabase's Apple provider is set up with):

     APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8 file's text),
     APPLE_BUNDLE_ID (defaults to ai.akarat.app)

   Best effort: without them, or if Apple does not answer, the account is
   deleted all the same, and the person can still remove Akarat.ai from
   their Apple ID in Settings. */

const APPLE_TEAM_ID = process.env.APPLE_TEAM_ID;
const APPLE_KEY_ID = process.env.APPLE_KEY_ID;
const APPLE_PRIVATE_KEY = process.env.APPLE_PRIVATE_KEY;
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID || "ai.akarat.app";
const APPLE_CODE = /^[A-Za-z0-9._-]{10,2048}$/;

const b64url = (data: Buffer | string) => Buffer.from(data).toString("base64url");

/** Apple's client secret: a short-lived ES256 token signed with the .p8 key. */
function appleClientSecret(): string | null {
  if (!APPLE_TEAM_ID || !APPLE_KEY_ID || !APPLE_PRIVATE_KEY) return null;
  // A key pasted into Vercel keeps its line breaks, or arrives with them
  // written out as the two characters backslash and n.
  const pem = APPLE_PRIVATE_KEY.split(String.fromCharCode(92) + "n").join(String.fromCharCode(10));
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: APPLE_KEY_ID }));
  const claims = b64url(
    JSON.stringify({ iss: APPLE_TEAM_ID, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: APPLE_BUNDLE_ID }),
  );
  const signature = sign("sha256", Buffer.from(`${header}.${claims}`), {
    key: createPrivateKey(pem),
    dsaEncoding: "ieee-p1363",
  });
  return `${header}.${claims}.${b64url(signature)}`;
}

async function revokeApple(code: string): Promise<void> {
  try {
    const secret = appleClientSecret();
    if (!secret) return;
    const post = (url: string, fields: Record<string, string>) =>
      fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ client_id: APPLE_BUNDLE_ID, client_secret: secret, ...fields }).toString(),
        signal: AbortSignal.timeout(6000),
      });
    const res = await post("https://appleid.apple.com/auth/token", { code, grant_type: "authorization_code" });
    if (!res.ok) return;
    const tokens = (await res.json()) as { refresh_token?: string; access_token?: string };
    const token = tokens.refresh_token ?? tokens.access_token;
    if (!token) return;
    await post("https://appleid.apple.com/auth/revoke", {
      token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    });
  } catch {
    /* best effort; see above */
  }
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

  // Only for an account that really signs in with Apple, and only a code
  // that looks like one.
  const appleCode = (body as { apple_authorization_code?: unknown }).apple_authorization_code;
  if (typeof appleCode === "string" && APPLE_CODE.test(appleCode) && user.identities?.some((i) => i.provider === "apple")) {
    await revokeApple(appleCode);
  }

  const admin = createClient(URL_, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });

  const emptyFolder = async () => {
    for (const bucket of BUCKETS) {
      try {
        for (let page = 0; page < 50; page++) {
          const { data: files } = await admin.storage.from(bucket).list(user.id, { limit: 100 });
          if (!files || files.length === 0) break;
          await admin.storage.from(bucket).remove(files.map((f) => `${user.id}/${f.name}`));
          if (files.length < 100) break;
        }
      } catch {
        /* best effort: orphaned files cost storage, not correctness (and the
           legal ones are ciphertext under a key the database never sees) */
      }
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
