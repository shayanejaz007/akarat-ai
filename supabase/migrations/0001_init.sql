-- Akarat.ai — initial schema
-- Run this in the Supabase SQL editor (Database → SQL Editor → New query).
-- Safe to re-run: every object is created with IF NOT EXISTS or replaced.

create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────────────────────
-- Canonical locations. Referenced by id everywhere else so place
-- names are never free text, and both languages stay in sync.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.cities (
  id          text primary key,
  name_en     text not null,
  name_ar     text not null,
  lat         double precision,
  lng         double precision,
  created_at  timestamptz not null default now()
);

create table if not exists public.neighborhoods (
  id          text primary key,
  city_id     text not null references public.cities (id) on delete cascade,
  name_en     text not null,
  name_ar     text not null,
  lat         double precision,
  lng         double precision,
  aliases     text[] not null default '{}',
  created_at  timestamptz not null default now()
);

create index if not exists neighborhoods_city_idx on public.neighborhoods (city_id);

-- ─────────────────────────────────────────────────────────────
-- Profiles. One row per auth user, created automatically by the
-- trigger below so a profile always exists after sign-up.
-- ─────────────────────────────────────────────────────────────
do $$ begin
  create type public.user_role as enum ('user', 'property_owner', 'agent', 'admin');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text,
  phone       text,
  locale      text not null default 'en',
  role        public.user_role not null default 'user',
  agency      text,
  verified    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'locale', 'en')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- Properties.
--
-- Columns hold only what the database must filter, sort or index on.
-- Everything bulky and free-form (both descriptions, amenity list,
-- image metadata, contact preferences) is gzipped client-side and
-- stored once in `payload_gz` as base64 text. That keeps rows small
-- and search fast, and means adding a field to the listing form
-- never needs a migration.
-- ─────────────────────────────────────────────────────────────
do $$ begin
  create type public.listing_status as enum
    ('draft', 'pending', 'active', 'rejected', 'paused', 'sold', 'rented', 'archived');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.deal_type as enum ('sale', 'rent');
exception when duplicate_object then null; end $$;

create table if not exists public.properties (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users (id) on delete cascade,

  status          public.listing_status not null default 'draft',
  deal            public.deal_type not null,
  property_type   text not null,

  city_id         text references public.cities (id) on delete set null,
  neighborhood_id text references public.neighborhoods (id) on delete set null,
  lat             double precision,
  lng             double precision,

  price_jod       integer not null check (price_jod >= 0),
  bedrooms        smallint check (bedrooms >= 0),
  bathrooms       smallint check (bathrooms >= 0),
  area_sqm        integer check (area_sqm >= 0),
  land_sqm        integer check (land_sqm >= 0),
  year_built      smallint,

  title_en        text not null,
  title_ar        text,

  verified        boolean not null default false,
  featured        boolean not null default false,

  -- gzip(JSON) as base64. See lib/supabase.js → packPayload / unpackPayload.
  payload_gz      text,
  payload_bytes   integer,
  raw_bytes       integer,

  views           integer not null default 0,
  saves           integer not null default 0,
  inquiries_count integer not null default 0,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  published_at    timestamptz
);

create index if not exists properties_owner_idx   on public.properties (owner_id);
create index if not exists properties_status_idx  on public.properties (status);
create index if not exists properties_search_idx  on public.properties (status, deal, city_id, price_jod);
create index if not exists properties_created_idx on public.properties (created_at desc);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists properties_touch on public.properties;
create trigger properties_touch
  before update on public.properties
  for each row execute function public.touch_updated_at();

-- ─────────────────────────────────────────────────────────────
-- Inquiries against a listing.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.inquiries (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  sender_id    uuid references auth.users (id) on delete set null,
  owner_id     uuid not null references auth.users (id) on delete cascade,
  name         text not null,
  email        text,
  phone        text,
  message      text not null,
  status       text not null default 'new',
  created_at   timestamptz not null default now()
);

create index if not exists inquiries_owner_idx    on public.inquiries (owner_id, created_at desc);
create index if not exists inquiries_property_idx on public.inquiries (property_id);

-- ─────────────────────────────────────────────────────────────
-- Saved AI searches.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.saved_searches (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  label       text not null,
  constraints jsonb not null,
  created_at  timestamptz not null default now()
);

create index if not exists saved_searches_user_idx on public.saved_searches (user_id, created_at desc);

-- ─────────────────────────────────────────────────────────────
-- Row Level Security.
--
-- Nothing below trusts the browser. A client may only ever read
-- active listings plus its own rows, and may only write rows whose
-- owner_id equals its own auth.uid().
-- ─────────────────────────────────────────────────────────────
alter table public.profiles       enable row level security;
alter table public.properties     enable row level security;
alter table public.inquiries      enable row level security;
alter table public.saved_searches enable row level security;
alter table public.cities         enable row level security;
alter table public.neighborhoods  enable row level security;

