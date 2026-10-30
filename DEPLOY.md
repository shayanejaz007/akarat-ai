# Akarat.ai — Deployment Guide

Bilingual (English / Arabic) Jordanian property marketplace.
Next.js 14 App Router + Supabase (Postgres, Auth, Storage).

---

## 1. What this project actually is

Worth understanding before you touch anything, because it is not a conventional
Next.js app.

The **entire user-facing site is one file**: `Akarat.dc.html`. It contains the
markup, the styles, and roughly 2,000 lines of application logic inside a
`<script type="text/x-dc">` block. A runtime, `support.js`, compiles that block
into React elements in the browser at load time.

**Next.js handles only** the API routes (`/api/ai/search`, `/api/admin/crawl`),
the auth middleware, and the document metadata. It does not render the site.
`next.config.mjs` rewrites `/`, `/en`, and `/ar` to the static document.

Practical consequences:

- Editing the site means editing `Akarat.dc.html`, not React components.
- `public/` is **generated**. Never edit files there; they are overwritten on
  every build by `scripts/sync-public.mjs`. Edit the copies at the repo root.
- Search engines receive HTML with no listings in it. Everything is client
  rendered. See §9.

---

## 2. Project structure

```
akarat-ai/
│
├── Akarat.dc.html            THE SITE. Markup + styles + all app logic.
│                             Everything the user sees is in this one file.
├── support.js                Vendor runtime that compiles and renders the
│                             above. Generated — do not hand-edit.
│
├── app/                      Next.js App Router — API and metadata only
│   ├── layout.tsx            Root layout (does not render the marketplace)
│   ├── metadata.ts           Site-wide SEO defaults
│   ├── robots.ts             /robots.txt
│   ├── sitemap.ts            /sitemap.xml, from active listings
│   ├── [lang]/property/[id]/
│   │   └── page.tsx          SERVER-RENDERED listing page — see §9
│   └── api/
│       ├── ai/search/route.ts     AI search: our listings + external
│       │                          providers. SSRF guard + rate limit.
│       └── admin/crawl/route.ts   External-source crawler. Service-role
│                                  key, protected by CRON_SECRET.
│
├── lib/                      Browser-side modules, loaded by the document
│   ├── supabase.js           Supabase client, payload gzip, listing CRUD,
│   │                         media upload to Storage
│   ├── listing-server.ts     Server-side listing reads + payload gunzip
│   ├── reference.ts          GENERATED from data/market.js — do not edit
│   ├── aisearch.js           Query parsing (EN + AR), scoring, explanations
│   └── providers.js          External listing-source adapters
│
├── data/
│   └── market.js             Static reference data: cities, neighbourhoods,
│                             property types, amenities
│
├── utils/supabase/           Server-side Supabase helpers (SSR cookies)
│   ├── client.ts
│   ├── server.ts
│   └── middleware.ts
│
├── assets/                   Images and video used by the document
│   ├── akarat-mark.png       Brand mark (transparent)
│   ├── favicon-32.png
│   ├── apple-touch-icon.png
│   ├── hero-jordan.mp4       Hero background video (~40 MB)
│   ├── jordan-hero-v3.png    Hero poster frame
│   └── star-*.svg
│
├── supabase/
│   ├── migrations/           RUN IN ORDER. See §4.
│   │   ├── 0001_init.sql             Tables, RLS, indexes
│   │   ├── 0002_external_index.sql   External listing index
│   │   ├── 0003_dedupe.sql           Duplicate grouping
│   │   ├── 0005_grants.sql           Role grants
│   │   ├── 0006_listing_photos.sql   Storage bucket + policies
│   │   ├── 0007_listing_video.sql    Widens bucket for video
│   │   ├── 0008_hardening.sql        Inquiry policy + rate-limit table
│   │   └── 0009_locations.sql        All cities + areas (generated)
│   ├── diagnose.sql          Read-only health check
│   └── cleanup-samples.sql   Removes seeded sample rows
│
├── scripts/
│   ├── gen-reference.mjs     Mirrors data/market.js into lib/reference.ts
│   ├── gen-locations-sql.mjs Writes migration 0009 from data/market.js
│   └── sync-public.mjs       Build step. Copies the document, support.js,
│                             assets, lib and data into public/. Vendors
│                             React locally. Generates public/config.js
│                             from environment variables.
│
├── middleware.ts             Session refresh on /api, /dashboard, /list
├── next.config.mjs           Rewrites + security headers
├── .env.example              Environment variables — copy to .env.local
└── package.json
```

There is no `migration 0004`. That gap is intentional; nothing is missing.

