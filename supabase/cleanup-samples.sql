-- Removes the four sample listings the old "Add property" button inserted
-- before it was replaced with a real form.
--
-- These rows are in YOUR database, written under YOUR account, so the app
-- cannot clear them for you. Run this once in the Supabase SQL Editor.

-- 1. Look before you delete. This shows exactly what will go.
select id, title_en, price_jod, city_id, neighborhood_id, created_at
from public.properties
where title_en in (
  'Contemporary stone villa with terraced garden',
  'Furnished two-bedroom near Wakalat Street',
  'Sea-view apartment in a serviced resort tower',
  'Residential plot, zoning A, quiet cul-de-sac'
)
order by created_at;

-- 2. If that list is only sample rows, delete them.
delete from public.properties
where title_en in (
  'Contemporary stone villa with terraced garden',
  'Furnished two-bedroom near Wakalat Street',
  'Sea-view apartment in a serviced resort tower',
  'Residential plot, zoning A, quiet cul-de-sac'
);

-- 3. Confirm the table holds only what you listed yourself.
select count(*) as listings_remaining from public.properties;

-- If you would rather start completely clean, this empties the table:
--   delete from public.properties;
