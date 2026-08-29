import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";

// Typed explicitly: @supabase/ssr leaves this parameter uninferred under
// `strict`, which fails the build on an implicit `any`.
type CookiesToSet = { name: string; value: string; options?: CookieOptions }[];

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
// Either name works: NEXT_PUBLIC_SUPABASE_ANON_KEY is what .env.example,
// the API routes and scripts/sync-public.mjs use; PUBLISHABLE_KEY was the
// original name here and is kept so existing deployments do not break.
const supabaseKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const createClient = (cookieStore: Awaited<ReturnType<typeof cookies>>) => {
  return createServerClient(supabaseUrl!, supabaseKey!, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet: CookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options)
          );
        } catch {
          // Called from a Server Component. Safe to ignore while the
          // middleware below is refreshing sessions.
        }
      },
    },
  });
};