---

## 3. Environment variables

Copy `.env.example` to `.env.local` for local work, and set the same four in
your host's dashboard for production.

| Variable | Where it is used | Notes |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Browser + server | Baked into `public/config.js` at build time |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Browser + server | Publishable key. Safe to expose — RLS decides what it can reach |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only | **Bypasses RLS.** Never expose to the browser, never commit |
| `CRON_SECRET` | Server only | Bearer token guarding `/api/admin/crawl` |
| `ANTHROPIC_API_KEY` | Server only | The AI advisor (`/api/ai/advisor`) and listing translation (`/api/translate`). Unset, the advisor says it is unavailable and the page falls back to its plain search, and the forms leave the other language to the owner |
| `AI_ADVISOR_DAILY_TOTAL` | Server only | Optional. Questions per day for everyone together, the ceiling on what a day can cost. Default 600 |
| `AI_ADVISOR_DAILY_PER_IP` / `AI_ADVISOR_DAILY_PER_USER` | Server only | Optional. Questions per day for one signed-out visitor / one signed-in account. Defaults 30 and 80 |
| `AI_ADVISOR_PER_MINUTE_IP` / `AI_ADVISOR_PER_MINUTE_USER` | Server only | Optional. Per minute, the same two. Defaults 5 and 8 |
| `AI_ADVISOR_MODEL` / `AI_ADVISOR_EFFORT` | Server only | Optional. Default `claude-opus-5-5` at `low` effort. `claude-sonnet-5-5` costs half as much per token |
| `AI_ADVISOR_PORTALS` / `AI_ADVISOR_RESEARCH_DOMAINS` | Server only | Optional. Extra sites the advisor may search and read: `example.jo=Example` pairs for listing portals, plain hosts for research. Add only sites whose terms allow it |
| `AI_ADVISOR_SECRET` | Server only | Optional. Signs the conversation the browser holds. Defaults to a key derived from `ANTHROPIC_API_KEY`; set it only to rotate conversations independently of the API key |
| `ADMIN_PASSWORD` | Server only | The password for the admin panel at `/admin`. Change it here and redeploy to sign every admin out |
| `BACKFILL_SECRET` | Server only | Any long random string. Guards `/api/admin/backfill-translations`, which translates listings saved before translation existed: `BACKFILL_SECRET=… npm run backfill:translations` (dry run), then again with `-- --apply` |

If the two `NEXT_PUBLIC_*` variables are unset, the app falls back to literals
in `lib/supabase.js` so a fresh checkout still runs. Set them properly in
production so staging and production can point at different projects.

External provider API keys, if you use them, go in the same place — see
`lib/providers.js` for the names each adapter reads.

---

## 4. Database setup

Run the migrations **in numeric order** in the Supabase SQL editor
(Dashboard → SQL Editor → New query → paste → Run). Each is idempotent, so
re-running a migration you have already applied is safe.

```
0001_init.sql
0002_external_index.sql
0003_dedupe.sql
0005_grants.sql
0006_listing_photos.sql
0007_listing_video.sql      ← required before video upload works
0008_hardening.sql          ← required for the shared rate limiter
0009_locations.sql          ← required: every city and area the form offers
0010_location.sql
0011_sold_visible.sql
0012_storage_no_listing.sql
0013_protect_trust_fields.sql
0014_favorites.sql
0015_listing_reports.sql
0016_revoke_stray_anon_reads.sql
0017_service_role_grants.sql
0018_admin_analytics.sql    ← the admin panel
0019_daily_rentals.sql      ← daily rentals
0020_ai_advisor.sql         ← the AI advisor's daily limits and usage figures
```

If the project is already live, run **0007, 0008 and 0009** in that order.
All three are safe to run again if you are not sure whether you already did.

### What 0009 does
`properties.city_id` and `properties.neighborhood_id` are foreign keys into the
`cities` and `neighborhoods` tables. The listing form offers every place in
`data/market.js` (22 cities, 52 areas), but the database was only seeded with
9 and 15. Picking any of the others failed with:

```
insert or update on table "properties" violates foreign key constraint
"properties_neighborhood_id_fkey"
```

0009 upserts every place into the database. It is **generated** from
`data/market.js` — after adding or renaming a place there, run
`npm run gen:locations` and run the regenerated file in Supabase.

### What 0007 does
Widens the `listing-photos` Storage bucket to accept `video/mp4`, `video/webm`
and `video/quicktime`, and raises the per-object size limit to 50 MB. Until it
runs, video uploads fail the bucket's MIME check.

### What 0008 does
Two fixes:

