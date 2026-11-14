-- 0024_services.sql
--
-- Services: household maintenance and property services people can ask for
-- (plumbing, electrical, air conditioning, cleaning…). For now an admin
-- handles every request by hand: nothing here sets a price, names a
-- contractor or takes a payment.
--
--   1. service_categories: what can be asked for. Managed from the admin
--      panel (names in both languages, examples, an icon, order, on/off), so
--      a new category needs no app release. Everyone reads the active ones.
--   2. service_requests: one per request, private. Nobody reads or writes
--      the table through the API: people create, list and cancel their own
--      through the functions in 4, and the admin panel works through the
--      service role after its own password check.
--   3. service_request_events: each request's history (created, every
--      status change, notes, assignment), each marked as shown to the
--      customer or kept for admins. Internal notes are never shown.
--   4. create_service_request(), my_service_requests(),
--      cancel_service_request(): the customer's side. They check every
--      field, keep one request per client_token (a retried submission gets
--      the first one back), and cap how many a person can send in a day.
--   5. admin_service_update(): the admin panel's side. A status, a note (for
--      the customer or internal) and an assignment, in one transaction,
--      written to the history and to the customer's notifications.
--   6. The service-photos bucket: private, images only, 8 MB each. People
--      upload only into their own folder; photos are read back through
--      signed URLs.
--   7. Notifications (0019's table): the customer hears about every status
--      change and every note meant for them; accounts with the admin role
--      hear about every new and every cancelled request.
--   8. admin_services_overview(): the admin panel's counts.
--
-- Needs 0019 (notifications) and 0023 (governorates). ADDITIVE ONLY, and
-- safe to run more than once.

/* ── 1. Categories ────────────────────────────────────────────────────── */

create table if not exists public.service_categories (
  id          text primary key check (id ~ '^[a-z0-9][a-z0-9_-]{1,40}$'),
  name_en     text not null check (char_length(name_en) between 1 and 60),
  name_ar     text not null check (char_length(name_ar) between 1 and 60),
  examples_en text not null default '' check (char_length(examples_en) <= 200),
  examples_ar text not null default '' check (char_length(examples_ar) <= 200),
  -- One of the icons every platform draws: plumbing, bathroom, electrical,
  -- ac, painting, carpentry, cleaning, appliance, water, maintenance,
  -- renovation, pest, moving, custom. An unknown one falls back to a toolbox.
  icon        text not null default 'maintenance' check (icon ~ '^[a-z]{2,20}$'),
  sort        integer not null default 100,
  active      boolean not null default true,
  -- The "something else" category: the person names the service themselves.
  custom      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.service_categories enable row level security;
drop policy if exists "active service categories are public" on public.service_categories;
create policy "active service categories are public" on public.service_categories for select using (active);
revoke all on public.service_categories from anon, authenticated, public;
grant select on public.service_categories to anon, authenticated;
grant all on public.service_categories to service_role;

-- The starting list. On a second run nothing is overwritten: what an admin
-- has changed since stays changed.
insert into public.service_categories (id, name_en, name_ar, examples_en, examples_ar, icon, sort, custom) values
  ('plumbing',    'Plumbing',            'السباكة',              'Water leaks, blocked drains, pipe repairs',  'تسريب المياه، انسداد المصارف، إصلاح الأنابيب',  'plumbing',    10,  false),
  ('bathroom',    'Bathroom repairs',    'إصلاحات الحمّامات',     'Toilets, showers, faucets',                  'المراحيض، الدش، الحنفيات',                       'bathroom',    20,  false),
  ('electrical',  'Electrical',          'الكهرباء',             'Wiring, switches, lights, sockets',          'التمديدات، المفاتيح، الإنارة، المقابس',           'electrical',  30,  false),
  ('ac',          'Air conditioning',    'التكييف',              'AC repair, servicing, installation',         'إصلاح المكيفات وصيانتها وتركيبها',               'ac',          40,  false),
  ('painting',    'Painting',            'الدهان',               'Interior and exterior painting',             'دهان داخلي وخارجي',                              'painting',    50,  false),
  ('carpentry',   'Carpentry',           'النجارة',              'Doors, cabinets, furniture repairs',         'الأبواب، الخزائن، إصلاح الأثاث',                  'carpentry',   60,  false),
  ('cleaning',    'Cleaning',            'التنظيف',              'Home, apartment and deep cleaning',          'تنظيف المنازل والشقق والتنظيف العميق',           'cleaning',    70,  false),
  ('appliances',  'Appliance repair',    'صيانة الأجهزة المنزلية', 'Washing machines, refrigerators, ovens',     'الغسالات، الثلاجات، الأفران',                     'appliance',   80,  false),
  ('water',       'Water systems',       'أنظمة المياه',          'Water tanks, pumps, heaters',                'خزانات المياه، المضخات، السخانات',                'water',       90,  false),
  ('maintenance', 'General maintenance', 'صيانة عامة',           'Handyman services, minor repairs',           'أعمال الصيانة والإصلاحات البسيطة',                'maintenance', 100, false),
  ('renovation',  'Renovation',          'الترميم والتجديد',      'Kitchen, bathroom and interior renovation',  'تجديد المطابخ والحمّامات والديكور الداخلي',        'renovation',  110, false),
  ('pest',        'Pest control',        'مكافحة الحشرات',        'Pest treatment for homes and buildings',     'رش الحشرات ومكافحة القوارض في المنازل والمباني',   'pest',        120, false),
  ('moving',      'Moving services',     'خدمات النقل',           'Moving and furniture transport',             'نقل العفش والأثاث',                              'moving',      130, false),
  ('custom',      'Custom service',      'خدمة أخرى',            'Something not listed here',                  'خدمة غير موجودة في القائمة',                     'custom',      999, true)
on conflict (id) do nothing;

/* ── 2. Requests ──────────────────────────────────────────────────────── */

create sequence if not exists public.service_request_seq;

create table if not exists public.service_requests (
  id               uuid primary key default gen_random_uuid(),
  -- What people quote on the phone: SR-000123.
  ref              text not null unique default ('SR-' || lpad(nextval('public.service_request_seq')::text, 6, '0')),
  user_id          uuid not null references auth.users (id) on delete cascade,
  -- One per submission attempt: a retry after a dropped connection sends the
  -- same token and gets the first request back instead of a second one.
  client_token     uuid not null,
  category_id      text not null references public.service_categories (id) on update cascade,
  custom_service   text check (custom_service is null or char_length(custom_service) between 2 and 80),
  description      text not null check (char_length(description) between 10 and 4000),
  governorate_id   text not null references public.governorates (id) on update cascade,
  city_id          text not null references public.cities (id) on update cascade,
  neighborhood_id  text references public.neighborhoods (id) on update cascade on delete set null,
  address          text not null check (char_length(address) between 3 and 300),
  lat              double precision check (lat is null or lat between 29 and 33.5),
  lng              double precision check (lng is null or lng between 34.8 and 39.5),
  preferred_date   date not null,
  preferred_window text not null default 'any' check (preferred_window in ('morning', 'afternoon', 'evening', 'any')),
  urgency          text not null default 'normal' check (urgency in ('normal', 'urgent', 'emergency')),
  -- Paths in the private service-photos bucket, each in the requester's folder.
  photos           text[] not null default '{}' check (cardinality(photos) <= 6),
  contact_name     text not null check (char_length(contact_name) between 2 and 120),
  contact_phone    text not null check (char_length(contact_phone) between 7 and 24),
  contact_email    text check (contact_email is null or char_length(contact_email) <= 200),
  status           text not null default 'pending'
                   check (status in ('pending', 'under_review', 'accepted', 'in_progress', 'completed', 'rejected', 'cancelled')),
  -- An admin account looking after it. Never shown to the customer.
  assigned_to      uuid references auth.users (id) on delete set null,
  cancel_reason    text check (cancel_reason is null or char_length(cancel_reason) <= 500),
  lang             text not null default 'ar' check (lang in ('ar', 'en')),
  platform         text check (platform in ('web', 'android', 'ios')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  status_at        timestamptz not null default now(),
  check ((lat is null) = (lng is null)),
  unique (user_id, client_token)
);

create index if not exists service_requests_user_idx     on public.service_requests (user_id, created_at desc);
create index if not exists service_requests_status_idx   on public.service_requests (status, created_at desc);
create index if not exists service_requests_category_idx on public.service_requests (category_id, created_at desc);
create index if not exists service_requests_city_idx     on public.service_requests (city_id);

alter table public.service_requests enable row level security;
-- No policies: the table is not readable or writable through the API.
revoke all on public.service_requests from anon, authenticated, public;
grant all on public.service_requests to service_role;
revoke all on sequence public.service_request_seq from anon, authenticated, public;
grant usage on sequence public.service_request_seq to service_role;

/* ── 3. History ───────────────────────────────────────────────────────── */

create table if not exists public.service_request_events (
  id          bigint generated always as identity primary key,
  request_id  uuid not null references public.service_requests (id) on delete cascade,
  at          timestamptz not null default now(),
  kind        text not null check (kind in ('created', 'status', 'note', 'assigned')),
  from_status text,
  to_status   text,
  note        text check (note is null or char_length(note) <= 1000),
  -- Shown to the customer. Internal notes and assignments never are.
  public      boolean not null default false,
  actor       text not null check (actor in ('customer', 'admin', 'system'))
);

create index if not exists service_request_events_request_idx on public.service_request_events (request_id, at);

alter table public.service_request_events enable row level security;
revoke all on public.service_request_events from anon, authenticated, public;
grant all on public.service_request_events to service_role;

/* ── 7. Notifications point at a request ──────────────────────────────── */

alter table public.notifications
  add column if not exists service_request_id uuid references public.service_requests (id) on delete cascade;
create index if not exists notifications_service_request_idx on public.notifications (service_request_id) where service_request_id is not null;

/* ── 4. The customer's side ───────────────────────────────────────────── */

-- What a notification about a request carries, so each app can word it in
-- the reader's language without another round trip.
create or replace function public.service_note_data(r public.service_requests)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'ref', r.ref, 'status', r.status, 'urgency', r.urgency,
    'category_en', coalesce(r.custom_service, c.name_en), 'category_ar', coalesce(r.custom_service, c.name_ar))
  from service_categories c where c.id = r.category_id;
$$;

create or replace function public.create_service_request(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid       uuid := auth.uid();
  tok       uuid;
  cat       service_categories%rowtype;
  prior     service_requests%rowtype;
  r         service_requests%rowtype;
  v_custom  text := nullif(btrim(coalesce(p->>'custom_service', '')), '');
  v_desc    text := btrim(coalesce(p->>'description', ''));
  v_gov     text := nullif(p->>'governorate_id', '');
  v_city    text := nullif(p->>'city_id', '');
  v_hood    text := nullif(p->>'neighborhood_id', '');
  v_address text := btrim(coalesce(p->>'address', ''));
  v_lat     double precision;
  v_lng     double precision;
  v_date    date;
  v_window  text := coalesce(nullif(p->>'preferred_window', ''), 'any');
  v_urgency text := coalesce(nullif(p->>'urgency', ''), 'normal');
  v_name    text := btrim(coalesce(p->>'contact_name', ''));
  v_phone   text := btrim(coalesce(p->>'contact_phone', ''));
  v_email   text := nullif(lower(btrim(coalesce(p->>'contact_email', ''))), '');
  v_photos  text[] := '{}';
  v_today   date := (now() at time zone 'Asia/Amman')::date;
  item      jsonb;
begin
  if uid is null then
    raise exception 'sign_in';
  end if;

  begin
    tok := (p->>'client_token')::uuid;
  exception when others then
    raise exception 'invalid:client_token';
  end;
  if tok is null then
    raise exception 'invalid:client_token';
  end if;

  -- The same submission again (a retry after a dropped connection): the
  -- first request, not a second one.
  select * into prior from service_requests where user_id = uid and client_token = tok;
  if found then
    return jsonb_build_object('id', prior.id, 'ref', prior.ref, 'status', prior.status,
                              'created_at', prior.created_at, 'duplicate', true);
  end if;

  if (select count(*) from service_requests where user_id = uid and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'too_many';
  end if;

  select * into cat from service_categories where id = p->>'category_id' and active;
  if not found then
    raise exception 'invalid:category_id';
  end if;
  if cat.custom then
    if v_custom is null or char_length(v_custom) not between 2 and 80 then
      raise exception 'invalid:custom_service';
    end if;
  else
    v_custom := null;
  end if;

  if char_length(v_desc) not between 10 and 4000 then
    raise exception 'invalid:description';
  end if;

  if v_gov is null or not exists (select 1 from governorates where id = v_gov and active) then
    raise exception 'invalid:governorate_id';
  end if;
  if v_city is null or not exists (select 1 from cities where id = v_city and governorate_id = v_gov and active) then
    raise exception 'invalid:city_id';
  end if;
  if v_hood is not null and not exists (select 1 from neighborhoods where id = v_hood and city_id = v_city and active) then
    raise exception 'invalid:neighborhood_id';
  end if;
  if char_length(v_address) not between 3 and 300 then
    raise exception 'invalid:address';
  end if;

  if (p ? 'lat' and jsonb_typeof(p->'lat') = 'number') or (p ? 'lng' and jsonb_typeof(p->'lng') = 'number') then
    begin
      v_lat := (p->>'lat')::double precision;
      v_lng := (p->>'lng')::double precision;
    exception when others then
      raise exception 'invalid:lat';
    end;
    if v_lat is null or v_lng is null or v_lat not between 29 and 33.5 or v_lng not between 34.8 and 39.5 then
      raise exception 'invalid:lat';
    end if;
  end if;

  begin
    v_date := (p->>'preferred_date')::date;
  exception when others then
    raise exception 'invalid:preferred_date';
  end;
  if v_date is null or v_date < v_today or v_date > v_today + 180 then
    raise exception 'invalid:preferred_date';
  end if;
  if v_window not in ('morning', 'afternoon', 'evening', 'any') then
    raise exception 'invalid:preferred_window';
  end if;
  if v_urgency not in ('normal', 'urgent', 'emergency') then
    raise exception 'invalid:urgency';
  end if;

  if jsonb_typeof(coalesce(p->'photos', '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p->'photos', '[]'::jsonb)) > 6 then
    raise exception 'invalid:photos';
  end if;
  for item in select * from jsonb_array_elements(coalesce(p->'photos', '[]'::jsonb)) loop
    -- Only files in the requester's own folder of the private bucket.
    if jsonb_typeof(item) <> 'string'
       or (item #>> '{}') !~ ('^' || uid::text || '/[A-Za-z0-9][A-Za-z0-9._-]{0,119}$') then
      raise exception 'invalid:photos';
    end if;
    v_photos := v_photos || (item #>> '{}');
  end loop;
  if cardinality(v_photos) > 0 and to_regclass('storage.objects') is not null then
    if (select count(*) from storage.objects o where o.bucket_id = 'service-photos' and o.name = any (v_photos))
       < cardinality(v_photos) then
      raise exception 'invalid:photos';
    end if;
  end if;

  if char_length(v_name) not between 2 and 120 then
    raise exception 'invalid:contact_name';
  end if;
  if v_phone !~ '^\+?[0-9][0-9 ()-]{5,22}$' or char_length(regexp_replace(v_phone, '[^0-9]', '', 'g')) not between 7 and 15 then
    raise exception 'invalid:contact_phone';
  end if;
  if v_email is not null and (char_length(v_email) > 200 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    raise exception 'invalid:contact_email';
  end if;

  insert into service_requests (
    user_id, client_token, category_id, custom_service, description,
    governorate_id, city_id, neighborhood_id, address, lat, lng,
    preferred_date, preferred_window, urgency, photos,
    contact_name, contact_phone, contact_email, lang, platform
  ) values (
    uid, tok, cat.id, v_custom, v_desc,
    v_gov, v_city, v_hood, v_address, v_lat, v_lng,
    v_date, v_window, v_urgency, v_photos,
    v_name, v_phone, v_email,
    case when p->>'lang' = 'en' then 'en' else 'ar' end,
    case when p->>'platform' in ('web', 'android', 'ios') then p->>'platform' end
  )
  returning * into r;

  insert into service_request_events (request_id, kind, to_status, public, actor)
  values (r.id, 'created', 'pending', true, 'customer');

  -- Every admin account hears about it at once.
  insert into notifications (user_id, kind, service_request_id, data)
  select pr.id, 'service_new', r.id, service_note_data(r)
  from profiles pr where pr.role = 'admin';

  return jsonb_build_object('id', r.id, 'ref', r.ref, 'status', r.status,
                            'created_at', r.created_at, 'duplicate', false);
end;
$$;

create or replace function public.my_service_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'sign_in';
  end if;
  return coalesce((
    select jsonb_agg(t.item order by t.created_at desc)
    from (
      select r.created_at, jsonb_build_object(
        'id', r.id, 'ref', r.ref, 'status', r.status,
        'category_id', r.category_id, 'category_en', c.name_en, 'category_ar', c.name_ar, 'icon', c.icon,
        'custom_service', r.custom_service, 'description', r.description,
        'governorate_id', r.governorate_id, 'city_id', r.city_id, 'neighborhood_id', r.neighborhood_id,
        'address', r.address, 'lat', r.lat, 'lng', r.lng,
        'preferred_date', r.preferred_date, 'preferred_window', r.preferred_window,
        'urgency', r.urgency, 'photos', to_jsonb(r.photos),
        'contact_name', r.contact_name, 'contact_phone', r.contact_phone, 'contact_email', r.contact_email,
        'cancel_reason', r.cancel_reason,
        'created_at', r.created_at, 'updated_at', r.updated_at, 'status_at', r.status_at,
        'cancellable', r.status in ('pending', 'under_review', 'accepted'),
        'events', coalesce((
          select jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'status', e.to_status, 'note', e.note, 'by', e.actor)
                           order by e.at, e.id)
          from service_request_events e
          where e.request_id = r.id and e.public), '[]'::jsonb)
      ) as item
      from service_requests r
      join service_categories c on c.id = r.category_id
      where r.user_id = auth.uid()
      order by r.created_at desc
      limit 100
    ) t), '[]'::jsonb);
end;
$$;

create or replace function public.cancel_service_request(p_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r      service_requests%rowtype;
  before text;
  reason text := nullif(btrim(left(coalesce(p_reason, ''), 500)), '');
begin
  if auth.uid() is null then
    raise exception 'sign_in';
  end if;
  select * into r from service_requests where id = p_id and user_id = auth.uid() for update;
  if not found then
    raise exception 'not_found';
  end if;
  -- Only before work begins.
  if r.status not in ('pending', 'under_review', 'accepted') then
    raise exception 'not_allowed';
  end if;
  before := r.status;

  update service_requests
  set status = 'cancelled', cancel_reason = reason, updated_at = now(), status_at = now()
  where id = r.id
  returning * into r;

  insert into service_request_events (request_id, kind, from_status, to_status, note, public, actor)
  values (r.id, 'status', before, 'cancelled', reason, true, 'customer');

  insert into notifications (user_id, kind, service_request_id, data)
  select pr.id, 'service_cancelled', r.id, service_note_data(r)
  from profiles pr where pr.role = 'admin';

  return jsonb_build_object('id', r.id, 'ref', r.ref, 'status', r.status);
end;
$$;

/* ── 5. The admin panel's side ────────────────────────────────────────── */

create or replace function public.admin_service_update(
  p_id          uuid,
  p_status      text default null,
  p_note        text default null,
  p_note_public boolean default false,
  p_assignee    uuid default null,
  p_unassign    boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r       service_requests%rowtype;
  before  text;
  note    text := nullif(btrim(left(coalesce(p_note, ''), 1000)), '');
  moved   boolean := false;
begin
  select * into r from service_requests where id = p_id for update;
  if not found then
    raise exception 'not_found';
  end if;
  before := r.status;

  if p_status is not null and p_status not in ('pending', 'under_review', 'accepted', 'in_progress', 'completed', 'rejected', 'cancelled') then
    raise exception 'invalid:status';
  end if;

  if p_status is not null and p_status <> r.status then
    update service_requests set status = p_status, updated_at = now(), status_at = now() where id = r.id returning * into r;
    -- A note for the customer travels with the change it explains.
    insert into service_request_events (request_id, kind, from_status, to_status, note, public, actor)
    values (r.id, 'status', before, p_status, case when p_note_public then note end, true, 'admin');
    insert into notifications (user_id, kind, service_request_id, data)
    values (r.user_id, 'service_status', r.id, service_note_data(r) || jsonb_build_object('note', case when p_note_public then note end));
    moved := true;
  end if;

  if note is not null and not (moved and p_note_public) then
    insert into service_request_events (request_id, kind, note, public, actor)
    values (r.id, 'note', note, p_note_public, 'admin');
    if p_note_public then
      insert into notifications (user_id, kind, service_request_id, data)
      values (r.user_id, 'service_note', r.id, service_note_data(r) || jsonb_build_object('note', note));
    end if;
  end if;

  if p_unassign and r.assigned_to is not null then
    update service_requests set assigned_to = null, updated_at = now() where id = r.id returning * into r;
    insert into service_request_events (request_id, kind, note, public, actor)
    values (r.id, 'assigned', null, false, 'admin');
  elsif p_assignee is not null and p_assignee is distinct from r.assigned_to then
    if not exists (select 1 from profiles where id = p_assignee and role = 'admin') then
      raise exception 'invalid:assignee';
    end if;
    update service_requests set assigned_to = p_assignee, updated_at = now() where id = r.id returning * into r;
    insert into service_request_events (request_id, kind, note, public, actor)
    values (r.id, 'assigned', (select coalesce(full_name, '') from profiles where id = p_assignee), false, 'admin');
  end if;

  return jsonb_build_object('id', r.id, 'ref', r.ref, 'status', r.status, 'assigned_to', r.assigned_to);
end;
$$;

/* ── 8. The admin panel's counts ──────────────────────────────────────── */

create or replace function public.admin_services_overview()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'total', (select count(*) from service_requests),
    'byStatus', jsonb_build_object(
      'pending',      (select count(*) from service_requests where status = 'pending'),
      'under_review', (select count(*) from service_requests where status = 'under_review'),
      'accepted',     (select count(*) from service_requests where status = 'accepted'),
      'in_progress',  (select count(*) from service_requests where status = 'in_progress'),
      'completed',    (select count(*) from service_requests where status = 'completed'),
      'rejected',     (select count(*) from service_requests where status = 'rejected'),
      'cancelled',    (select count(*) from service_requests where status = 'cancelled')),
    'today', (select count(*) from service_requests
              where created_at >= date_trunc('day', now() at time zone 'Asia/Amman') at time zone 'Asia/Amman'),
    'week', (select count(*) from service_requests where created_at > now() - interval '7 days'),
    'urgentOpen', (select count(*) from service_requests
                   where urgency in ('urgent', 'emergency') and status in ('pending', 'under_review', 'accepted', 'in_progress')),
    'oldestPending', (select min(created_at) from service_requests where status = 'pending'),
    'categories', (select count(*) from service_categories where active),
    'byCategory', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'en', c.name_en, 'ar', c.name_ar, 'n', x.n) order by x.n desc)
      from (select category_id, count(*) as n from service_requests
            where created_at > now() - interval '30 days' group by category_id) x
      join service_categories c on c.id = x.category_id), '[]'::jsonb),
    'daily', (
      select jsonb_agg(jsonb_build_object('day', to_char(d, 'YYYY-MM-DD'), 'requests',
        (select count(*) from service_requests r where (r.created_at at time zone 'Asia/Amman')::date = d)) order by d)
      from generate_series((now() at time zone 'Asia/Amman')::date - 29, (now() at time zone 'Asia/Amman')::date, interval '1 day') g(d0),
           lateral (select g.d0::date as d) x)
  );
$$;

/* ── Who may call what ────────────────────────────────────────────────── */

revoke all on function public.service_note_data(public.service_requests) from public, anon, authenticated;
revoke all on function public.create_service_request(jsonb) from public, anon;
revoke all on function public.my_service_requests() from public, anon;
revoke all on function public.cancel_service_request(uuid, text) from public, anon;
revoke all on function public.admin_service_update(uuid, text, text, boolean, uuid, boolean) from public, anon, authenticated;
revoke all on function public.admin_services_overview() from public, anon, authenticated;
grant execute on function public.service_note_data(public.service_requests) to service_role;
grant execute on function public.create_service_request(jsonb) to authenticated, service_role;
grant execute on function public.my_service_requests() to authenticated, service_role;
grant execute on function public.cancel_service_request(uuid, text) to authenticated, service_role;
grant execute on function public.admin_service_update(uuid, text, text, boolean, uuid, boolean) to service_role;
grant execute on function public.admin_services_overview() to service_role;

/* ── 6. Photos ────────────────────────────────────────────────────────── */

-- Private: never served to the public. Policies are made with EXECUTE so
-- this file also runs where the storage schema is absent (a test database).
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('service-photos', 'service-photos', false, 8388608,
          array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
  on conflict (id) do update
    set public = false,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  execute 'drop policy if exists "service photos: upload into your own folder" on storage.objects';
  execute $p$create policy "service photos: upload into your own folder" on storage.objects for insert to authenticated
    with check (bucket_id = 'service-photos' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
  execute 'drop policy if exists "service photos: read your own" on storage.objects';
  execute $p$create policy "service photos: read your own" on storage.objects for select to authenticated
    using (bucket_id = 'service-photos' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
  execute 'drop policy if exists "service photos: delete your own" on storage.objects';
  execute $p$create policy "service photos: delete your own" on storage.objects for delete to authenticated
    using (bucket_id = 'service-photos' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
end $$;

notify pgrst, 'reload schema';
