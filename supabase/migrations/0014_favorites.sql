-- 0014_favorites.sql
--
-- Saved properties, per account, so a heart tapped on the phone is still
-- there on the website and on the next device.
--
-- ADDITIVE ONLY. Creates one table, its policies and grants. It changes no
-- existing table, column, policy or row, and is safe to run more than once.
-- Review it, then run it in the Supabase SQL Editor like the others.
--
-- Until it runs, the mobile app keeps saved properties on the device and
-- says so; nothing fails. The website today keeps them in page memory only
-- (toggleSaved in Akarat.dc.html) and can read this table once it exists.

create table if not exists public.favorites (
  user_id     uuid not null references auth.users (id) on delete cascade,
  property_id uuid not null references public.properties (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, property_id)
);

-- "My saved properties, newest first" and "how many people saved this".
create index if not exists favorites_user_created_idx on public.favorites (user_id, created_at desc);
create index if not exists favorites_property_idx on public.favorites (property_id);

alter table public.favorites enable row level security;

-- Private to their owner in every direction.
drop policy if exists "favorites are private to their owner" on public.favorites;
create policy "favorites are private to their owner"
  on public.favorites for select using (auth.uid() = user_id);

-- A row can be written only for yourself, and only against a listing you can
-- actually see (public, or your own). The subquery runs under the caller's
-- RLS, so a private listing of someone else's is invisible to it.
drop policy if exists "owners save visible listings" on public.favorites;
create policy "owners save visible listings"
  on public.favorites for insert
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.properties p where p.id = favorites.property_id)
  );

drop policy if exists "owners remove their own favorites" on public.favorites;
create policy "owners remove their own favorites"
  on public.favorites for delete using (auth.uid() = user_id);

-- No update policy: a favourite is added or removed, never edited.

grant select, insert, delete on public.favorites to authenticated;

-- 0005_grants.sql's default privileges hand SELECT on every new table to
-- `anon`. Nothing here is for signed-out callers, so take it back rather than
-- leave the table resting on RLS alone (same reasoning as 0010).
revoke all on public.favorites from anon;
revoke all on public.favorites from public;

notify pgrst, 'reload schema';