1. **Inquiries.** The original policy was `with check (true)`, meaning anyone
   could insert a row naming any owner against any property, real or not. Now
   the `owner_id` must be the genuine owner of a real, active listing.
2. **Rate limiting.** Adds a `rate_limits` table and a `check_rate_limit`
   function so the AI search limit is shared across serverless instances. The
   previous in-memory counter reset on every cold start and was never shared,
   so it enforced nothing in practice.

### Verify
```sql
-- paste supabase/diagnose.sql, or spot-check:
select id, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'listing-photos';

select tablename, policyname from pg_policies
 where schemaname = 'public' order by tablename;
```

---

## 5. Local development

```bash
npm install
cp .env.example .env.local        # then fill in your values
npm run dev                       # http://localhost:3000
```

`npm run dev` triggers `predev`, which runs `scripts/sync-public.mjs` and
rebuilds `public/`. **After editing any root file** (`Akarat.dc.html`,
`support.js`, anything in `lib/`, `data/` or `assets/`) the sync must run
again — restart the dev server, or run `node scripts/sync-public.mjs` manually.

Expect this line on a healthy sync:

```
sync-public: public/ is up to date (react vendored: 2/2, supabase config from env: yes)
```

`react vendored: 0/2` means `npm install` has not run. The site still boots —
it falls back to the unpkg CDN — but you lose the local-serving benefit.

---

## 6. Deploying to Vercel

1. **Push to GitHub.** Set the repository to **private**. If
   `SUPABASE_SERVICE_ROLE_KEY` or `CRON_SECRET` were ever committed at any
   point in the history, rotate them in the Supabase dashboard first.
2. **Import the repo** at vercel.com → Add New → Project. Framework preset
   auto-detects as Next.js. Leave the build command and output directory alone.
3. **Add the four environment variables** from §3 under Settings →
   Environment Variables, for Production and Preview.
4. **Deploy.** The build runs `prebuild` → `sync-public.mjs` → `next build`.
5. **Point your domain** at the deployment under Settings → Domains.
6. **Update Supabase Auth URLs**: Dashboard → Authentication → URL
   Configuration. Set Site URL to your domain and add it to Redirect URLs, or
   email confirmation links will point at localhost.

### Any other host
Anything that runs Next.js 14 works — Netlify, Render, Fly, a container.
`npm run build && npm start`. There is nothing Vercel-specific in the config.

---

## 7. Post-deploy checklist

- [ ] `/` loads and the hero video plays
- [ ] `/en` and `/ar` load (they should **not** 404 — the canonical and
      hreflang tags point at them)
- [ ] Browser console is clean on the home page and a listing page
- [ ] Language toggle switches to Arabic and the layout flips to RTL
- [ ] Buy / Rent pages show **4 listings per row** on desktop, 1 on mobile
- [ ] Sign up, then publish a listing with photos **and** a video clip
- [ ] The listing's first photo appears in the **large frame** on the detail
      page, not only in the thumbnail strip
- [ ] Clicking a thumbnail promotes it into the large frame
- [ ] AI search returns your own listings (try a query matching one you just
      created) and "View property" opens it
- [ ] Favicon and Apple touch icon render
- [ ] `curl -I https://yourdomain.com` shows `strict-transport-security` and
      `x-content-type-options`
- [ ] `/sitemap.xml` lists your listings and `/robots.txt` loads
- [ ] `curl -s https://yourdomain.com/en/property/<id> | grep RealEstateListing`
      matches — this is the SEO check that matters
- [ ] Opening a listing puts `?property=<id>` in the address bar; back returns
      to the grid

---

## 8. Operations

### The admin panel
`/admin` (app/admin) shows people on the site and app right now, daily views,
inquiries and sign-ups, the most viewed and most inquired listings, and every
listing, inquiry, account and report, with the actions on each (status,
feature, verify, delete; inquiry status; role; report decisions).

It needs `supabase/migrations/0018_admin_analytics.sql` (view and session
tracking, and the aggregates), `SUPABASE_SERVICE_ROLE_KEY` on Vercel with
0017's grants, and `ADMIN_PASSWORD`: the panel's one password. To change it,
edit `ADMIN_PASSWORD` in Vercel → Settings → Environment Variables and
redeploy; every open admin session ends, since the session cookie is signed
with the password. Sessions otherwise last 12 hours, and sign-in allows five
attempts a minute per IP address.

Every `/api/admin/*` route checks that cookie on the server; the page itself
holds no privileged key. Views and "live now" are counted from the website and
from app version 1.0.2 on.

