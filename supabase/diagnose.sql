-- Akarat.ai — schema audit
--
-- Paste the whole file into the Supabase SQL Editor and run it. It changes
-- nothing. Scroll to the LAST result: it is a single verdict row telling you
-- whether the database is ready. The blocks above it show the detail behind
-- that verdict, so you only need them if the verdict is not PASS.

-- ══════════════════════════════════════════════════════════════
-- 1. Tables: do they exist, do they have policies, can the app read them?
-- ══════════════════════════════════════════════════════════════
select
  expected.name as table_name,
  case when t.table_name is null then '✗ missing' else '✓ present' end as exists,
  coalesce((select count(*) from pg_policies p
    where p.schemaname = 'public' and p.tablename = expected.name), 0) as policies,
  case when t.table_name is null then null
       else has_table_privilege('anon', 'public.' || expected.name, 'select') end as anon_read,
  case when t.table_name is null then null
       else has_table_privilege('authenticated', 'public.' || expected.name, 'select') end as user_read
from (values
  ('profiles'), ('properties'), ('inquiries'), ('saved_searches'),
  ('cities'), ('neighborhoods'), ('external_sources'), ('external_properties')
) as expected(name)
left join information_schema.tables t
  on t.table_schema = 'public' and t.table_name = expected.name
order by expected.name;

-- ══════════════════════════════════════════════════════════════
-- 2. Columns on `properties`: a missing one is what produces a 400
-- ══════════════════════════════════════════════════════════════
select
  expected.name as column_name,
  case when c.column_name is null then '✗ missing' else '✓ ' || c.data_type end as status
from (values
  ('id'), ('owner_id'), ('deal'), ('property_type'), ('city_id'),
  ('neighborhood_id'), ('price_jod'), ('bedrooms'), ('bathrooms'),
  ('area_sqm'), ('land_sqm'), ('year_built'), ('title_en'), ('title_ar'),
  ('status'), ('created_at'), ('payload_gz'), ('payload_bytes'), ('raw_bytes')
) as expected(name)
left join information_schema.columns c
  on c.table_schema = 'public' and c.table_name = 'properties'
  and c.column_name = expected.name
order by expected.name;

-- ══════════════════════════════════════════════════════════════
-- 3. Everything else each migration was supposed to leave behind
-- ══════════════════════════════════════════════════════════════
select 'enum deal_type' as object,
  case when exists (select 1 from pg_type where typname = 'deal_type')
       then '✓ present' else '✗ missing — rerun 0001_init.sql' end as status
union all
select 'enum listing_status',
  case when exists (select 1 from pg_type where typname = 'listing_status')
       then '✓ present' else '✗ missing — rerun 0001_init.sql' end
union all
select 'cities seeded',
  case when (select count(*) from public.cities) > 0
       then '✓ ' || (select count(*) from public.cities)::text || ' rows'
       else '✗ empty — rerun 0001_init.sql' end
union all
select 'neighborhoods seeded',
  case when (select count(*) from public.neighborhoods) > 0
       then '✓ ' || (select count(*) from public.neighborhoods)::text || ' rows'
       else '✗ empty — rerun 0001_init.sql' end
union all
select 'view external_properties_grouped',
  case when exists (
    select 1 from information_schema.views
    where table_schema = 'public' and table_name = 'external_properties_grouped')
       then '✓ present' else '✗ missing — run 0003_dedupe.sql' end
union all
select 'external sources registered',
  case when exists (select 1 from public.external_sources)
       then '✓ ' || (select count(*) from public.external_sources)::text || ' rows ('
            || (select count(*) from public.external_sources where enabled)::text || ' enabled)'
       else '✗ empty — rerun 0002_external_index.sql' end;

-- ══════════════════════════════════════════════════════════════
-- 4. Location privacy: can a signed-out visitor reach exact coordinates?
--
-- properties.lat/lng is the publishable point and may be deliberately
-- displaced. The real one lives in property_locations, and the whole design
-- rests on `anon` having no way to read that table.
--
-- Worth checking rather than assuming, because 0005_grants.sql grants SELECT
-- to anon on every table created after it by default, which silently included
-- this one until 0010 revoked it. Every row below should read ✓.
-- ══════════════════════════════════════════════════════════════
select 'table property_locations' as check,
  case when exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'property_locations')
       then '✓ present' else '✗ missing — run 0010_location.sql' end as status
union all
select 'properties.location_precision',
  case when exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'properties'
      and column_name = 'location_precision')
       then '✓ present' else '✗ missing — run 0010_location.sql' end
