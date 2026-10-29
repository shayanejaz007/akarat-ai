-- 0019_daily_rentals.sql
--
-- Daily rentals: short stays priced per night, kept apart from Buy and Rent.
--
--   1. properties.deal gains 'daily'. A daily listing lives in the same table,
--      so photos, location, translation, favourites, reports and view counts
--      work unchanged, but nobody else can see it until an admin approves it:
--      properties.daily_review is 'pending', 'approved', 'rejected' or
--      'suspended', and only staff (the admin panel's service role) can change
--      it. Buy and Rent never show one: they ask for deal = 'sale' or 'rent'.
--   2. daily_blocked_days: nights the owner has closed.
--   3. booking_requests: a renter asks for dates and a number of guests. The
--      owner approves or rejects. The owner's phone reaches the renter only
--      on approval, written onto that request by booking_respond(). A request
--      the owner marks confirmed blocks its nights, and two confirmed stays
--      can never overlap: an exclusion constraint, not a check in the apps.
--   4. notifications: one row per thing a person should hear about, written
--      by triggers here and read live by the website and the app.
--
-- Errors meant for people are raised as short keys (daily_unavailable,
-- daily_min_nights, ...) that the website and the app translate, with any
-- number in DETAIL.
--
-- Run it whole in the SQL Editor. Safe to run more than once. Nothing here
-- changes an existing sale or rent listing.

/* ── 1. The deal type and the review columns ─────────────────────────── */

alter type public.deal_type add value if not exists 'daily';

-- The new enum value cannot be used as a literal in the transaction that
-- adds it, so everything below compares deal::text instead.

alter table public.properties add column if not exists daily_review      text;
alter table public.properties add column if not exists daily_review_note text;
alter table public.properties add column if not exists daily_reviewed_at timestamptz;
-- Set when the owner edits an approved listing's text, photos or place, so
-- the admin panel can show what changed since it was checked.
alter table public.properties add column if not exists daily_changed_at  timestamptz;
alter table public.properties add column if not exists max_guests        smallint;
alter table public.properties add column if not exists min_nights        smallint;

alter table public.properties drop constraint if exists properties_daily_review_chk;
alter table public.properties add constraint properties_daily_review_chk
  check (daily_review in ('pending', 'approved', 'rejected', 'suspended'));

alter table public.properties drop constraint if exists properties_daily_fields_chk;
alter table public.properties add constraint properties_daily_fields_chk check (
  (max_guests is null or max_guests between 1 and 50)
  and (min_nights is null or min_nights between 1 and 30)
  and (daily_review_note is null or char_length(daily_review_note) <= 500)
);

create index if not exists properties_daily_review_idx
  on public.properties (daily_review, created_at desc)
  where daily_review is not null;

-- Who may move a daily listing through review, and what an owner's edit does
-- to it. Staff, as in 0013: the service role or the database owner.
create or replace function public.guard_daily_review()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  is_staff boolean :=
    coalesce(auth.role(), '') = 'service_role'
    or current_user in ('postgres', 'supabase_admin', 'service_role');
  edited boolean;
begin
  if new.deal::text <> 'daily' then
    -- Not (or no longer) a daily listing: it carries no review. Switching
    -- back to daily later starts the review again.
    if not is_staff then
      new.daily_review      := null;
      new.daily_review_note := null;
      new.daily_reviewed_at := null;
      new.daily_changed_at  := null;
      -- A daily approval is not a verified sale or rent listing.
      if tg_op = 'UPDATE' and old.deal::text = 'daily' then
        new.verified := false;
      end if;
    end if;
    return new;
  end if;

  if is_staff then
    if tg_op = 'INSERT' then
      new.daily_review := coalesce(new.daily_review, 'pending');
    elsif new.daily_review is distinct from old.daily_review then
      new.daily_reviewed_at := now();
      new.daily_changed_at  := null;
    end if;
    -- The badge the rest of the site already shows means the same thing.
    new.verified := new.daily_review = 'approved';
    return new;
  end if;

  -- The owner. A new daily listing, or one switched to daily, waits for review.
  if tg_op = 'INSERT' or old.deal::text <> 'daily' then
    new.daily_review      := 'pending';
    new.daily_review_note := null;
    new.daily_reviewed_at := null;
    new.daily_changed_at  := null;
    new.verified          := false;
    return new;
  end if;

  new.daily_review      := old.daily_review;
  new.daily_review_note := old.daily_review_note;
  new.daily_reviewed_at := old.daily_reviewed_at;
  new.daily_changed_at  := old.daily_changed_at;

  -- Price, guests, minimum stay and pause/resume are the owner's to change
  -- freely. What a reviewer looked at is the words, the photos and the place.
  edited := row(new.title_en, new.title_ar, new.property_type, new.city_id, new.neighborhood_id,
                new.lat, new.lng, new.bedrooms, new.bathrooms, new.area_sqm, new.land_sqm,
                new.payload_gz, new.address)
            is distinct from
            row(old.title_en, old.title_ar, old.property_type, old.city_id, old.neighborhood_id,
                old.lat, old.lng, old.bedrooms, old.bathrooms, old.area_sqm, old.land_sqm,
                old.payload_gz, old.address);
  if edited then
    if old.daily_review = 'rejected' then
      -- Fixing a rejected listing sends it back for review.
      new.daily_review      := 'pending';
      new.daily_review_note := null;
    elsif old.daily_review = 'approved' then
      new.daily_changed_at := now();
    end if;
  end if;
  return new;
end;
$$;

-- Named to run after properties_keep_staff_fields (0013), which would
-- otherwise put back the verified flag this sets: triggers on one table fire
-- in name order. It only ever lowers verified for an owner, never raises it.
drop trigger if exists properties_review_daily on public.properties;
create trigger properties_review_daily
  before insert or update on public.properties
  for each row execute function public.guard_daily_review();

-- Public: live sale and rent listings as before, and daily ones only once
-- approved. Owners still read all of their own (0001).
drop policy if exists "active and closed listings are public" on public.properties;
create policy "active and closed listings are public"
  on public.properties for select
  using (
    status in ('active', 'sold', 'rented')
    and (deal::text <> 'daily' or daily_review = 'approved')
  );

-- A view of a listing nobody may see yet is not a view.
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
  if not exists (
    select 1 from properties
    where id = p_property and status in ('active', 'sold', 'rented')
      and (deal::text <> 'daily' or daily_review = 'approved')
  ) then
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
  update properties set views = views + 1 where id = p_property;
end;
$$;

-- Repeated from 0018 for databases that ran it before the fix: a counter
-- going up is not the listing changing.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'properties'
     and to_jsonb(new) - array['views', 'saves', 'inquiries_count', 'updated_at']
       = to_jsonb(old) - array['views', 'saves', 'inquiries_count', 'updated_at'] then
    return new;
  end if;
  new.updated_at = now();
  return new;
end;
$$;

/* ── 2. Nights the owner has closed ───────────────────────────────────── */

create table if not exists public.daily_blocked_days (
  property_id uuid not null references public.properties (id) on delete cascade,
  day         date not null,
  created_at  timestamptz not null default now(),
  primary key (property_id, day)
);

alter table public.daily_blocked_days enable row level security;

drop policy if exists "owners manage their blocked days" on public.daily_blocked_days;
create policy "owners manage their blocked days"
  on public.daily_blocked_days for all
  using (exists (select 1 from public.properties p where p.id = property_id and p.owner_id = auth.uid()))
  with check (exists (select 1 from public.properties p where p.id = property_id and p.owner_id = auth.uid()));

revoke all on public.daily_blocked_days from anon, public;
grant select, insert, delete on public.daily_blocked_days to authenticated;
grant all on public.daily_blocked_days to service_role;

/* ── 3. Booking requests ──────────────────────────────────────────────── */

-- In Supabase the extensions schema already exists; elsewhere it is made.
create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;

create table if not exists public.booking_requests (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties (id) on delete cascade,
  owner_id      uuid not null references auth.users (id) on delete cascade,
  renter_id     uuid not null references auth.users (id) on delete cascade,
  renter_name   text not null check (char_length(renter_name) between 1 and 120),
  check_in      date not null,
  check_out     date not null,
  nights        integer generated always as (check_out - check_in) stored,
  guests        smallint not null check (guests between 1 and 50),
  message       text check (message is null or char_length(message) <= 2000),
  -- The price when it was asked for, so a later price change cannot rewrite
  -- what the renter was shown.
  nightly_price integer not null check (nightly_price >= 0),
  total_price   integer not null check (total_price >= 0),
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'rejected', 'cancelled', 'confirmed')),
  -- Only ever set while approved or confirmed.
  owner_phone   text,
  response_note text check (response_note is null or char_length(response_note) <= 500),
  -- Set when the system closed the request rather than a person:
  -- 'dates_taken' when another stay was confirmed over these nights.
  closed_reason text check (closed_reason in ('dates_taken')),
  cancelled_by  text check (cancelled_by in ('renter', 'owner')),
  responded_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (check_out > check_in),
  check (check_out - check_in <= 90)
);

