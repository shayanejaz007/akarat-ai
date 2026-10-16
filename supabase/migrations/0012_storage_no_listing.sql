-- 0012_storage_no_listing.sql
--
-- Stops a signed-out visitor enumerating the whole listing-photos bucket.
--
-- 0006 gave storage.objects a SELECT policy covering the entire bucket, so
-- POST /storage/v1/object/list/listing-photos answered a stranger with every
-- path in it. Two things fall out of that, neither of them wanted:
--
--   - The folder names are owner user ids, so the listing is also a list of
--     every account that has ever uploaded a photo, and how many each has.
--   - Photos belonging to listings that are NOT public — drafts, paused,
--     rejected, archived — are in the same bucket. The row is hidden by RLS
--     on `properties`, but the photograph was still discoverable, and a
--     public bucket serves it to anyone holding the path.
--
-- The broad policy is not what makes the photos load. The bucket is
-- `public = true`, and a public bucket serves GET /object/public/... without
-- consulting RLS at all. The policy only governed the authenticated API —
-- which in practice meant `list`. So narrowing it to owners costs the app
-- nothing: nothing in the codebase lists the bucket, and every <img> keeps
-- working exactly as before.
--
-- Safe to run more than once, and it changes no files.

drop policy if exists "listing photos are public" on storage.objects;

drop policy if exists "owners list their own photos" on storage.objects;
create policy "owners list their own photos"
  on storage.objects for select
  using (
    bucket_id = 'listing-photos'
    -- Paths are written as <owner id>/<file>, which is the same check the
    -- insert and delete policies in 0006 already make.
    and auth.uid()::text = (storage.foldername(name))[1]
  );
