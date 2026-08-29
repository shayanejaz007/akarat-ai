-- Akarat.ai — external property index
--
-- Run after 0001_init.sql.
--
-- This is the table that makes search work the way a search engine works:
-- crawlers fill it on a schedule, and a user's search reads only from here.
-- Nobody waits for a third-party site during a search.

create extension if not exists "pg_trgm";

-- Approved sources. A crawler will not touch a host that is not listed here
-- and enabled, which is also where robots.txt and rate limits are recorded.
create table if not exists public.external_sources (
  id                text primary key,
  name              text not null,
  host              text not null,
  kind              text not null default 'known_marketplace',
  confidence        numeric(3,2) not null default 0.70,
  enabled           boolean not null default false,
  robots_checked_at timestamptz,
  crawl_delay_ms    integer not null default 2000,
  requests_per_hour integer not null default 600,
  terms_reviewed    boolean not null default false,
  notes             text,
  created_at        timestamptz not null default now()
);

comment on column public.external_sources.enabled is
  'Off until robots.txt and the site terms have been reviewed for this host.';
comment on column public.external_sources.confidence is
  'Confidence in the SOURCE, not in any individual property.';

create table if not exists public.external_properties (
  id                  uuid primary key default gen_random_uuid(),
  source_id           text not null references public.external_sources (id) on delete cascade,
  source_listing_id   text,
  source_url          text not null,

  title               text not null,
  description         text,

  price               integer,
  currency            text not null default 'JOD',
  transaction_type    public.deal_type,
  property_type       text,

  bedrooms            smallint,
  bathrooms           smallint,
  area_sqm            integer,

  city_id             text references public.cities (id) on delete set null,
  neighborhood_id     text references public.neighborhoods (id) on delete set null,
  latitude            double precision,
  longitude           double precision,

  image_url           text,

  -- Freshness. Presented to the user as "checked today", never as "available".
  source_published_at timestamptz,
  first_discovered_at timestamptz not null default now(),
  last_checked_at     timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  availability_status text not null default 'unknown',

  -- Cross-source grouping. Set when a duplicate is detected with confidence;
  -- left null when uncertain, so the listings stay separate rather than merged.
  dedupe_group        uuid,

  raw_metadata        jsonb,

  unique (source_id, source_listing_id)
);

-- The indexes a query actually uses: filter by the columns, not the blob.
create index if not exists ext_props_search_idx
  on public.external_properties (transaction_type, city_id, price)
  where availability_status <> 'unavailable';
create index if not exists ext_props_hood_idx    on public.external_properties (neighborhood_id);
create index if not exists ext_props_seen_idx    on public.external_properties (last_seen_at desc);
create index if not exists ext_props_group_idx   on public.external_properties (dedupe_group);
-- trigram index for fuzzy title matching during deduplication
create index if not exists ext_props_title_trgm  on public.external_properties using gin (title gin_trgm_ops);

alter table public.external_properties enable row level security;
alter table public.external_sources    enable row level security;

-- Readable by anyone, writable only by the service role (the crawler).
-- No policy grants insert or update, so the publishable key cannot write here.
drop policy if exists "external listings are public" on public.external_properties;
create policy "external listings are public"
  on public.external_properties for select using (true);

drop policy if exists "sources are public" on public.external_sources;
create policy "sources are public"
  on public.external_sources for select using (true);

-- A listing missing from its source for long enough stops being presented as
-- current. Run from the same schedule as the crawler.
create or replace function public.expire_stale_external(stale_days integer default 21)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  update public.external_properties
     set availability_status = 'unknown'
   where availability_status = 'likely_available'
     and last_seen_at < now() - (stale_days || ' days')::interval;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Seed the two portals whose URL grammar is already confirmed. Both start
-- disabled: enable a source only after reviewing its robots.txt and terms.
insert into public.external_sources (id, name, host, kind, confidence, enabled, notes) values
  ('opensooq', 'OpenSooq Jordan', 'jo.opensooq.com', 'known_marketplace', 0.86, false,
   'Search-URL grammar verified. Check robots.txt and terms before enabling; prefer an official feed.'),
  ('bayut',    'Bayut Jordan',    'www.bayut.jo',   'known_marketplace', 0.86, false,
   'Search-URL grammar verified, including neighbourhood paths. Same review required.')
on conflict (id) do nothing;