create index if not exists booking_requests_owner_idx    on public.booking_requests (owner_id, created_at desc);
create index if not exists booking_requests_renter_idx   on public.booking_requests (renter_id, created_at desc);
create index if not exists booking_requests_property_idx on public.booking_requests (property_id, check_in);

-- Two confirmed stays on the same nights cannot both exist, whoever writes.
alter table public.booking_requests drop constraint if exists booking_requests_no_overlap;
alter table public.booking_requests add constraint booking_requests_no_overlap
  exclude using gist (property_id with =, daterange(check_in, check_out, '[)') with &&)
  where (status = 'confirmed');

alter table public.booking_requests enable row level security;

drop policy if exists "renters and owners read their requests" on public.booking_requests;
create policy "renters and owners read their requests"
  on public.booking_requests for select
  using (auth.uid() = renter_id or auth.uid() = owner_id);

drop policy if exists "signed-in renters ask as themselves" on public.booking_requests;
create policy "signed-in renters ask as themselves"
  on public.booking_requests for insert to authenticated
  with check (auth.uid() = renter_id);

-- No update or delete through the API: every change goes through
-- booking_respond(), which knows who may do what.
revoke all on public.booking_requests from anon, public;
grant select, insert on public.booking_requests to authenticated;
grant all on public.booking_requests to service_role;

