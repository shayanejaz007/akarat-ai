-- 0018_admin_analytics.sql
--
-- What the admin panel (akarat.ai/admin) reads that did not exist before:
--
--   1. property_views: one row per listing opened, from the website or the
--      app. properties.views existed since 0001 but nothing ever raised it.
--   2. app_sessions: one row per browser or app install, touched about once a
--      minute while it is open. "Live now" is every session seen in the last
--      two minutes; daily and weekly actives come from the same rows.
--   3. properties.inquiries_count and properties.saves kept up to date by
--      triggers, and recounted once here.
--   4. admin_overview() and admin_listing_stats(), the panel's aggregates.
--
-- Clients write only through record_view() and heartbeat(), which check their
-- input and cannot be pointed at anything else. Nobody reads these tables
-- through the API: the panel's server routes use the service role, and only
-- after checking that the caller's profile has role = 'admin'.
--
-- ADDITIVE ONLY, and safe to run more than once. Works whether or not
-- 0014 (favorites) and 0015 (listing_reports) have been applied.

/* ── 1. Views ─────────────────────────────────────────────────────────── */

create table if not exists public.property_views (
  id          bigint generated always as identity primary key,
  property_id uuid not null references public.properties (id) on delete cascade,
  session_id  text not null check (char_length(session_id) between 8 and 64),
  user_id     uuid references auth.users (id) on delete set null,
  platform    text not null check (platform in ('web', 'android', 'ios')),
  created_at  timestamptz not null default now()
);

create index if not exists property_views_property_idx on public.property_views (property_id, created_at desc);
create index if not exists property_views_created_idx  on public.property_views (created_at desc);
create index if not exists property_views_session_idx  on public.property_views (session_id, property_id, created_at desc);

/* ── 2. Sessions ──────────────────────────────────────────────────────── */

create table if not exists public.app_sessions (
  session_id  text primary key check (char_length(session_id) between 8 and 64),
  user_id     uuid references auth.users (id) on delete set null,
  platform    text not null check (platform in ('web', 'android', 'ios')),
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);

create index if not exists app_sessions_last_seen_idx on public.app_sessions (last_seen desc);

alter table public.property_views enable row level security;
alter table public.app_sessions   enable row level security;
-- No policies: not readable or writable through the API by anyone but the
-- service role. 0005's default privileges would otherwise hand them out.
revoke all on public.property_views from anon, authenticated, public;
revoke all on public.app_sessions   from anon, authenticated, public;
grant all on public.property_views to service_role;
grant all on public.app_sessions   to service_role;

/* ── 3. The two client entry points ───────────────────────────────────── */

