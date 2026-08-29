import { createBrowserClient } from "@supabase/ssr";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
// Either name works: NEXT_PUBLIC_SUPABASE_ANON_KEY is what .env.example,
// the API routes and scripts/sync-public.mjs use; PUBLISHABLE_KEY was the
// original name here and is kept so existing deployments do not break.
const supabaseKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const createClient = () => createBrowserClient(supabaseUrl!, supabaseKey!);
