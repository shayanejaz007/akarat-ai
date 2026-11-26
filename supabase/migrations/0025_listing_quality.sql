-- 0025_listing_quality.sql
--
-- Additive and safe to re-run. Review, then apply in the SQL Editor; nothing
-- here deletes or rewrites existing listings.
--
--   1. Price on request. An owner of a sale or monthly rental can choose not
--      to publish a price; the listing then shows "Price on request". The
--      price column stays NOT NULL (every query and index relies on it) and
--      holds 0 for these rows, so anything that filters, sorts or averages by
--      price must also look at price_on_request. Daily rentals always have a
--      nightly price: a booking is charged from it.
--
--   2. A listing quality score, 0–100. How complete and useful a listing is:
--      photos, description, both languages, the facts, the location, a
--      published price. It is worked out by the website's server
--      (lib/listing-score.js, through /api/listings/score and the nightly
--      maintenance run), because most of what it looks at lives in the
--      gzipped payload, which SQL cannot read. Owners cannot set it: the
--      staff-fields trigger keeps it as it was, like `verified`.
--      Buy, Rent, Daily rentals and Explore list the highest scores first.
--
--   3. Writing the score does not change updated_at, so "updated 3 days ago"
--      stays true to the owner's last edit. A row whose updated_at is later
--      than quality_scored_at was edited since it was scored.

/* ── 1. Price on request ───────────────────────────────────────────── */

alter table public.properties add column if not exists price_on_request boolean not null default false;

alter table public.properties drop constraint if exists properties_price_on_request_chk;
alter table public.properties add constraint properties_price_on_request_chk
  check (not price_on_request or (deal::text <> 'daily' and price_jod = 0));

-- The price is cleared when it is hidden, so an old figure cannot leak back
-- through the API, and a daily rental can never hide its nightly price.
create or replace function public.normalise_price_on_request()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.deal::text = 'daily' then
    new.price_on_request := false;
  end if;
  if new.price_on_request then
    new.price_jod := 0;
  end if;
  return new;
end;
$$;

drop trigger if exists properties_price_on_request on public.properties;
create trigger properties_price_on_request
  before insert or update on public.properties
  for each row execute function public.normalise_price_on_request();

/* ── 2. The quality score ──────────────────────────────────────────── */

alter table public.properties add column if not exists quality_score     smallint;
alter table public.properties add column if not exists quality_scored_at timestamptz;
-- What the score is made of, for the admin panel: { photos: 18, ... }.
alter table public.properties add column if not exists quality_parts     jsonb;

alter table public.properties drop constraint if exists properties_quality_score_chk;
alter table public.properties add constraint properties_quality_score_chk
  check (quality_score is null or quality_score between 0 and 100);

-- Highest score first, newest next: the order the marketplace lists in.
create index if not exists properties_quality_idx
  on public.properties (deal, status, quality_score desc nulls last, created_at desc);

-- Rows the server still has to score: never scored, or edited since.
create index if not exists properties_quality_stale_idx
  on public.properties (updated_at)
  where quality_scored_at is null;

-- Owners cannot write the score. Extends 0013's trigger function; the
-- profile branch and the counters are unchanged.
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
      new.verified          := false;
      new.featured          := false;
      new.views             := 0;
      new.saves             := 0;
      new.inquiries_count   := 0;
      new.quality_score     := null;
      new.quality_scored_at := null;
      new.quality_parts     := null;
    else
      new.verified          := old.verified;
      new.featured          := old.featured;
      new.views             := old.views;
      new.saves             := old.saves;
      new.inquiries_count   := old.inquiries_count;
      new.quality_score     := old.quality_score;
      new.quality_scored_at := old.quality_scored_at;
      new.quality_parts     := old.quality_parts;
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

/* ── 3. Scoring leaves updated_at alone ────────────────────────────── */

-- The same function 0018 and 0019 defined, with the score's columns added
-- to the ones that are not "the listing changing": a counter going up (a
-- view, a save, an inquiry) and now the score being written. The trigger
-- itself (properties_touch, 0001) is unchanged.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'properties'
     and to_jsonb(new) - array['views', 'saves', 'inquiries_count', 'updated_at',
                               'quality_score', 'quality_scored_at', 'quality_parts']
       = to_jsonb(old) - array['views', 'saves', 'inquiries_count', 'updated_at',
                               'quality_score', 'quality_scored_at', 'quality_parts'] then
    return new;
  end if;
  new.updated_at = now();
  return new;
end;
$$;

-- An earlier draft of this migration replaced the trigger with a function of
-- its own; put 0001's trigger back if that draft was ever run.
drop trigger if exists properties_touch on public.properties;
create trigger properties_touch
  before update on public.properties
  for each row execute function public.touch_updated_at();
drop function if exists public.touch_property_updated_at();

-- The new columns are readable like the rest of the row: 0005 grants select
-- on the whole table. Only the server writes the score (keep_staff_fields).

/* ── 4. What the server has to score ───────────────────────────────── */

-- Listings never scored, or edited since they were: the nightly run and the
-- save-time call work through these. PostgREST cannot compare two columns,
-- so this is a function. The server only.
create or replace function public.listings_to_score(p_limit integer default 200)
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id
    from public.properties
   where quality_scored_at is null
      or quality_scored_at < updated_at
   order by updated_at desc
   limit greatest(1, least(coalesce(p_limit, 200), 1000));
$$;

revoke all on function public.listings_to_score(integer) from public, anon, authenticated;
grant execute on function public.listings_to_score(integer) to service_role;
