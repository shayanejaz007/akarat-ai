-- 0005_grants.sql
--
-- Row Level Security decides which ROWS a caller may see. It never grants
-- access to the table itself. Without an explicit GRANT, PostgREST answers
-- every read with 403 "permission denied" before a policy is ever evaluated.
--
-- Supabase normally applies these grants automatically, but a table created
-- by a role other than `postgres`, or one created before default privileges
-- were set, misses them. Running this file is safe either way: grants are
-- idempotent.

-- The two roles PostgREST uses: `anon` for signed-out visitors, and
-- `authenticated` for anyone with a session.
grant usage on schema public to anon, authenticated;

-- Reads. RLS still narrows these to the rows each policy allows: active
-- listings for everyone, own listings for their owner.
grant select on public.properties            to anon, authenticated;
grant select on public.cities                to anon, authenticated;
grant select on public.neighborhoods         to anon, authenticated;
grant select on public.external_properties   to anon, authenticated;
grant select on public.external_sources      to anon, authenticated;

-- Writes, allowed only where a policy also allows the row.
grant insert, update, delete on public.properties to authenticated;
grant select, insert, update, delete on public.profiles       to authenticated;
grant select, insert on public.inquiries      to anon, authenticated;
grant select, insert, update, delete on public.saved_searches to authenticated;

-- The deduplicated view from 0003. A view carries its own privileges.
grant select on public.external_properties_grouped to anon, authenticated;

-- Anything added later inherits the same shape.
alter default privileges in schema public
  grant select on tables to anon, authenticated;

-- PostgREST caches the schema. Tell it to reload, otherwise a table added a
-- moment ago keeps answering 400 until the next restart.
notify pgrst, 'reload schema';