-- Free for these nights: none closed by the owner, none in a confirmed stay.
-- check_out is the morning of leaving, so that night is not needed.
create or replace function public.daily_is_available(p_property uuid, p_check_in date, p_check_out date)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_check_out > p_check_in
     and not exists (
       select 1 from daily_blocked_days b
       where b.property_id = p_property and b.day >= p_check_in and b.day < p_check_out)
     and not exists (
       select 1 from booking_requests r
       where r.property_id = p_property and r.status = 'confirmed'
         and daterange(r.check_in, r.check_out, '[)') && daterange(p_check_in, p_check_out, '[)'));
$$;

-- The nights a calendar should grey out, without saying why or for whom.
-- Only for a listing the caller may see. At most about a year at a time.
create or replace function public.daily_unavailable_days(p_property uuid, p_from date, p_to date)
returns date[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with visible as (
    select 1 from properties p
    where p.id = p_property and p.deal::text = 'daily'
      and (p.owner_id = auth.uid() or (p.status = 'active' and p.daily_review = 'approved'))
  ),
  span as (
    select p_from as f, least(p_to, p_from + 400) as t
  ),
  days as (
    select b.day
    from daily_blocked_days b, span
    where b.property_id = p_property and b.day >= span.f and b.day < span.t
    union
    select g::date
    from booking_requests r, span,
         generate_series(greatest(r.check_in, span.f)::timestamp,
                         (least(r.check_out, span.t) - 1)::timestamp, interval '1 day') g
    where r.property_id = p_property and r.status = 'confirmed'
      and r.check_in < span.t and r.check_out > span.f
  )
  select coalesce(array_agg(day order by day), '{}')
  from days
  where exists (select 1 from visible);
$$;

-- Approved daily listings, optionally only those free for the dates asked
-- and big enough for the party. Runs as the caller, so the read policy above
-- still decides what comes back; filter, sort and page it like a table.
create or replace function public.search_daily_rentals(
  p_check_in  date default null,
  p_check_out date default null,
  p_guests    integer default null
)
returns setof public.properties
language sql
stable
set search_path = public, pg_temp
as $$
  select p.*
  from properties p
  where p.deal::text = 'daily'
    and p.status = 'active'
    and p.daily_review = 'approved'
    and (p_guests is null or coalesce(p.max_guests, 50) >= p_guests)
    and (p_check_in is null or p_check_out is null or (
          p_check_out - p_check_in >= coalesce(p.min_nights, 1)
          and daily_is_available(p.id, p_check_in, p_check_out)));
$$;

-- Everything about a new request that the renter does not get to decide.
create or replace function public.prepare_booking_request()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  p     properties%rowtype;
  today date := (now() at time zone 'Asia/Amman')::date;
  n     integer;
begin
  select * into p from properties where id = new.property_id;
  if not found or p.deal::text <> 'daily' or p.status <> 'active' or p.daily_review is distinct from 'approved' then
    raise exception 'daily_not_bookable';
  end if;
  if p.owner_id = new.renter_id then
    raise exception 'daily_own_listing';
  end if;
  if new.check_in is null or new.check_out is null or new.check_out <= new.check_in then
    raise exception 'daily_bad_dates';
  end if;
  if new.check_in < today then
    raise exception 'daily_past_dates';
  end if;
  if new.check_in > today + 365 then
    raise exception 'daily_too_far';
  end if;
  n := new.check_out - new.check_in;
  if n < coalesce(p.min_nights, 1) then
    raise exception 'daily_min_nights' using detail = coalesce(p.min_nights, 1)::text;
  end if;
  if n > 90 then
    raise exception 'daily_max_nights' using detail = '90';
  end if;
  if new.guests is null or new.guests < 1 then
    raise exception 'daily_bad_guests';
  end if;
  if new.guests > coalesce(p.max_guests, 50) then
    raise exception 'daily_max_guests' using detail = coalesce(p.max_guests, 50)::text;
  end if;
  if not daily_is_available(p.id, new.check_in, new.check_out) then
    raise exception 'daily_unavailable';
  end if;
  if exists (
    select 1 from booking_requests
    where property_id = p.id and renter_id = new.renter_id
      and status in ('pending', 'approved') and check_out > today
  ) then
    raise exception 'daily_open_request';
  end if;
  if (select count(*) from booking_requests
      where renter_id = new.renter_id and created_at > now() - interval '1 day') >= 15 then
    raise exception 'daily_too_many';
  end if;

  new.owner_id      := p.owner_id;
  new.nightly_price := p.price_jod;
  new.total_price   := p.price_jod * n;
  new.status        := 'pending';
  new.owner_phone   := null;
  new.response_note := null;
  new.closed_reason := null;
  new.cancelled_by  := null;
  new.responded_at  := null;
  new.created_at    := now();
  new.updated_at    := now();
  new.message       := nullif(left(btrim(coalesce(new.message, '')), 2000), '');
  new.renter_name   := left(coalesce(
    nullif(btrim(new.renter_name), ''),
    nullif(btrim((select full_name from profiles where id = new.renter_id)), ''),
    'Guest'), 120);
  return new;
end;
$$;

drop trigger if exists booking_requests_prepare on public.booking_requests;
create trigger booking_requests_prepare
  before insert on public.booking_requests
  for each row execute function public.prepare_booking_request();

-- The one way a request changes.
--   owner:  approve (with the phone to share), reject, confirm (after
--           approving: the stay is agreed and its nights close), cancel
--           (an approved or confirmed one)
--   renter: cancel (a pending, approved or confirmed one)
create or replace function public.booking_respond(
  p_request uuid,
  p_action  text,
  p_phone   text default null,
  p_note    text default null
)
returns public.booking_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r     booking_requests%rowtype;
  me    uuid := auth.uid();
  today date := (now() at time zone 'Asia/Amman')::date;
  phone text;
  note  text := nullif(left(btrim(coalesce(p_note, '')), 500), '');
begin
  if me is null then
    raise exception 'daily_sign_in';
  end if;
  select * into r from booking_requests where id = p_request for update;
  if not found or (r.owner_id <> me and r.renter_id <> me) then
    raise exception 'daily_request_missing';
  end if;

  if r.renter_id = me and r.owner_id <> me then
    if p_action <> 'cancel' then
      raise exception 'daily_not_yours';
    end if;
    if r.status not in ('pending', 'approved', 'confirmed') then
      raise exception 'daily_request_closed';
    end if;
    update booking_requests
       set status = 'cancelled', cancelled_by = 'renter', owner_phone = null, updated_at = now()
     where id = r.id
     returning * into r;
    return r;
  end if;

  -- The owner.
  if p_action = 'approve' then
    if r.status <> 'pending' then
      raise exception 'daily_request_closed';
    end if;
    if r.check_in < today then
      raise exception 'daily_past_dates';
    end if;
    phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
    if phone !~ '^\+?[0-9]{7,15}$' then
      raise exception 'daily_phone_needed';
    end if;
    if not daily_is_available(r.property_id, r.check_in, r.check_out) then
      raise exception 'daily_unavailable';
    end if;
    update booking_requests
       set status = 'approved', owner_phone = phone, response_note = note,
           responded_at = now(), updated_at = now()
     where id = r.id
     returning * into r;

  elsif p_action = 'reject' then
    if r.status not in ('pending', 'approved') then
      raise exception 'daily_request_closed';
    end if;
    update booking_requests
       set status = 'rejected', owner_phone = null, response_note = note,
           responded_at = now(), updated_at = now()
     where id = r.id
     returning * into r;

  elsif p_action = 'confirm' then
    if r.status <> 'approved' then
      raise exception 'daily_request_closed';
    end if;
    begin
      update booking_requests
         set status = 'confirmed', updated_at = now()
       where id = r.id
       returning * into r;
    exception when exclusion_violation then
      raise exception 'daily_unavailable';
    end;
    -- Anyone else still asking for any of these nights is told they went.
    update booking_requests
       set status = 'rejected', owner_phone = null, closed_reason = 'dates_taken',
           responded_at = now(), updated_at = now()
     where property_id = r.property_id and id <> r.id
       and status in ('pending', 'approved')
       and daterange(check_in, check_out, '[)') && daterange(r.check_in, r.check_out, '[)');

  elsif p_action = 'cancel' then
    if r.status not in ('approved', 'confirmed') then
      raise exception 'daily_request_closed';
    end if;
    update booking_requests
       set status = 'cancelled', cancelled_by = 'owner', owner_phone = null,
           response_note = coalesce(note, response_note), updated_at = now()
     where id = r.id
     returning * into r;

  else
    raise exception 'daily_bad_action';
  end if;
  return r;
end;
$$;

revoke all on function public.daily_is_available(uuid, date, date) from public;
revoke all on function public.daily_unavailable_days(uuid, date, date) from public;
revoke all on function public.search_daily_rentals(date, date, integer) from public;
revoke all on function public.booking_respond(uuid, text, text, text) from public, anon;
grant execute on function public.daily_is_available(uuid, date, date) to anon, authenticated, service_role;
grant execute on function public.daily_unavailable_days(uuid, date, date) to anon, authenticated, service_role;
grant execute on function public.search_daily_rentals(date, date, integer) to anon, authenticated, service_role;
grant execute on function public.booking_respond(uuid, text, text, text) to authenticated, service_role;

/* ── 4. Notifications ─────────────────────────────────────────────────── */

create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  -- booking_new, booking_approved, booking_rejected, booking_confirmed,
  -- booking_cancelled, listing_approved, listing_rejected,
  -- listing_suspended, listing_unapproved. The apps word each one.
  kind        text not null,
  property_id uuid references public.properties (id) on delete cascade,
  booking_id  uuid references public.booking_requests (id) on delete cascade,
  data        jsonb not null default '{}',
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists "people read their own notifications" on public.notifications;
create policy "people read their own notifications"
  on public.notifications for select using (auth.uid() = user_id);

drop policy if exists "people mark their own notifications read" on public.notifications;
create policy "people mark their own notifications read"
  on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "people clear their own notifications" on public.notifications;
create policy "people clear their own notifications"
  on public.notifications for delete using (auth.uid() = user_id);

revoke all on public.notifications from anon, public, authenticated;
grant select, delete on public.notifications to authenticated;
-- Marking read is the only change a person can make.
grant update (read_at) on public.notifications to authenticated;
grant all on public.notifications to service_role;

create or replace function public.notify_booking()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  p    properties%rowtype;
  data jsonb;
begin
  select * into p from properties where id = new.property_id;
  data := jsonb_build_object(
    'title_en', p.title_en, 'title_ar', p.title_ar,
    'check_in', new.check_in, 'check_out', new.check_out,
    'guests', new.guests, 'renter_name', new.renter_name,
    'note', new.response_note, 'reason', new.closed_reason);

  if tg_op = 'INSERT' then
    insert into notifications (user_id, kind, property_id, booking_id, data)
    values (new.owner_id, 'booking_new', new.property_id, new.id, data);
    return null;
  end if;

  if new.status is not distinct from old.status then
    return null;
  end if;
  if new.status in ('approved', 'rejected', 'confirmed') then
    insert into notifications (user_id, kind, property_id, booking_id, data)
    values (new.renter_id, 'booking_' || new.status, new.property_id, new.id, data);
  elsif new.status = 'cancelled' then
    insert into notifications (user_id, kind, property_id, booking_id, data)
    values (case when new.cancelled_by = 'renter' then new.owner_id else new.renter_id end,
            'booking_cancelled', new.property_id, new.id, data || jsonb_build_object('by', new.cancelled_by));
  end if;
  return null;
end;
$$;

drop trigger if exists booking_requests_notify on public.booking_requests;
create trigger booking_requests_notify
  after insert or update on public.booking_requests
  for each row execute function public.notify_booking();

create or replace function public.notify_daily_review()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  kind text;
begin
  if new.deal::text <> 'daily' or new.daily_review is not distinct from old.daily_review then
    return null;
  end if;
  kind := case
    when new.daily_review = 'approved'  then 'listing_approved'
    when new.daily_review = 'rejected'  then 'listing_rejected'
    when new.daily_review = 'suspended' then 'listing_suspended'
    -- An approval taken back. A rejected listing the owner fixed goes back
    -- to pending too, and that one they did themselves.
    when new.daily_review = 'pending' and old.daily_review = 'approved' then 'listing_unapproved'
  end;
  if kind is null then
    return null;
  end if;
  insert into notifications (user_id, kind, property_id, data)
  values (new.owner_id, kind, new.id, jsonb_build_object(
    'title_en', new.title_en, 'title_ar', new.title_ar, 'note', new.daily_review_note));
  return null;
end;
$$;

drop trigger if exists properties_notify_daily_review on public.properties;
create trigger properties_notify_daily_review
  after update of daily_review on public.properties
  for each row execute function public.notify_daily_review();

-- Live updates in the apps. Realtime still applies the read policies above.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.notifications;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.booking_requests;
    exception when duplicate_object then null;
    end;
  end if;
end $$;

/* ── 5. For the admin panel ───────────────────────────────────────────── */

create or replace function public.admin_daily_overview()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'review', jsonb_build_object(
      'pending',   (select count(*) from properties where deal::text = 'daily' and daily_review = 'pending'),
      'approved',  (select count(*) from properties where deal::text = 'daily' and daily_review = 'approved'),
      'rejected',  (select count(*) from properties where deal::text = 'daily' and daily_review = 'rejected'),
      'suspended', (select count(*) from properties where deal::text = 'daily' and daily_review = 'suspended'),
      'changed',   (select count(*) from properties where deal::text = 'daily' and daily_review = 'approved'
                                                       and daily_changed_at is not null),
      'live',      (select count(*) from properties where deal::text = 'daily' and daily_review = 'approved'
                                                       and status = 'active')),
    'requests', jsonb_build_object(
      'total',     (select count(*) from booking_requests),
      'pending',   (select count(*) from booking_requests where status = 'pending'),
      'approved',  (select count(*) from booking_requests where status = 'approved'),
      'confirmed', (select count(*) from booking_requests where status = 'confirmed'),
      'week',      (select count(*) from booking_requests where created_at > now() - interval '7 days'),
      'nightsConfirmed', (select coalesce(sum(nights), 0) from booking_requests where status = 'confirmed'))
  );
$$;

revoke all on function public.admin_daily_overview() from public, anon, authenticated;
grant execute on function public.admin_daily_overview() to service_role;

notify pgrst, 'reload schema';
