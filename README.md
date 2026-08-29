# Akarat.ai

Property search across Jordan. Describe what you want in English or Arabic;
the app reads your requirements, searches its own verified listings and the
wider Jordanian market, and shows how each result was matched.

## What is in this repository

```
Akarat.dc.html                    the application
lib/aisearch.js                   query parsing, scoring, match explanations
lib/providers.js                  portal deep links (verified URL grammar)
lib/supabase.js                   auth, listings, compression, index reads
data/market.js                    reference data only: locations, amenities, types
app/api/ai/search/route.ts        server-side search pipeline + provider adapters
app/api/admin/crawl/route.ts      crawl worker (robots.txt, JSON-LD, upsert)
app/metadata.ts                   SEO metadata and schema.org output
middleware.ts                     session refresh + server-side route gating
utils/supabase/*                  server, browser and middleware clients
supabase/migrations/*.sql         schema, RLS, external index, deduplication
```

Reference documents: `SECURITY-AUDIT.md`, `SEARCH-ARCHITECTURE.md`,
`SUPABASE.md`.

## No invented data

There is no seed inventory and no sample metrics anywhere in this codebase.
An empty marketplace renders an empty state; an account with no listings shows
an empty table. Where a source published nothing, the field reads
"Not provided". This is deliberate and worth preserving: the product's claim is
that every figure traces to a real record.

**One exception to clear out.** An earlier build's "Add property" button
inserted one of four hardcoded sample listings instead of opening a form. That
button is gone, but any rows it already wrote are still in your database, and
they now surface on the home carousel and the buy page like real inventory.
Run `supabase/cleanup-samples.sql` once to remove them, or delete them from the
dashboard, where you own every row.

## Configuring the database

The app runs without a database, but sign-in, the dashboard and the market
index all stay dark until Supabase is wired up. Work through these steps in
order; the whole thing takes about ten minutes.

### 1. Create the project

Go to supabase.com, create a new project, and pick a region close to your
users (Frankfurt is the usual choice for Jordan). Save the database password
somewhere safe. Wait for provisioning to finish before continuing.

### 2. Collect the keys

In the dashboard, open **Project Settings → API**. You need three values:

- **Project URL** — looks like `https://abcdefgh.supabase.co`
- **Publishable (anon) key** — safe in the browser, because Row Level Security
  bounds everything it can reach
- **Service role key** — bypasses RLS entirely. Server only. Never ship it to
  the browser, never commit it, never prefix it with `NEXT_PUBLIC_`.

### 3. Fill in the environment

```bash
npm install @supabase/supabase-js @supabase/ssr
cp .env.example .env.local
```

Open `.env.local` and set:

| Variable | Where | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | client + server | project URL from step 2 |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | client + server | anon key, bounded by RLS |
| `SUPABASE_SERVICE_ROLE_KEY` | **server only** | crawler writes; bypasses RLS |
| `CRON_SECRET` | **server only** | authenticates the crawl route |

Generate the cron secret with `openssl rand -hex 32`. On Vercel, add all four
under **Settings → Environment Variables**; mark the last two as available to
the server runtime only.

### 4. Run the migrations

Open **SQL Editor** in the Supabase dashboard, then paste and run each file in
this order, one at a time, checking each succeeds before moving on:

1. `supabase/migrations/0001_init.sql` — profiles, properties, inquiries,
   saved searches, canonical locations, and Row Level Security
2. `supabase/migrations/0002_external_index.sql` — the crawled market index
3. `supabase/migrations/0003_dedupe.sql` — cross-source deduplication
4. `supabase/migrations/0005_grants.sql` — table privileges for the `anon` and
   `authenticated` roles

Step 4 is not optional. RLS policies decide which rows a caller may see; they
do not grant access to the table itself. Without the grants, every read comes
back **403 permission denied** before any policy is consulted.

Until step 1 runs, the tables do not exist and RLS is not protecting anything.

If you prefer the CLI:

```bash
npx supabase link --project-ref <your-project-ref>
npx supabase db push
```

### 5. Configure Auth

Under **Authentication → Providers**, keep Email enabled. Under
**Authentication → URL Configuration**, set the Site URL to your deployed
domain and add `http://localhost:3000` as an additional redirect URL for local
work. Before launch, turn on email confirmation and leaked-password protection.

### 6. Verify

Run the app, create an account, and open the dashboard. The badge beside
**Your listings** tells you the state of the connection:

- **Connected** — schema is live and reachable
- **Index not set up yet** — migration `0002` has not run
- **Database unreachable** — URL or key is wrong, or the project is paused

An empty table under a Connected badge is correct: there is no seed data.

If the browser console shows Supabase errors, run `supabase/diagnose.sql` in
the SQL Editor. It reports which tables exist, which have policies, and which
the `anon` role can read. Read the statuses this way:

- **403** — the role has no `GRANT` on that table. Run `0005_grants.sql`.
- **400** — the request does not match the deployed schema, usually a column
  the migration never created. Result 2 of the diagnostic lists what is there.
- **404** — the table does not exist. That migration has not run.
- **200 with an empty array** — everything is wired up; RLS is simply matching
  no rows, which is the correct answer for an empty database.

### 7. Enable market sources (optional)

The two portals in `external_sources` ship with `enabled = false` on purpose.
See "Running the crawler" below before you turn either one on.

## Running the crawler

Sources ship disabled. For each one: review its `robots.txt` and terms, record
the decision in `external_sources.robots_checked_at` and `terms_reviewed`, then
set `enabled = true`. Ask for a licensed feed first; it is cleaner technically
and legally, and the adapter interface treats every source as pluggable.

```bash
curl -X POST https://your-host/api/admin/crawl \
  -H "Authorization: Bearer $CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"maxPages": 4}'
```

Schedule it with Vercel Cron or `pg_cron`. It honours per-host crawl delays,
respects `Retry-After`, extracts only schema.org JSON-LD, and never passes raw
page HTML into any reasoning layer.

## Before going live

The full list is at the end of `SECURITY-AUDIT.md`. The essentials:

1. Run the three migrations
2. Keep the service-role key server-side
3. Move the search route's rate-limit buckets to Redis or Postgres (the
   in-memory map is per-instance)
4. Add CSP, HSTS, `X-Content-Type-Options`, `X-Frame-Options` at the edge
5. Enable email confirmation and leaked-password protection in Supabase Auth
6. Move `assets/hero-jordan.mp4` (19.7 MB) to a CDN, and re-encode it with
   `-movflags +faststart` so playback starts before the whole file downloads

## Known gap

Owners cannot yet hide exact coordinates behind an approximate location. Build
that before publishing real listings.