### Daily rentals
Short stays priced per night, in their own tab on the website (Daily rentals)
and in the app (Daily, next to Explore). Run
`supabase/migrations/0019_daily_rentals.sql` after 0018. Until it runs, the
tab is empty and choosing "Daily rental" in the listing form says so; nothing
else changes.

- **Listing.** An owner chooses "Daily rental" in the listing form and gives
  a price per night, how many it sleeps and a minimum stay. The listing's
  phone is never published; it carries a grey check and is visible only to
  its owner until approved.
- **Review.** `/admin` → Daily rentals: approve, reject (with a reason the
  owner sees), suspend, revoke or reinstate. Approval makes it public on the
  website and the app and turns its check green. Edits to an approved
  listing keep it live and appear under "Changed since approval".
- **Requests.** A signed-in renter picks dates on the listing's calendar
  (taken nights are crossed out) and sends a request with the number of
  guests. The owner approves it from their dashboard (website) or Bookings
  (app), choosing the number to share; only then does that renter see it,
  with a WhatsApp button. The owner confirms once the stay is agreed, which
  closes those nights and declines overlapping requests. The database refuses
  two confirmed stays on the same night, whoever writes them.
- **Notifications.** New requests, answers and review decisions arrive in
  the dashboard (website) and under Profile → Notifications (app), live.
  There are no push notifications or emails yet.
- **Admin.** `/admin` → Bookings lists every request with renter, owner,
  dates, total and status.

### The AI advisor
The "Search with AI" page is a conversation with a property advisor built on
Claude (`/api/ai/advisor`, code in `lib/advisor/`). It searches Akarat.ai's
listings first, then two Jordanian portals and a fixed list of official, news
and research sites, and answers in English or Jordanian Arabic with listing
cards, comparisons, cited sources and follow-up questions. Voice input uses
the browser's own speech recognition.

- **Turn it on.** `ANTHROPIC_API_KEY` in Vercel (already set if listing
  translation works), then run `0020_ai_advisor.sql`. Without 0020 the
  advisor works, but its daily limits are counted per server instance, which
  is weaker, and the admin panel has no AI figures.
- **Anthropic Console.** Web search and web fetch must be enabled for the
  organisation (Settings → Capabilities). They are on unless someone turned
  them off; if they are off, every question fails with "isn't available".
- **What it costs.** On Claude Opus 5.5, a question answered from Akarat.ai's
  listings is typically 3 to 8 US cents; one that also searches the web and
  reads a page or two, 10 to 30 cents (each web search is a cent on top of
  tokens). `AI_ADVISOR_DAILY_TOTAL` caps the number of questions a day; at the
  default of 600 the worst day is roughly $60-180. Raise it as traffic grows,
  or set `AI_ADVISOR_MODEL=claude-sonnet-5-5` to halve the per-token price.
  Past the cap, visitors get the plain search and a note to come back later.
  `/admin` → Overview → AI advisor shows each day's questions and an estimated
  cost; the Anthropic Console has the invoice.
- **What it will not do.** It reads only public listings (Row Level Security,
  as a visitor), never owners' contact details, and never a site outside its
  list. An outside listing is shown only if its exact link came back from a
  search, and with only the figures found on the page itself. Details in
  SECURITY-AUDIT.md → AI advisor.
- **Check it with the real model** after deploying (spends about $1-4):
  `SITE_URL=https://www.akarat.ai node scripts/advisor-live-check.mts`. It
  asks in English, Jordanian Arabic, formal Arabic and a mix, asks an
  investment question, and tries the attacks the advisor must refuse.
- **Tests without the model:** `npm run test:advisor`.
- **The app** still uses its own on-device search (`/api/ai/search`, which is
  unchanged). The advisor's API takes the same bearer token the app already
  sends, so the app can move to it later without server changes.

### The crawler
`/api/admin/crawl` refreshes the external listing index. It requires
`Authorization: Bearer $CRON_SECRET`. To run it on a schedule, add to
`vercel.json`:

```json
{ "crons": [{ "path": "/api/admin/crawl", "schedule": "0 3 * * *" }] }
```

Vercel cron requests carry the secret automatically when `CRON_SECRET` is set.

### Media storage costs
Listing media goes to the `listing-photos` Storage bucket: images up to 6 MB,
video up to 50 MB, two clips per listing. Video is where Supabase egress adds
up fastest. If volume grows, move video to a dedicated host and store only the
URL — the payload already carries a `type` field per media entry, so the
gallery needs no changes.

### Backups
Supabase Dashboard → Database → Backups. On the free tier, take a manual
`pg_dump` before running migrations on live data.

---

## 9. SEO and shareable listing URLs