union all
select 'anon CANNOT read exact coords',
  case when not has_table_privilege('anon', 'public.property_locations', 'select')
       then '✓ revoked at the grant'
       else '✗ ANON HAS SELECT — rerun 0010_location.sql' end
union all
select 'owner CAN read exact coords',
  case when has_table_privilege('authenticated', 'public.property_locations', 'select')
       then '✓ granted (RLS limits it to the owner)'
       else '✗ missing — rerun 0010_location.sql' end
union all
select 'RLS enforced on exact coords',
  case when (select relrowsecurity from pg_class
             where oid = 'public.property_locations'::regclass)
       then '✓ enabled with ' || (select count(*)::text from pg_policies
             where schemaname = 'public' and tablename = 'property_locations')
            || ' owner-scoped policies'
       else '✗ RLS OFF — rerun 0010_location.sql' end
union all
-- Any other table that picked up the same unasked-for grant. Reads ✓ when the
-- only anon-readable tables are the ones meant to be public.
select 'no table leaks to anon by accident',
  coalesce((
    select '✗ unexpected anon SELECT on: ' || string_agg(t.table_name, ', ')
    from information_schema.tables t
    where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
      and t.table_name not in ('properties','cities','neighborhoods',
        'external_sources','external_properties','inquiries')
      and has_table_privilege('anon', 'public.' || t.table_name, 'select')
  ), '✓ only the public tables are anon-readable');

-- ══════════════════════════════════════════════════════════════
-- 5. VERDICT — read this one
-- ══════════════════════════════════════════════════════════════
with checks as (
  select
    (select count(*) from information_schema.tables
      where table_schema = 'public' and table_name in (
        'profiles','properties','inquiries','saved_searches',
        'cities','neighborhoods','external_sources','external_properties'
      )) as tables_present,
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'properties'
        and column_name in (
          'id','owner_id','deal','property_type','city_id','neighborhood_id',
          'price_jod','bedrooms','bathrooms','area_sqm','land_sqm','year_built',
          'title_en','title_ar','status','created_at','payload_gz',
          'payload_bytes','raw_bytes'
        )) as columns_present,
    (select count(*) from pg_policies where schemaname = 'public') as policies,
    (select count(*) from pg_type where typname in ('deal_type','listing_status')) as enums,
    (select count(*) from public.cities) as cities,
    (select count(*) from information_schema.views
      where table_schema = 'public' and table_name = 'external_properties_grouped') as dedupe_view,
    (select bool_and(has_table_privilege('anon', 'public.' || table_name, 'select'))
      from information_schema.tables
      where table_schema = 'public'
        and table_name in ('properties','cities','neighborhoods',
                           'external_sources','external_properties')) as grants_ok,
    -- 0010. Present and locked down, or not deployed at all; a half-deployed
    -- state is the one that publishes addresses, so it fails the verdict.
    (select count(*) from information_schema.tables
      where table_schema = 'public' and table_name = 'property_locations') as geo_table,
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'properties'
        and column_name in ('location_precision', 'address')) as geo_columns,
    (select not has_table_privilege('anon', 'public.property_locations', 'select')
      from information_schema.tables
      where table_schema = 'public' and table_name = 'property_locations') as geo_private
)
select
  case
    when tables_present = 8 and columns_present = 19 and enums = 2
     and cities > 0 and dedupe_view = 1 and grants_ok and policies > 0
     and geo_table = 1 and geo_columns = 2 and geo_private
      then '✓ PASS — schema complete, grants in place, app is ready to run'
    when geo_table = 1 and not coalesce(geo_private, false)
      then '✗ PRIVACY — anon can read exact coordinates. Rerun 0010_location.sql'
    else '✗ INCOMPLETE — see the failing items below'
  end as verdict,
  tables_present   || ' / 8'  as tables,
  columns_present  || ' / 19' as properties_columns,
  enums            || ' / 2'  as enum_types,
  policies         || ' policies' as rls_policies,
  case when grants_ok then 'granted' else 'MISSING → run 0005_grants.sql' end as anon_grants,
  case when dedupe_view = 1 then 'present' else 'MISSING → run 0003_dedupe.sql' end as dedupe_view,
  case when geo_table = 0 then 'not deployed → run 0010_location.sql'
       when geo_columns < 2 then 'columns missing → rerun 0010_location.sql'
       when not coalesce(geo_private, false) then 'EXPOSED → rerun 0010_location.sql'
       else 'exact coords owner-only' end as location_privacy,
  cities || ' cities seeded' as seed_data
from checks;
