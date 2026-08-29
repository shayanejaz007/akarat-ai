-- 0008_hardening.sql
--
-- Two production gaps closed:
--   1. an inquiry could be inserted with any owner_id, against any property
--   2. the AI search rate limit lived in a per-instance Map, so it never
--      actually limited anything once more than one instance was running

/* ── 1. Inquiries ─────────────────────────────────────────────────────
   The old policy was `with check (true)`: anyone could insert a row naming
   any owner and any property, including ones that do not exist. The owner_id
   is now required to be the real owner of a real, active listing, and the
   sender must be either anonymous or genuinely themselves. */

drop policy if exists "anyone may send an inquiry" on public.inquiries;
create policy "anyone may send an inquiry"
  on public.inquiries for insert
  with check (
    exists (
      select 1
        from public.properties p
       where p.id = inquiries.property_id
         and p.owner_id = inquiries.owner_id
         and p.status = 'active'
    )
    and (inquiries.sender_id is null or inquiries.sender_id = auth.uid())
  );

/* ── 2. Rate limiting ─────────────────────────────────────────────────
   A shared counter in Postgres, so every serverless instance sees the same
   number. One row per key per fixed minute window; old rows are cheap to
   sweep and harmless if left. Only the service role touches this table. */

create table if not exists public.rate_limits (
  key         text        not null,
  window_start timestamptz not null,
  hits        integer     not null default 0,
  primary key (key, window_start)
);

alter table public.rate_limits enable row level security;
-- No policies: RLS on with zero policies denies anon and authenticated
-- outright. The route reaches this only through the service role, which
-- bypasses RLS by design.
revoke all on public.rate_limits from anon, authenticated;

-- Returns true when the call is allowed. security definer so the route can
-- call it without granting table access to anybody.
create or replace function public.check_rate_limit(
  p_key text,
  p_limit integer,
  p_window_seconds integer default 60
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_window timestamptz;
  v_hits   integer;
begin
  v_window := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  insert into public.rate_limits (key, window_start, hits)
       values (p_key, v_window, 1)
  on conflict (key, window_start)
    do update set hits = public.rate_limits.hits + 1
    returning hits into v_hits;

  -- Opportunistic sweep: roughly one call in a hundred clears old windows.
  if random() < 0.01 then
    delete from public.rate_limits
     where window_start < now() - interval '1 hour';
  end if;

  return v_hits <= p_limit;
end;
$$;

revoke all on function public.check_rate_limit(text, integer, integer) from public, anon, authenticated;

notify pgrst, 'reload schema';
