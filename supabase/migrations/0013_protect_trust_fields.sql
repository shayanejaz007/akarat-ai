-- 0013_protect_trust_fields.sql
--
-- Found in the security audit (mobile/SECURITY_AUDIT.md, S1–S3). Additive and
-- safe to re-run. Review, then apply in the SQL Editor; nothing here deletes
-- or rewrites existing data.
--
-- 1. Row Level Security checks which ROWS a user may write, not which
--    columns. An owner could therefore set `verified` and `featured` on their
--    own listings, inflate its counters, and set `verified` or `role`
--    ('admin') on their own profile, straight through the REST API with the
--    public key. A trigger now keeps those columns as they were unless the
--    change comes from staff: the service role (the website's server routes)
--    or the database owner (the dashboard SQL editor, security-definer
--    functions such as handle_new_user).
--
-- 2. Two security-definer maintenance functions were executable by anyone,
--    because Postgres grants EXECUTE to PUBLIC by default and PostgREST
--    exposes functions as /rest/v1/rpc/<name>. expire_stale_external(0)
--    would mark every external listing "unknown". They are for the crawler,
--    which uses the service role, so execution is revoked from everyone else.

/* ── 1. Staff-only columns ─────────────────────────────────────────── */

create or replace function public.keep_staff_fields()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  is_staff boolean :=
    coalesce(auth.role(), '') = 'service_role'
    or current_user in ('postgres', 'supabase_admin', 'service_role');
begin
  if is_staff then
    return new;
  end if;

  if tg_table_name = 'properties' then
    if tg_op = 'INSERT' then
      new.verified        := false;
      new.featured        := false;
      new.views           := 0;
      new.saves           := 0;
      new.inquiries_count := 0;
    else
      new.verified        := old.verified;
      new.featured        := old.featured;
      new.views           := old.views;
      new.saves           := old.saves;
      new.inquiries_count := old.inquiries_count;
    end if;
  elsif tg_table_name = 'profiles' then
    if tg_op = 'INSERT' then
      new.role     := 'user';
      new.verified := false;
    else
      new.role     := old.role;
      new.verified := old.verified;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists properties_keep_staff_fields on public.properties;
create trigger properties_keep_staff_fields
  before insert or update on public.properties
  for each row execute function public.keep_staff_fields();

drop trigger if exists profiles_keep_staff_fields on public.profiles;
create trigger profiles_keep_staff_fields
  before insert or update on public.profiles
  for each row execute function public.keep_staff_fields();

/* ── 2. Maintenance functions: crawler only ────────────────────────── */

revoke all on function public.expire_stale_external(integer) from public, anon, authenticated;
revoke all on function public.group_external_duplicates() from public, anon, authenticated;
grant execute on function public.expire_stale_external(integer) to service_role;
grant execute on function public.group_external_duplicates() to service_role;

notify pgrst, 'reload schema';

/* ── Check, after applying (as a signed-in non-staff user, e.g. from the
   app's test account): an update setting verified = true on your own listing
   succeeds but leaves verified unchanged; calling
   /rest/v1/rpc/expire_stale_external with the publishable key returns 401/403. */
