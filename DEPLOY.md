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
│   │   └── 0008_hardening.sql        Inquiry policy + rate-limit table
│   ├── diagnose.sql          Read-only health check
│   └── cleanup-samples.sql   Removes seeded sample rows
│
├── scripts/
│   ├── gen-reference.mjs     Mirrors data/market.js into lib/reference.ts
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
```

If the project is already live and you are applying this update, you only need
**0007** and **0008**.

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

**Next.js 14.** Pinned to 14.2.35, the latest patched 14.x. `npm audit` still
reports advisories against the whole 14 line that are only fixed in 16.x. They
are mostly DoS and cache-poisoning issues in features this app does not use:
no `next/image`, no Server Actions, no Pages Router i18n, no custom server.
Moving to 16 also means React 19, which no longer ships the UMD builds the
marketplace document loads, so the browser React would need pinning
separately. Worth scheduling as its own piece of work.