-- A listing was opened. The same browser or install opening the same listing
-- again within 30 minutes is one view, not several: reloads and back-and-forth
-- would otherwise rank whatever people fiddle with most.
create or replace function public.record_view(p_property uuid, p_session text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_session is null or char_length(p_session) not between 8 and 64
     or p_platform not in ('web', 'android', 'ios') then
    return;
  end if;
  -- Only listings the public can see; nothing is learned about the rest.
  if not exists (select 1 from properties where id = p_property and status in ('active', 'sold', 'rented')) then
    return;
  end if;
  if exists (
    select 1 from property_views
    where session_id = p_session and property_id = p_property
      and created_at > now() - interval '30 minutes'
  ) then
    return;
  end if;

  insert into property_views (property_id, session_id, user_id, platform)
  values (p_property, p_session, auth.uid(), p_platform);
  -- Runs as the function owner, which keep_staff_fields (0013) lets through.
  update properties set views = views + 1 where id = p_property;
end;
$$;

-- Still here. Called on open and about once a minute while visible.
create or replace function public.heartbeat(p_session text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_session is null or char_length(p_session) not between 8 and 64
     or p_platform not in ('web', 'android', 'ios') then
    return;
  end if;
  insert into app_sessions (session_id, user_id, platform)
  values (p_session, auth.uid(), p_platform)
  on conflict (session_id) do update
    set last_seen = now(),
        -- Signing in attaches the session to the account; signing out keeps
        -- the last known one, so "who was active" stays answerable.
        user_id   = coalesce(excluded.user_id, app_sessions.user_id),
        platform  = excluded.platform;
end;
$$;

revoke all on function public.record_view(uuid, text, text) from public;
revoke all on function public.heartbeat(text, text) from public;
grant execute on function public.record_view(uuid, text, text) to anon, authenticated, service_role;
grant execute on function public.heartbeat(text, text) to anon, authenticated, service_role;

/* ── 4. Counters that follow their tables ─────────────────────────────── */

create or replace function public.count_inquiry()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    update properties set inquiries_count = inquiries_count + 1 where id = new.property_id;
  else
    update properties set inquiries_count = greatest(inquiries_count - 1, 0) where id = old.property_id;
  end if;
  return null;
end;
$$;

drop trigger if exists inquiries_count_trg on public.inquiries;
create trigger inquiries_count_trg
  after insert or delete on public.inquiries
  for each row execute function public.count_inquiry();

update public.properties p
set inquiries_count = (select count(*) from public.inquiries i where i.property_id = p.id);

do $$
begin
  if to_regclass('public.favorites') is null then
    return;
  end if;

  create or replace function public.count_save()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, pg_temp
  as $f$
  begin
    if tg_op = 'INSERT' then
      update properties set saves = saves + 1 where id = new.property_id;
    else
      update properties set saves = greatest(saves - 1, 0) where id = old.property_id;
    end if;
    return null;
  end;
  $f$;

  drop trigger if exists favorites_count_trg on public.favorites;
  create trigger favorites_count_trg
    after insert or delete on public.favorites
    for each row execute function public.count_save();

  update public.properties p
  set saves = (select count(*) from public.favorites f where f.property_id = p.id);
end $$;

/* ── 5. The panel's aggregates ────────────────────────────────────────── */

-- Everything on the overview in one round trip. Days are Amman days.
create or replace function public.admin_overview()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tz constant text := 'Asia/Amman';
  result jsonb;
  open_reports bigint := 0;
  total_saves bigint := 0;
begin
  if to_regclass('public.listing_reports') is not null then
    execute 'select count(*) from public.listing_reports where status = ''open''' into open_reports;
  end if;
  if to_regclass('public.favorites') is not null then
    execute 'select count(*) from public.favorites' into total_saves;
  end if;

  select jsonb_build_object(
    'live', (
      select jsonb_build_object(
        'total',   count(*),
        'web',     count(*) filter (where platform = 'web'),
        'android', count(*) filter (where platform = 'android'),
        'ios',     count(*) filter (where platform = 'ios'),
        'signedIn', count(*) filter (where user_id is not null)
      )
      from app_sessions where last_seen > now() - interval '2 minutes'
    ),
    'active', jsonb_build_object(
      'today', (select count(*) from app_sessions where last_seen >= date_trunc('day', now() at time zone tz) at time zone tz),
      'week',  (select count(*) from app_sessions where last_seen > now() - interval '7 days'),
      'month', (select count(*) from app_sessions where last_seen > now() - interval '30 days')
    ),
    'users', jsonb_build_object(
      'total',   (select count(*) from profiles),
      'week',    (select count(*) from profiles where created_at > now() - interval '7 days'),
      'admins',  (select count(*) from profiles where role = 'admin'),
      'owners',  (select count(distinct owner_id) from properties)
    ),
    'listings', (
      select jsonb_build_object(
        'total', count(*),
        'week',  count(*) filter (where created_at > now() - interval '7 days'),
        'byStatus', coalesce((
          select jsonb_object_agg(status, n) from (
            select status::text, count(*) n from properties group by status
          ) s
        ), '{}'::jsonb)
      )
      from properties
    ),
    'inquiries', jsonb_build_object(
      'total', (select count(*) from inquiries),
      'today', (select count(*) from inquiries where created_at >= date_trunc('day', now() at time zone tz) at time zone tz),
      'week',  (select count(*) from inquiries where created_at > now() - interval '7 days'),
      'new',   (select count(*) from inquiries where status = 'new')
    ),
    'views', jsonb_build_object(
      'total', (select coalesce(sum(views), 0) from properties),
      'today', (select count(*) from property_views where created_at >= date_trunc('day', now() at time zone tz) at time zone tz),
      'week',  (select count(*) from property_views where created_at > now() - interval '7 days')
    ),
    'saves', total_saves,
    'openReports', open_reports,
    -- The last 30 Amman days, oldest first, zero-filled.
    'daily', (
      select jsonb_agg(jsonb_build_object(
        'day', to_char(d, 'YYYY-MM-DD'),
        'views',     (select count(*) from property_views v where (v.created_at at time zone tz)::date = d),
        'inquiries', (select count(*) from inquiries i     where (i.created_at at time zone tz)::date = d),
        'signups',   (select count(*) from profiles p      where (p.created_at at time zone tz)::date = d),
        'listings',  (select count(*) from properties p    where (p.created_at at time zone tz)::date = d),
        -- Distinct browsers and installs that opened at least one listing.
        'viewers',   (select count(distinct v.session_id) from property_views v where (v.created_at at time zone tz)::date = d)
      ) order by d)
      from generate_series((now() at time zone tz)::date - 29, (now() at time zone tz)::date, interval '1 day') g(d0),
           lateral (select g.d0::date as d) x
    ),
    'topViewed', coalesce((
      select jsonb_agg(t order by t.n desc) from (
        select v.property_id as id, p.title_en, p.title_ar, p.status, count(*) as n
        from property_views v join properties p on p.id = v.property_id
        where v.created_at > now() - interval '30 days'
        group by v.property_id, p.title_en, p.title_ar, p.status
        order by count(*) desc limit 10
      ) t
    ), '[]'::jsonb),
    'topInquired', coalesce((
      select jsonb_agg(t order by t.n desc) from (
        select i.property_id as id, p.title_en, p.title_ar, p.status, count(*) as n
        from inquiries i join properties p on p.id = i.property_id
        where i.created_at > now() - interval '30 days'
        group by i.property_id, p.title_en, p.title_ar, p.status
        order by count(*) desc limit 10
      ) t
    ), '[]'::jsonb),
    'byCity', coalesce((
      select jsonb_agg(t order by t.n desc) from (
        select coalesce(c.name_en, 'Unknown') as city, count(*) as n
        from properties p left join cities c on c.id = p.city_id
        group by c.name_en
      ) t
    ), '[]'::jsonb),
    'generatedAt', now()
  ) into result;

  return result;
end;
$$;

-- Views per listing over the last 7 and 30 days, for the listings table.
create or replace function public.admin_listing_stats(p_ids uuid[])
returns table (property_id uuid, views_7d bigint, views_30d bigint, last_inquiry timestamptz)
language sql
security definer
set search_path = public, pg_temp
as $$
  select u.pid,
    (select count(*) from property_views v where v.property_id = u.pid and v.created_at > now() - interval '7 days'),
    (select count(*) from property_views v where v.property_id = u.pid and v.created_at > now() - interval '30 days'),
    (select max(i.created_at) from inquiries i where i.property_id = u.pid)
  from unnest(p_ids) as u(pid);
$$;

-- When each user was last seen, on any device.
create or replace function public.admin_last_seen(p_ids uuid[])
returns table (user_id uuid, last_seen timestamptz, platform text)
language sql
security definer
set search_path = public, pg_temp
as $$
  select distinct on (s.user_id) s.user_id, s.last_seen, s.platform
  from app_sessions s
  where s.user_id = any (p_ids)
  order by s.user_id, s.last_seen desc;
$$;

revoke all on function public.admin_overview() from public, anon, authenticated;
revoke all on function public.admin_listing_stats(uuid[]) from public, anon, authenticated;
revoke all on function public.admin_last_seen(uuid[]) from public, anon, authenticated;
grant execute on function public.admin_overview() to service_role;
grant execute on function public.admin_listing_stats(uuid[]) to service_role;
grant execute on function public.admin_last_seen(uuid[]) to service_role;

notify pgrst, 'reload schema';

-- The panel at /admin signs in with ADMIN_PASSWORD (Vercel), not an account
-- role; its routes call these functions with the service role.
