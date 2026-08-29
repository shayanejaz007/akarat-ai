import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { type NextRequest, NextResponse } from "next/server";

// @supabase/ssr does not infer this parameter under `strict`, so it is typed
// explicitly. Without it `next build` fails on an implicit `any`.
type CookiesToSet = { name: string; value: string; options?: CookieOptions }[];

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
// Either name works: NEXT_PUBLIC_SUPABASE_ANON_KEY is what .env.example,
// the API routes and scripts/sync-public.mjs use; PUBLISHABLE_KEY was the
// original name here and is kept so existing deployments do not break.
const supabaseKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const updateSession = async (request: NextRequest) => {
  let supabaseResponse = NextResponse.next({ request: { headers: request.headers } });

  const supabase = createServerClient(supabaseUrl!, supabaseKey!, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet: CookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        supabaseResponse = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          supabaseResponse.cookies.set(name, value, options)
        );
      },
    },
  });

  // Touch the session so the refresh token rotates on every request.
  // Do not remove: without it, server components see a stale session.
  const { data: { user } } = await supabase.auth.getUser();

  // Gate the owner area server-side. Client-side checks are not access control.
  const path = request.nextUrl.pathname;
  const isProtected = path.startsWith("/dashboard") || path.startsWith("/list");
  if (isProtected && !user) {
    const url = request.nextUrl.clone();
    url.pathname = "/sign-in";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
};

export const createClient = updateSession;
