# Locations: the map pin, and the Google key behind it

Owners can search for their property's address, drop a pin on the exact
building, and decide whether buyers see that pin or a circle around it.

This document is the setup. It takes about fifteen minutes, and the app runs
fine without any of it — with no key configured the listing form keeps the
city and area dropdowns it has always had, and Google is never contacted.

## What was added

| Piece | Where |
|---|---|
| Autocomplete, map picker, pin→area snapping, blurring | `lib/geo.js` |
| `location_precision`, `address`, `property_locations` | `supabase/migrations/0010_location.sql` |
| `updateProperty`, `saveExactLocation`, `getExactLocation` | `lib/supabase.js` |
| Location block in the listing sheet, Edit on dashboard rows | `Akarat.dc.html` |
| `mapsKey` baked into `public/config.js` | `scripts/sync-public.mjs` |

## Two coordinates, on purpose

This is the part worth understanding before you turn it on.

RLS on `properties` says *active listings are public*. That is a rule about
rows, not columns: every column of an active listing is readable with the anon
key, `lat` and `lng` included. An exact coordinate written to `properties` is
a published coordinate, no matter what the interface chooses to draw.

So the pin is stored twice:

```
properties.lat / lng          what the world may see
                              exact if the owner chose exact,
                              displaced up to ~300 m if they chose approximate

property_locations.lat / lng  the real point
                              readable by its owner and nobody else
```

The displacement is deterministic, seeded from the coordinates themselves, so
the circle lands in the same spot on every save and every render. A fresh
random offset per read would let anyone average many reads back to the truth.
It is also an offset rather than a rounding, because rounding to three
decimals snaps to a grid, and a grid tells you which cell the real point is in.

`approximate` is the default, including for listings that existed before this
migration. An owner who never opened the map does not get their address
published by accident.

## Step 1 — run the migration

Open the Supabase SQL Editor and run `supabase/migrations/0010_location.sql`.

It is safe on a database with listings in it: existing rows keep their
coordinates and default to `approximate`. It is safe to run twice.

At this point the Edit button works and listings can be corrected. The map
needs the rest.

## Step 2 — create the Google Cloud project

1. Go to <https://console.cloud.google.com/> and sign in.
2. Create a project. Call it `akarat-ai`.
3. **Enable billing on it.** Google Maps will not serve a single tile without
   a billing account attached, even inside the free allowance. Billing →
   Link a billing account.

## Step 3 — enable exactly two APIs

APIs & Services → Library. Enable:

- **Maps JavaScript API** — draws the map and the draggable pin
- **Places API (New)** — address autocomplete

Enable nothing else. Every enabled API is another thing a stolen key could be
spent on.

## Step 4 — create the key, and restrict it

APIs & Services → Credentials → Create credentials → API key.

Before you copy it, click **Edit API key** and set both restrictions. An
unrestricted Maps key found in a page source is somebody else's free quota,
billed to you.

**Application restrictions** → Websites. Add, as separate entries:

```
https://your-domain.com/*
https://*.your-domain.com/*
http://localhost:3000/*
```

**API restrictions** → Restrict key → tick only *Maps JavaScript API* and
*Places API (New)*.

Save. The restrictions take a few minutes to propagate.

## Step 5 — cap the spend

This is the step people skip and regret.

1. Billing → Budgets & alerts → Create budget. Set a monthly amount you are
   willing to lose — $50 is a sensible starting point — and alerts at 50%,
   90% and 100%.
2. APIs & Services → each API → Quotas. Set a daily request cap on both. A
   budget alert emails you after the money is gone; a quota stops the
   requests.

Google's allowance covers roughly 28,000 map loads a month at the time of
writing, which is far more than a launching marketplace uses. Autocomplete is
billed per session rather than per keystroke, which is why `lib/geo.js` mints
a session token per editing session and retires it on selection. Do not remove
that.

## Step 6 — configure and run

Paste the key into `.env.local` (the file is already there, and `.gitignore`
covers it):

```bash
NEXT_PUBLIC_GOOGLE_MAPS_KEY=AIza...
```

No quotes, no spaces around the `=`. Then **restart**:

```bash
npm run dev     # or npm run build
```

Restarting is not optional. The key is baked into `public/config.js` by
`scripts/sync-public.mjs` when the server starts, not read per request, so
nothing picks up a change to `.env.local` while the server is running.

That script reads `.env.local` itself, because loading it is a Next.js
feature and the script runs as plain Node from `predev`. A real environment
variable still wins, so Vercel and CI are unaffected.

The startup line tells you whether it worked:

```
sync-public: ... google maps: on
sync-public: no NEXT_PUBLIC_GOOGLE_MAPS_KEY — the listing form will use ...
```

On Vercel: Settings → Environment Variables. This one **is** browser-visible,
so unlike `SUPABASE_SERVICE_ROLE_KEY` it is fine in all environments — its
safety comes from the referrer restriction in step 4, not from secrecy.

## Why a key in the browser, when SEARCH-ARCHITECTURE.md forbids it

