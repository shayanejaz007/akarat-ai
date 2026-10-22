-- 0015_listing_reports.sql
--
-- Reports of listings, from "Report this listing" in the mobile app. Both
-- app stores require apps where people post content to let others report
-- it (App Store guideline 1.2, Google Play's user-generated content policy),
-- and someone to act on what comes in — promptly: Apple's terms for such
-- apps speak of acting within 24 hours.
--
-- ADDITIVE ONLY. Creates one table, its policy and grant. It changes no
-- existing table, column, policy or row, and is safe to run more than once.
-- Review it, then run it in the Supabase SQL Editor like the others.
--
-- Anyone signed in may file a report; nobody can read reports back through
-- the API, the reporter included. Read them in the dashboard (Table Editor →
-- listing_reports, open ones newest first) and record what was done in
-- `status`. Until this runs, the app sends reports by email instead.

create table if not exists public.listing_reports (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  -- Kept when the reporter later deletes their account: the report still
  -- stands.
  reporter_id uuid default auth.uid() references auth.users (id) on delete set null,
  reason      text not null check (reason in ('scam', 'wrong_details', 'unavailable', 'offensive', 'other')),
  details     text check (char_length(details) <= 1000),
  status      text not null default 'open' check (status in ('open', 'reviewed', 'removed', 'dismissed')),
  created_at  timestamptz not null default now()
);

-- One report per person per listing: a second tap is not a second report.
create unique index if not exists listing_reports_once_idx on public.listing_reports (property_id, reporter_id);
-- What is waiting, newest first.
create index if not exists listing_reports_open_idx on public.listing_reports (created_at desc) where status = 'open';

alter table public.listing_reports enable row level security;

-- As themselves, and only as a new report: a reporter cannot mark their own
-- report handled.
drop policy if exists "signed-in people report listings as themselves" on public.listing_reports;
create policy "signed-in people report listings as themselves"
  on public.listing_reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open');

grant insert on public.listing_reports to authenticated;

notify pgrst, 'reload schema';

/* ── Check, after applying: the app's "Report this listing" says thanks
   instead of opening an email, and the row appears in the Table Editor.
   GET /rest/v1/listing_reports with the publishable key returns no rows
   (or permission denied): reports are not readable through the API. */
