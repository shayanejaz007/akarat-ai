-- 0006_listing_photos.sql
--
-- Storage for listing photos. Files live in Supabase Storage rather than in
-- payload_gz: gzipped base64 of a JPEG is larger than the JPEG itself, and it
-- would be re-read on every listing fetch.
--
-- Path convention is `<user_id>/<filename>`, which is what the write policies
-- below check. An owner can only write under their own prefix.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'listing-photos',
  'listing-photos',
  true,                                   -- listings are public, so are their photos
  6291456,                                -- 6 MB per file, enforced server-side too
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
)
on conflict (id) do update
  set public = true,
      file_size_limit = 6291456,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/avif'];

-- Anyone may read. The bucket is public, and a listing with unviewable photos
-- is not a listing.
drop policy if exists "listing photos are public" on storage.objects;
create policy "listing photos are public"
  on storage.objects for select
  using (bucket_id = 'listing-photos');

-- Writes are confined to the caller's own folder. `storage.foldername` returns
-- the path segments, so [1] is the user id prefix.
drop policy if exists "owners upload their own photos" on storage.objects;
create policy "owners upload their own photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "owners replace their own photos" on storage.objects;
create policy "owners replace their own photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "owners delete their own photos" on storage.objects;
create policy "owners delete their own photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

notify pgrst, 'reload schema';