That document's rule is right, and this is genuinely the exception, for the
same reason the Supabase publishable key is one: it is bounded somewhere the
browser cannot reach.

A Brave or Anthropic key has no such boundary. Whoever holds it is you, can
spend your quota from anywhere, and you find out on the invoice. A Maps key
restricted to your domains is refused when it is used anywhere else, is
refused for any API you did not tick, and stops at the quota you set.

There is also no alternative. An interactive map is tiles fetched by the
browser; a proxy in front of it would just be your server paying for the same
tiles and re-serving them, against Google's terms.

What stays server-side is any **Geocoding or Places key called from a
server**, because a referrer restriction cannot cover a server call. If you
add server-side geocoding later, give it a second key restricted by IP, and
put it behind `/api` like the search route.

## Verifying

1. Sign in, open **Sell**, and scroll to *Location on the map*. Nothing there
   means no key: check `public/config.js` contains `mapsKey`.
2. Type `Abdoun Circle`. Suggestions should appear after the third character.
3. Pick one. The pin moves, and the City and Area dropdowns snap to Amman /
   Abdoun on their own — coordinates never replace those fields, because they
   are foreign keys that search, dedupe and the Arabic place names all read.
4. Drag the pin somewhere in Sweifieh. Area should follow.
5. Leave it on *Approximate circle*, publish, then open the listing. The
   location line should read "approximate location", and the map link should
   point somewhere near but not at the building.
6. Dashboard → **Edit** on that listing. The pin should return to the exact
   spot you placed, not the blurred one.

## Deploying on Vercel

Set `NEXT_PUBLIC_GOOGLE_MAPS_KEY` under Settings → Environment Variables.
`prebuild` runs on Vercel, real environment variables take precedence over any
file, and `.env.local` is not in the repository, so the key flows straight
into `public/config.js`. Three things catch people out:

1. **Environment variables do not apply to deployments that already exist.**
   Adding the key changes nothing until you redeploy. Deployments →
   ⋯ → Redeploy, or push a commit.
2. **Tick every environment you use.** A key set for Production only is
   absent from preview deployments, and the form there falls back to
   dropdowns.
3. **Preview URLs are different domains.** Vercel gives each deployment its
   own `*.vercel.app` hostname, and the key's referrer list must include it or
   Google refuses. Add `https://*.vercel.app/*` alongside your real domain
   while you are still testing, and drop it once you are on the custom domain.

Because the key is baked in at build time, changing it later also needs a
redeploy.

## Two headers to keep in mind

`next.config.mjs` sets no Content-Security-Policy today, which is why the map
works. `SECURITY-AUDIT.md` lists adding one as a pre-launch task — when you
do, it has to allow Google or the map silently stops loading:

```
script-src  'self' https://maps.googleapis.com
img-src     'self' data: https://*.googleapis.com https://*.gstatic.com
connect-src 'self' https://maps.googleapis.com
style-src   'self' 'unsafe-inline' https://fonts.googleapis.com
font-src    'self' https://fonts.gstatic.com
```

`Referrer-Policy: strict-origin-when-cross-origin` is already set and is
compatible: it still sends the origin to Google, which is what the referrer
restriction matches on. Do not change it to `no-referrer` — that would make
every restricted key fail.

Separately, `Permissions-Policy` disables `geolocation`. Nothing here uses it,
but a future "use my current location" button would need that relaxed.

## When it does not work

Every one of these reports itself in the form, under the map, rather than
looking like "no results". If you see nothing at all there, the key never
arrived — check the `sync-public` line from step 6 first.

| What you see | Cause | Fix |
|---|---|---|
| No *Location on the map* section | Key not in `public/config.js` | Check `.env.local`, then restart. `cat public/config.js` should show your key |
| Grey box, "Google rejected the key" | Billing off, domain not in the referrer list, or Maps JavaScript not in the key's API restrictions | Steps 3–5. The browser console names which one |
| Map fine, "Places API (New) is not available" | Places API (New) not enabled, or not ticked in the key's API restrictions | Steps 3 and 4 |
| Suggestions never appear, no error | Fewer than three characters typed | Type more; nothing is sent before the third character |
| "For development purposes only" watermark | Billing not enabled | Step 2.3 |
| Area dropdown snaps somewhere unexpected | The pin is more than 6 km from any known area, so only the city is set | Expected. Add the area to `data/market.js` and run `npm run gen:locations` |
| Saving fails, "location columns are not set up" | `0010_location.sql` has not been run | Step 1 |

Restrictions take a few minutes to propagate after you save them in the Cloud
console. A key that looks wrong immediately after editing may just be early.

## Costs, plainly

| | Billed |
|---|---|
| Map load in the listing form | per load, only when an owner opens the form |
| Autocomplete | per session — a whole typed address plus one selection |
| Listing pages | nothing; the map link is an ordinary URL |
| Browsing, searching, the home page | nothing; Google is never loaded |

Only the listing form loads Google at all. A visitor who never sells is never
a cost.