drop policy if exists "cities readable by anyone" on public.cities;
create policy "cities readable by anyone"
  on public.cities for select using (true);

drop policy if exists "neighborhoods readable by anyone" on public.neighborhoods;
create policy "neighborhoods readable by anyone"
  on public.neighborhoods for select using (true);

drop policy if exists "profiles are self readable" on public.profiles;
create policy "profiles are self readable"
  on public.profiles for select using (auth.uid() = id);

drop policy if exists "profiles are self writable" on public.profiles;
create policy "profiles are self writable"
  on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "active listings are public" on public.properties;
create policy "active listings are public"
  on public.properties for select using (status = 'active');

drop policy if exists "owners read their own listings" on public.properties;
create policy "owners read their own listings"
  on public.properties for select using (auth.uid() = owner_id);

drop policy if exists "owners create their own listings" on public.properties;
create policy "owners create their own listings"
  on public.properties for insert with check (auth.uid() = owner_id);

drop policy if exists "owners update their own listings" on public.properties;
create policy "owners update their own listings"
  on public.properties for update using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "owners delete their own listings" on public.properties;
create policy "owners delete their own listings"
  on public.properties for delete using (auth.uid() = owner_id);

drop policy if exists "owners read inquiries on their listings" on public.inquiries;
create policy "owners read inquiries on their listings"
  on public.inquiries for select using (auth.uid() = owner_id or auth.uid() = sender_id);

drop policy if exists "anyone may send an inquiry" on public.inquiries;
create policy "anyone may send an inquiry"
  on public.inquiries for insert with check (true);

drop policy if exists "saved searches are private" on public.saved_searches;
create policy "saved searches are private"
  on public.saved_searches for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────
-- Canonical Jordanian locations.
-- ─────────────────────────────────────────────────────────────
insert into public.cities (id, name_en, name_ar, lat, lng) values
  ('amman',   'Amman',    'عمان',        31.953, 35.910),
  ('aqaba',   'Aqaba',    'العقبة',      29.532, 35.006),
  ('irbid',   'Irbid',    'إربد',        32.556, 35.847),
  ('zarqa',   'Zarqa',    'الزرقاء',     32.072, 36.088),
  ('madaba',  'Madaba',   'مادبا',       31.716, 35.795),
  ('salt',    'Salt',     'السلط',       32.038, 35.727),
  ('jerash',  'Jerash',   'جرش',         32.282, 35.896),
  ('deadsea', 'Dead Sea', 'البحر الميت', 31.502, 35.583),
  ('fuheis',  'Fuheis',   'الفحيص',      32.008, 35.774)
on conflict (id) do nothing;

insert into public.neighborhoods (id, city_id, name_en, name_ar, lat, lng, aliases) values
  ('abdoun',      'amman', 'Abdoun',        'عبدون',        31.936, 35.879, '{abdon,abdoon}'),
  ('sweifieh',    'amman', 'Sweifieh',      'الصويفية',     31.949, 35.867, '{swaifieh,sweifiyeh,swefieh}'),
  ('khalda',      'amman', 'Khalda',        'خلدا',         31.987, 35.826, '{khaldah}'),
  ('dabouq',      'amman', 'Dabouq',        'دابوق',        31.986, 35.786, '{daboug,dabuq}'),
  ('jabalamman',  'amman', 'Jabal Amman',   'جبل عمان',     31.951, 35.925, '{"jabal al amman"}'),
  ('deirghbar',   'amman', 'Deir Ghbar',    'دير غبار',     31.945, 35.858, '{"dair ghbar"}'),
  ('umuthaina',   'amman', 'Um Uthaina',    'أم أذينة',     31.964, 35.872, '{"umm uthaina"}'),
  ('shmeisani',   'amman', 'Shmeisani',     'الشميساني',    31.968, 35.905, '{shmaisani}'),
  ('airportrd',   'amman', 'Airport Road',  'طريق المطار',  31.855, 35.950, '{}'),
  ('tlaalali',    'amman', 'Tla'' Al Ali',  'تلاع العلي',   31.987, 35.862, '{"tlaa al ali","tla al ali"}'),
  ('jubaiha',     'amman', 'Al Jubaiha',    'الجبيهة',      32.020, 35.874, '{jubeiha}'),
  ('marj',        'amman', 'Marj Al Hamam', 'مرج الحمام',   31.888, 35.836, '{}'),
  ('tabarbour',   'amman', 'Tabarbour',     'طبربور',       32.020, 35.945, '{}'),
  ('southbeach',  'aqaba', 'South Beach',   'الشاطئ الجنوبي', 29.451, 34.986, '{}'),
  ('aqabacentre', 'aqaba', 'Aqaba Centre',  'وسط العقبة',   29.529, 35.006, '{}')
on conflict (id) do nothing;
