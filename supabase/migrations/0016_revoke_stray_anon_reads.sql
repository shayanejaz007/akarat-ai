-- 0016_revoke_stray_anon_reads.sql
--
-- Takes back SELECT privileges that nobody asked for, and stops the next
-- table inheriting them.
--
-- ── Where they came from ───────────────────────────────────────────────
-- 0005_grants.sql ends with:
--
--     alter default privileges in schema public
--       grant select on tables to anon, authenticated;
--
-- which means every table created in this schema *after* that statement ran
-- starts life readable by `anon`, whether or not anyone intended it. It is why
-- `profiles` and `saved_searches` correctly refuse a signed-out read — they
-- predate it — while tables added later quietly do not.
--
-- This has already been fixed once, for property_locations in 0010. A sweep of
-- every table found one more that slipped through the same way.
--
-- ── What this changes, and what it does not ────────────────────────────
-- Nothing currently leaks. RLS has no SELECT policy on the tables below, so a
-- signed-out read already returns no rows. The problem is that RLS is the only
-- thing standing there: a policy written later that is more permissive than
-- intended, or RLS switched off for a minute while debugging something else,
-- would turn an empty answer into a disclosure. Both are ordinary maintenance,
-- not exotic failures, and a grant that was never wanted is a poor thing to be
-- relying on their absence.
--
-- Safe to run more than once, and it touches no rows.

/* ── 1. listing_reports ────────────────────────────────────────────────
   Created in 0015, which grants INSERT only — the comment in that file says
   "nobody can read reports back through the API, the reporter included", and
   it is right about the outcome and wrong about the mechanism. A report holds
   free-text `details` and the `reporter_id` of whoever filed it; somebody
   reporting a listing for fraud should not be discoverable by the person they
   reported. Reports are read in the Supabase dashboard, which uses the
   service role and is unaffected by this. */
revoke all on public.listing_reports from anon;
revoke all on public.listing_reports from public;

/* ── 2. inquiries ──────────────────────────────────────────────────────
   0005 granted anon both SELECT and INSERT. INSERT is the point — anyone
   browsing may send an enquiry without an account, and the contact form on
   both the website and the mobile app depends on it. SELECT is not: an
   enquiry holds a name, an email address, a phone number and a message, and
   the only person meant to read one is the owner of the listing it was sent
   about, who is signed in. lib/supabase.js → listInquiries() returns early
   without a session and filters by owner_id, and the mobile app only inserts.
   So the read privilege has no caller and is removed; INSERT stays. */
revoke select on public.inquiries from anon;
grant insert on public.inquiries to anon;

/* ── 3. The default that caused this ───────────────────────────────────
   Future tables stop arriving pre-opened. `authenticated` keeps the default,
   because RLS is what scopes it to a person's own rows and policies are
   written for that role as a matter of course; `anon` does not, because a
   signed-out reader should be an explicit decision each time.

   The consequence to remember: a NEW table meant to be public now needs its
   grant written out, the way 0005 does for properties and cities —

       grant select on public.<table> to anon;

   Existing tables are untouched by this line; default privileges apply only
   to tables created after it. */
alter default privileges in schema public
  revoke select on tables from anon;

notify pgrst, 'reload schema';

/* ── Check, after applying ─────────────────────────────────────────────
   With the publishable (anon) key:

     GET /rest/v1/listing_reports   -> 401 permission denied   (was 200 [])
     GET /rest/v1/inquiries         -> 401 permission denied   (was 200 [])
     POST /rest/v1/inquiries        -> still works: the contact form must not
                                       break, and it is the reason anon has
                                       any privilege on that table at all
     GET /rest/v1/properties        -> 200, unchanged
     GET /rest/v1/cities            -> 200, unchanged

   And signed in, the owner's dashboard still lists enquiries on their own
   listings, because `authenticated` kept its grant. */