The marketplace document is client-rendered, so a crawler that does not run
JavaScript sees no listings in it. Rather than rebuild the whole app into Next
routes, the pages that matter for search are server-rendered alongside it:

| Route | What it is |
|---|---|
| `/en/property/<id>`, `/ar/property/<id>` | Real server-rendered HTML per listing: title, price, location, photos, video, specs, description, amenities, plus schema.org `RealEstateListing` JSON-LD, canonical and hreflang. Revalidated every 5 minutes. |
| `/sitemap.xml` | Generated from active listings, both languages. This is how listings get discovered — nothing else links to them in the served HTML. |
| `/robots.txt` | Allows everything except `/api/`, points at the sitemap. |

These also give a listing a **URL for the first time**. Previously a property
existed only as client state, so there was no link to share. Opening a listing
in the app now writes `?property=<id>` into the address bar, the back button
works, and `/en/property/<id>` is a proper landing page whose call to action
opens that listing inside the app.

After deploying, submit `https://yourdomain.com/sitemap.xml` in Google Search
Console. Indexing takes days to weeks.

The grid, search and dashboard stay client-rendered. That is fine — they are
not the pages you want ranking.

## 10. Known limitations

Documented so they are decisions rather than surprises.

**Supabase SDK loads from esm.sh** at runtime (`lib/supabase.js`). React is
served from your own origin, but the database client is still a third-party
CDN dependency in the critical path for all data loading.

**Rate limiting fails open.** If the database is unreachable,
`check_rate_limit` allows the request. Deliberate: a limiter that takes search
down during a database hiccup is worse than the abuse it prevents.

**One size limit per bucket.** Storage cannot express separate image and video
caps, so the bucket allows 50 MB for both. The 6 MB image limit is enforced by
the listing form and by `lib/supabase.js`, which is a courtesy, not a control.

**Outside listings come from search, not from feeds.** No Jordanian portal
offers a public listings API, and crawling them without permission is not an
option (SEARCH-ARCHITECTURE.md). The advisor uses Anthropic's web search over
an index, and reads individual pages with Anthropic's fetcher, which honours
each site's robots.txt. So outside results are whatever those portals let a
search engine see: some ads will be missing, and an ad can disappear between
the search and the click. Outside listings never show the portal's photos;
the card names the site and links to the ad instead. A licensed feed slots in
through the adapter in `app/api/ai/search/route.ts`.

**Voice needs a browser with speech recognition.** Chrome, Edge, Safari and
Samsung Internet have it; Firefox and most in-app browsers (Instagram,
Facebook) do not, and there the microphone is simply not shown. Recognition
runs in the browser's own speech service (Google's in Chrome, Apple's in
Safari); no audio reaches our server. A server-side transcriber would cover
the rest, but needs a second provider account and key.

**The advisor has 60 seconds.** That is the function limit on every Vercel
plan. It stops researching at about 38 seconds and finishes the answer with
what it has; at 54 it ends the reply and says so. On a Pro plan the limit can
be raised in `app/api/ai/advisor/route.ts` together with `TURN` in
`lib/advisor/config.ts`.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Blank page, console shows React undefined | `public/vendor/` missing | `npm install`, then rebuild |
| Edits to `Akarat.dc.html` do nothing | `public/` is stale | `node scripts/sync-public.mjs` |
| Video upload fails with a MIME error | 0007 not applied | Run `0007_listing_video.sql` |
| "Media storage is not set up yet" | Bucket missing | Run `0006` then `0007` |
| Listings do not appear | Rows not `status = 'active'`, or RLS | Run `supabase/diagnose.sql` |
| `/en` returns 404 | Old `next.config.mjs` | Use the current one — it rewrites `/en` and `/ar` |
| Confirmation emails link to localhost | Supabase Auth URLs unset | Set Site URL (§6, step 6) |
| AI search returns nothing | Migrations behind, or no active listings | Check `status`, then run `diagnose.sql` |
| `violates foreign key constraint properties_neighborhood_id_fkey` | An area in the form is missing from the database | Run `0009_locations.sql` |
| Hero video freezes | Old build | Current build resumes it automatically |

**Next.js 14.** Pinned to 14.2.35, the latest patched 14.x. `npm audit` still
reports advisories against the whole 14 line that are only fixed in 16.x. They
are mostly DoS and cache-poisoning issues in features this app does not use:
no `next/image`, no Server Actions, no Pages Router i18n, no custom server.
Moving to 16 also means React 19, which no longer ships the UMD builds the
marketplace document loads, so the browser React would need pinning
separately. Worth scheduling as its own piece of work.
