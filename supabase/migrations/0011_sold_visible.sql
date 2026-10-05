-- 0011_sold_visible.sql
--
-- Lets a sold or rented property stay on the marketplace instead of
-- disappearing from it.
--
-- Until now the public read policy was `status = 'active'`. The listing_status
-- enum has had 'sold' and 'rented' since 0001, but choosing either removed the
-- property from Buy and Rent completely and made its page stop loading — so
-- the only way to record a sale was to make the record vanish, taking any link
-- anyone had shared with it.
--
-- They now stay readable and the app greys their photographs and marks them
-- SOLD. This is how the large portals behave, and it is useful in both
-- directions: a buyer sees the market is moving, and the asking price of a
-- property that actually sold is the most honest comparison the site has.
--
-- What this publishes, stated plainly: for a sold or rented listing, the same
-- columns that were already public while it was active — photographs, asking
-- price, area, the approximate or exact point its owner chose. It does NOT
-- newly expose anything that was private. The exact coordinates in
-- property_locations stay owner-only (0010), and drafts, paused, pending,
-- rejected and archived listings stay invisible exactly as before.
--
-- An owner who would rather the listing disappeared after a sale still can:
-- 'archived' is in the enum and is not published by this policy.
--
-- Safe to run more than once.

drop policy if exists "active listings are public" on public.properties;

-- Named for what it now does. The old name is dropped above, so running this
-- file twice leaves exactly one policy.
drop policy if exists "active and closed listings are public" on public.properties;
create policy "active and closed listings are public"
  on public.properties for select
  using (status in ('active', 'sold', 'rented'));

-- The browse pages read status alongside deal and price on every request.
create index if not exists properties_public_status_idx
  on public.properties (status, deal, price_jod desc)
  where status in ('active', 'sold', 'rented');

notify pgrst, 'reload schema';
