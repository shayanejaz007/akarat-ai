-- 0007_listing_video.sql
--
-- Run after 0006_listing_photos.sql.
--
-- Widens the listing bucket so an owner can upload short video clips beside
-- the photos. The row policies from 0006 are unchanged and still apply: an
-- owner writes only under their own `<user_id>/` prefix, and anyone may read.
--
-- The size limit is per object and is the ceiling for BOTH kinds, so it has to
-- be the video number. Images stay held to 6 MB by the listing form and by
-- lib/supabase.js; one bucket cannot express two limits.

update storage.buckets
   set public = true,
       file_size_limit = 52428800,          -- 50 MB, matching MAX_VIDEO_BYTES
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/avif',
         'video/mp4', 'video/webm', 'video/quicktime'
       ]
 where id = 'listing-photos';

-- Should 0006 never have run, create the bucket outright rather than silently
-- doing nothing.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
select 'listing-photos', 'listing-photos', true, 52428800,
       array['image/jpeg', 'image/png', 'image/webp', 'image/avif',
             'video/mp4', 'video/webm', 'video/quicktime']
 where not exists (select 1 from storage.buckets where id = 'listing-photos');

notify pgrst, 'reload schema';
