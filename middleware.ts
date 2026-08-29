import { type NextRequest } from "next/server";
import { updateSession } from "@/utils/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    // Only the routes that need a session. The marketplace document itself is
    // static and public, so running an auth round-trip in front of it added a
    // Supabase call to every cold page load and bought nothing.
    "/api/:path*",
    "/dashboard/:path*",
    "/list/:path*",
  ],
};
