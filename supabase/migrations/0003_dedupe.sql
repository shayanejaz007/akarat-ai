-- Akarat.ai — cross-source deduplication
--
-- Run after 0002_external_index.sql.
--
-- The same property is listed on several portals. Grouping is deliberately
-- conservative: only strong evidence merges two rows. When the evidence is
-- weak the listings stay separate, because showing one property twice is a
-- small annoyance while merging two different properties is a real error.

create or replace function public.group_external_duplicates()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  merged integer := 0;
begin
  -- Pass 1: coordinates plus price. Two listings within ~150 m of each other
  -- at within 2% of the same price, same deal type and bedroom count, are the
  -- same property advertised twice.
  with pairs as (
    select a.id as keep, b.id as drop_id,
           coalesce(a.dedupe_group, gen_random_uuid()) as grp
      from external_properties a
      join external_properties b
        on b.id <> a.id
       and b.source_id <> a.source_id
       and a.transaction_type = b.transaction_type
       and coalesce(a.bedrooms, -1) = coalesce(b.bedrooms, -1)
       and a.latitude is not null and a.longitude is not null
       and b.latitude is not null and b.longitude is not null
       and abs(a.latitude - b.latitude) < 0.0014
       and abs(a.longitude - b.longitude) < 0.0016
       and a.price is not null and b.price is not null
       and abs(a.price - b.price)::numeric / greatest(a.price, 1) < 0.02
     where a.id < b.id
  )
  update external_properties e
     set dedupe_group = p.grp
    from pairs p
   where e.id in (p.keep, p.drop_id)
     and e.dedupe_group is distinct from p.grp;
  get diagnostics merged = row_count;

  -- Pass 2: no coordinates, so lean on title similarity within the same
  -- neighbourhood. The threshold is high on purpose; trigram similarity is
  -- suggestive, not proof.
  with pairs as (
    select a.id as keep, b.id as drop_id,
           coalesce(a.dedupe_group, b.dedupe_group, gen_random_uuid()) as grp
      from external_properties a
      join external_properties b
        on b.id <> a.id
       and b.source_id <> a.source_id
       and a.transaction_type = b.transaction_type
       and a.neighborhood_id is not null
       and a.neighborhood_id = b.neighborhood_id
       and coalesce(a.bedrooms, -1) = coalesce(b.bedrooms, -1)
       and coalesce(a.bathrooms, -1) = coalesce(b.bathrooms, -1)
       and a.price is not null and b.price is not null
       and abs(a.price - b.price)::numeric / greatest(a.price, 1) < 0.01
       and similarity(a.title, b.title) > 0.62
     where a.id < b.id
       and (a.latitude is null or b.latitude is null)
  )
  update external_properties e
     set dedupe_group = p.grp
    from pairs p
   where e.id in (p.keep, p.drop_id)
     and e.dedupe_group is distinct from p.grp;

  return merged;
end;
$$;

-- One row per property rather than per listing, with the sources that carry it.
-- The cheapest price wins the headline; every source URL stays reachable.
create or replace view public.external_properties_grouped as
select
  coalesce(p.dedupe_group::text, p.id::text)          as group_key,
  min(p.id::text)                                     as representative_id,
  count(*)                                            as source_count,
  array_agg(distinct p.source_id)                     as sources,
  jsonb_agg(jsonb_build_object(
    'source_id', p.source_id,
    'url', p.source_url,
    'price', p.price,
    'last_checked_at', p.last_checked_at
  ) order by p.price nulls last)                      as listings,
  min(p.price)                                        as price_low,
  max(p.price)                                        as price_high,
  max(p.last_seen_at)                                 as last_seen_at,
  -- representative facts, taken from the freshest row that has them
  (array_agg(p.title      order by p.last_seen_at desc))[1] as title,
  (array_agg(p.transaction_type order by p.last_seen_at desc))[1] as transaction_type,
  (array_agg(p.property_type   order by p.last_seen_at desc))[1] as property_type,
  (array_agg(p.city_id         order by p.last_seen_at desc))[1] as city_id,
  (array_agg(p.neighborhood_id order by p.last_seen_at desc))[1] as neighborhood_id,
  max(p.bedrooms)  as bedrooms,
  max(p.bathrooms) as bathrooms,
  max(p.area_sqm)  as area_sqm,
  (array_agg(p.latitude  order by p.last_seen_at desc))[1] as latitude,
  (array_agg(p.longitude order by p.last_seen_at desc))[1] as longitude,
  (array_agg(p.image_url order by p.last_seen_at desc))[1] as image_url
from public.external_properties p
where p.availability_status <> 'unavailable'
group by coalesce(p.dedupe_group::text, p.id::text);

comment on view public.external_properties_grouped is
  'One row per distinct property. source_count > 1 means the same property was found on several portals.';
