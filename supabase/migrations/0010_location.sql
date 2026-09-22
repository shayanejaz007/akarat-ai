-- 0010_location.sql
--
-- Puts a real point on a listing, and keeps the owner in charge of how
-- precisely that point is published.
--
-- Closes the gap README calls out: "Owners cannot yet hide exact coordinates
-- behind an approximate location. Build that before publishing real
-- listings."
--
-- ── Why two places for one pair of coordinates ─────────────────────────
-- RLS on `properties` is "active listings are public". That is a row-level
-- rule, not a column-level one: every column of an active listing is readable
-- by the anon key, lat and lng included. So an exact coordinate stored on
-- `properties` is a published coordinate, whatever the UI chooses to draw.
--
-- Hence the split:
--
--   properties.lat / lng        what the world may see. Exact when the owner
--                               said exact; displaced by up to ~300 m when
--                               they said approximate.
--   property_locations.lat/lng  the truth. Readable by its owner and no one
--                               else, enforced below rather than in the app.
--
-- Safe to run more than once, and safe to run on a database with listings in
-- it: existing rows keep their coordinates and default to 'approximate',
-- which is the conservative answer for a row nobody has made a choice about.

-- ── 1. How precisely this listing is published ─────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'location_precision') then
    create type public.location_precision as enum ('exact', 'approximate');
  end if;
end $$;

alter table public.properties
  add column if not exists location_precision public.location_precision
    not null default 'approximate';

-- Free-text address, shown only when the owner publishes an exact pin. Kept
-- as a column rather than in payload_gz because it is worth searching on.
alter table public.properties
  add column if not exists address text;

comment on column public.properties.lat is
  'Publishable latitude: exact, or displaced ~300 m when location_precision = approximate. Never assume this is the real point.';
comment on column public.properties.lng is
  'Publishable longitude. See lat.';

-- ── 2. The exact point, owner-only ─────────────────────────────────────
create table if not exists public.property_locations (
  property_id uuid primary key
    references public.properties (id) on delete cascade,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  lat         double precision not null,
  lng         double precision not null,
  -- What Google returned, kept so a re-geocode can be compared against the
  -- original rather than silently overwriting a pin the owner corrected.
  place_id    text,
  address     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

drop trigger if exists property_locations_touch on public.property_locations;
create trigger property_locations_touch
  before update on public.property_locations
  for each row execute function public.touch_updated_at();

alter table public.property_locations enable row level security;

-- No "active listings are public" policy here, deliberately. The only way to
-- read an exact coordinate is to own it.
drop policy if exists "owners read their own exact locations" on public.property_locations;
create policy "owners read their own exact locations"
  on public.property_locations for select using (auth.uid() = owner_id);

drop policy if exists "owners write their own exact locations" on public.property_locations;
create policy "owners write their own exact locations"
  on public.property_locations for insert with check (auth.uid() = owner_id);

drop policy if exists "owners update their own exact locations" on public.property_locations;
create policy "owners update their own exact locations"
  on public.property_locations for update
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "owners delete their own exact locations" on public.property_locations;
create policy "owners delete their own exact locations"
  on public.property_locations for delete using (auth.uid() = owner_id);

-- ── 3. Grants ──────────────────────────────────────────────────────────
grant select, insert, update, delete on public.property_locations to authenticated;

-- And now take away what this table was given without being asked.
--
-- 0005_grants.sql ends with:
--
--   alter default privileges in schema public
--     grant select on tables to anon, authenticated;
--
-- which means every table created after it starts life with SELECT already
-- granted to `anon` — this one included. `profiles` and `saved_searches`
-- predate that statement, which is why a signed-out read of those is refused
-- outright while a read of this table returned an empty list instead.
--
-- Nothing was exposed: RLS has no policy that matches a null auth.uid(), so
-- the answer was correctly no rows. But it left the most sensitive table in
-- the schema resting on a single control. Two things would turn that into a
-- disclosure: someone adding a policy here that reads more permissively than
-- they realised, or RLS being disabled for a minute during debugging. On a
-- table of exact home addresses, neither is a risk worth carrying for the
-- sake of a grant nobody wanted.
--
-- Revoked from PUBLIC too, so a role added later does not inherit it either.
revoke all on public.property_locations from anon;
revoke all on public.property_locations from public;

-- ── 4. Index ───────────────────────────────────────────────────────────
-- Map-bounds queries ("everything in this viewport") read lat and lng
-- together with status, which is always filtered first.
create index if not exists properties_geo_idx
  on public.properties (status, lat, lng)
  where lat is not null;

notify pgrst, 'reload schema';
