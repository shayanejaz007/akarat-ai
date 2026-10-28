-- 0017_service_role_grants.sql
--
-- Gives the service role the table privileges Supabase normally grants it on
-- its own, and which this project's tables never received.
--
-- ── How it showed up ──────────────────────────────────────────────────
-- /api/admin/backfill-translations, reading listings with
-- SUPABASE_SERVICE_ROLE_KEY, got:
--
--     403  42501  permission denied for table properties
--
-- The service role bypasses Row Level Security, but RLS only filters rows; a
-- role still needs a GRANT to touch the table at all (see 0005_grants.sql,
-- which wrote the grants out for anon and authenticated and not for this
-- role). Every server-side caller using the key was affected:
--
--   - the shared search rate limiter (check_rate_limit), which on a refusal
--     falls back to its weaker per-instance counter, so searches kept working
--     and nobody noticed;
--   - the crawler (/api/admin/crawl), writing external_properties;
--   - the translation backfill, and any other server code reading or
--     writing tables with the key.
--
-- ── Why granting everything is right here ────────────────────────────────
-- The service-role key is already, by design, the key that may do anything:
-- it bypasses RLS and lives only in Vercel's server environment. Withholding
-- table grants from it protects nothing — anyone holding the key holds the
-- project — and only breaks the server code meant to use it. This is the
-- default every new Supabase project ships with.
--
-- Safe to run more than once, and it touches no rows.

grant usage on schema public to service_role;

grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Tables, sequences and functions created later get the same.
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

notify pgrst, 'reload schema';

/* ── Check, after applying ─────────────────────────────────────────────
   With the service-role key:

     GET /rest/v1/properties?select=id&limit=1        -> 200 (was 403 42501)
     POST /rest/v1/rpc/check_rate_limit               -> 200 true/false

   Nothing changes for the publishable key or for signed-in users: no grant to
   anon or authenticated is touched. */
