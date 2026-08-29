# Akarat.ai — Supabase setup

Follow this top to bottom. Each step says what to run, where to run it, and
how to tell it worked.

---

## Step 1 — Run the migrations, in order

Open your project → **SQL Editor** → **New query**. For each file below: open
it from `supabase/migrations/`, copy the whole contents, paste, press **Run**,
and confirm it reports success before moving to the next one.

Order matters. Each file depends on the ones before it.

### `0001_init.sql` — the core schema

Creates the tables the app cannot run without:

| Table | Purpose |
|---|---|
| `profiles` | one row per account, created automatically on sign-up |
| `properties` | listings, owned by `auth.users.id` |
| `inquiries` | buyer messages against a listing |
| `saved_searches` | saved AI searches, private to each user |
| `cities`, `neighborhoods` | canonical Jordanian locations, seeded |

It also creates two enum types, `deal_type` and `listing_status`, enables Row
Level Security on every table, and writes the policies.

**Check it worked:** in **Table Editor** you should see six tables, and
`cities` should already contain Amman, Irbid, Zarqa, Aqaba and the rest. If
`cities` is empty the file did not finish; run it again.

### `0002_external_index.sql` — the market index

This is what the crawler writes into and what the search page reads when it
looks beyond your own listings. It creates two tables:

- `external_sources` — the portals you have approved. Two rows ship with it,
  both `enabled = false` on purpose. Nothing is crawled until you enable one.
- `external_properties` — one row per listing found on those portals, holding
  only what the source published as schema.org JSON-LD.

Read policy is public; there is no insert or update policy at all, so the
browser key can read this index but can never write to it. Only the service
role can, which is why the crawler runs server-side.

**Check it worked:** `external_sources` has two rows, both disabled.
`external_properties` exists and is empty. Empty is correct — it fills when
you run the crawler in step 6.

### `0003_dedupe.sql` — cross-source deduplication

The same villa listed on two portals should appear once, with both links. This
file adds the matching logic and a view, `external_properties_grouped`, that
returns one row per property with a `source_count` and every source URL.

The app queries that view, not the raw table. Without this file the external
half of search returns 404.

**Check it worked:** run `select * from external_properties_grouped limit 1;`
It should execute and return no rows. An error means the file did not run.

### `0005_grants.sql` — table privileges


Run this even though the earlier files created policies.

RLS decides which *rows* a caller may see. It does not grant access to the
table itself. Without a `GRANT`, PostgREST answers every read with **403
permission denied** before a policy is ever consulted. This file issues the
grants for the `anon` and `authenticated` roles and reloads the schema cache.

**Check it worked:** run `supabase/diagnose.sql`. Every row should show
`anon_can_read = true`.

### `0006_listing_photos.sql` — photo storage

Creates the `listing-photos` storage bucket and its policies. Reads are public
(a listing with unviewable photos is not a listing); writes are confined to
each owner's own folder, checked against `auth.uid()` on the path prefix. Files
are capped at 6 MB and limited to JPEG, PNG, WebP and AVIF.

Until this runs, the photo picker in the listing form reports that storage is
not set up and offers to publish without photos.

**Check it worked:** **Storage** in the dashboard shows a `listing-photos`
bucket marked public.

### `0004_coordinate_privacy.sql` — optional

Lets owners publish an approximate location instead of exact coordinates. Run
it before you list real homes. Not required to get the app working.

---

## Step 2 — Verify the whole schema at once

Paste `supabase/diagnose.sql` into the SQL Editor and run it. It changes
nothing and returns three result blocks:

1. Every expected table, its policy count, and whether `anon` and
   `authenticated` can read it. **Want: eight rows, policies above zero, both
   read columns true.**
2. The columns actually present on `properties`.
3. Whether `external_properties_grouped` exists.

Reading the result:

| What you see | What it means | What to do |
|---|---|---|
| A table is missing | that migration never ran | run it |
| `anon_can_read` is false | no grant | run `0005_grants.sql` |
| `policies` is 0 | policies missing | re-run `0001` or `0002` |
| A column is missing in block 2 | schema drift, causes 400s | re-run `0001_init.sql` |

---

## Step 3 — Configure Auth

**Authentication → URL Configuration**

- Site URL: your deployed domain
- Additional redirect URLs: `http://localhost:3000`

**Authentication → Providers → Email**

While testing, uncheck *Confirm email* so sign-up returns a session straight
away. Turn it back on before launch; the app already handles the "check your
email" path.

---

## Step 4 — Environment variables

Copy `.env.example` to `.env.local` and fill in all four values from
**Project Settings → API**:

```
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
CRON_SECRET=<openssl rand -hex 32>
```

The last two are server-only. Never prefix them with `NEXT_PUBLIC_`, never
import them into a client component, never commit `.env.local`.

`SUPABASE_SERVICE_ROLE_KEY` is not optional if you intend to crawl:
`app/api/admin/crawl/route.ts` reads it on every request and fails without it.

---

## Step 5 — Run it

```bash
npm install
npm run dev
```

Sign up, then open the dashboard. The badge beside **Your listings** tells you
the state of the connection:

- **Database connected** — schema live, query succeeded
- **Query rejected** — the server answered but refused the query. The row
  under the table carries the PostgREST code; look it up in the table below.
- **Database unreachable** — the request never arrived. Check the URL and key.

An empty table under a Connected badge is correct. There is no seed data.

### PostgREST codes you may meet

| Code / status | Meaning | Fix |
|---|---|---|
| 403 | no grant on the table | `0005_grants.sql` |
| 400 `PGRST204` | a column in the request does not exist | check block 2 of the diagnostic |
| 404 | table or view missing | run the migration that creates it |
| 23503 | foreign key violation | `cities` / `neighborhoods` not seeded; re-run `0001` |
| 200, empty array | everything works, no rows match | nothing to fix |

---

## Step 6 — Enable a market source (optional)

`external_sources` ships with both portals disabled. Before enabling one:

1. Read that portal's `robots.txt` and terms of use
2. Record your decision:

```sql
update external_sources
set robots_checked_at = now(),
    terms_reviewed = true,
    enabled = true
where id = 'opensooq';
```

Then run the crawler:

```bash
curl -X POST https://your-host/api/admin/crawl \
  -H "Authorization: Bearer $CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"maxPages": 4}'
```

It honours per-host crawl delays, respects `Retry-After`, extracts only
schema.org JSON-LD, and never passes raw page HTML into any reasoning layer.
Schedule it with Vercel Cron or `pg_cron`.

Ask each portal for a licensed feed first. It is cleaner technically and
legally, and every source goes through the same adapter interface either way.

---

## How compression works

A listing splits in two.

**Indexed columns** hold what the database must filter, sort or rank on:
price, deal type, city, bedrooms, bathrooms, area, status. These stay plain so
Postgres can index them.

**Everything else** — both descriptions, the amenity list, image metadata,
contact preferences — is `JSON.stringify`d, gzipped through
`CompressionStream` in the browser, base64'd, and stored in one `payload_gz`
column. `payload_bytes` and `raw_bytes` record the sizes so you can audit the
saving. Reading reverses it before the UI sees anything. Browsers without
`CompressionStream` fall back to uncompressed base64 with a `raw:` prefix, so
a save never fails.

The compression `ratio` is computed for the dashboard note only and is
deliberately not sent to the database; there is no such column, and including
it would make PostgREST reject the entire insert.

The trade: you cannot filter *inside* `payload_gz` in SQL. That is deliberate.
Anything you need to query belongs in a column; the blob is for content you
only ever read back whole.
