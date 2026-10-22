# Integration: one product, two clients

The app is a second client of the **same** backend the website uses. There is
no separate Supabase project, no copy of the data and no parallel user table.

```
                ┌──────────────── Supabase project ppqftdcdpshfokjqnuhq ───────────────┐
 website ──┐    │  Postgres + RLS (properties, inquiries, saved_searches, profiles,   │
           ├──► │  property_locations, cities, neighborhoods, external_*, favorites*) │
 mobile ───┘    │  Auth (auth.users)   Storage (listing-photos)                       │
     │          └──────────────────────────────────────────────────────────────────────┘
     │                                   ▲ service-role key (server only)
     └─ HTTPS, bearer JWT ──► Vercel: /api/ai/search, /api/account*, /api/admin/crawl (never called)
                                                                     * added in this change
```

## 1. What the app talks to

| Path | How | Credential on the device |
|---|---|---|
| `properties`, `cities`, `neighborhoods`, `inquiries`, `saved_searches`, `profiles`, `property_locations`, `external_properties_grouped`, `favorites` | supabase-dart / PostgREST | publishable key + the user's own session |
| Storage bucket `listing-photos`, folder `<user id>/` | supabase-dart storage | the user's session |
| Supabase Auth (email/password, Google, Facebook, recovery, phone one-time codes, connecting Facebook to an account) | gotrue, PKCE | none stored but the session (in the keystore) |
| Supabase public auth settings (`/auth/v1/settings`) | Dio, publishable key | none: only to see whether phone sign-in is switched on |
| `POST /api/ai/search` | Dio, `Authorization: Bearer <access token>` | the user's access token, or nothing |
| `DELETE /api/account` | Dio, bearer | the user's access token |

Never on the device: `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, partner-feed
keys, any LLM or search-API key. `/api/admin/crawl` is not referenced
anywhere in the app.

## 2. Configuration

Public values only, passed at build time (`lib/core/config/env.dart`):

| Define | Default | Meaning |
|---|---|---|
| `SUPABASE_URL` | production project | Same as the website's `NEXT_PUBLIC_SUPABASE_URL` |
| `SUPABASE_PUBLISHABLE_KEY` | production publishable key | Same as `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Public by design; RLS bounds it |
| `SITE_URL` | `https://www.akarat.ai` | The deployed website: API routes and shared links. The `www` host itself: `akarat.ai` redirects there, and a redirected DELETE or POST is not followed |
| `MAP_TILE_URL` | OpenStreetMap's tile server | Raster tiles for every map. OSM's server suits development and light use; its usage policy asks apps with real traffic to use their own provider (MapTiler, Stadia, Mapbox raster…), which may need a key in the URL |
| `GOOGLE_MAPS_ANDROID_KEY` / `GOOGLE_MAPS_IOS_KEY` | empty | Google's native map SDKs, with satellite view. Each key locked in Google Cloud to this app and the Maps SDK; Android's also reaches the manifest through Gradle. Empty: the OpenStreetMap tiles above |
| `PHONE_SIGNIN` | `auto` (`off` in `env/example.json`) | Phone sign-in: `auto` offers it once the project's Phone provider is switched on (read from the public auth settings, so no app update is needed); `off` never; `on` always (to try the screens first). Off for now, as on the website, until codes can be delivered |
| `FACEBOOK_SIGNIN` | `auto` | Facebook sign-in and connecting Facebook in Profile: `auto` offers them once the project's Facebook provider is on; `off` never; `on` always. On iOS only beside Sign in with Apple (App Store 4.8), as Google |
| `APPLE_SIGNIN` | `auto` | Sign in with Apple and connecting Apple in Profile: `auto` offers them once the project's Apple provider is on; `off` never; `on` always. Apple's own sheet on iPhone, Apple's web page on Android. While it is offered, iPhones also offer Google and Facebook |
| `OTP_CHANNEL` | `sms` (`whatsapp` in `env/example.json`, as the website) | How codes travel: `sms`, or `whatsapp` once Twilio has approved a WhatsApp sender. Only names the channel; Twilio's credentials are in Supabase |
| `APP_VERSION` | `1.0.0` | Shown in Profile |

```bash
cp env/example.json env/staging.json     # git-ignored
flutter run --dart-define-from-file=env/staging.json
```

The defaults equal the literals the website already ships in
`lib/supabase.js`, so a fresh checkout runs. Flutter cannot read Vercel's
environment; each build gets its values from the file or flags above.

Native-only secrets (never in Dart):

| Secret | Where | Committed? |
|---|---|---|
| Android upload keystore | `android/key.properties` + `.jks` | No (git-ignored) |

Message-provider credentials (Twilio Account SID, Auth Token, Messaging
Service SID) are in neither the app nor the repo: they live in the Supabase
dashboard (Authentication → Providers → Phone), and Supabase sends the codes.
Likewise Facebook's App ID and App Secret: Supabase dashboard only
(Authentication → Providers → Facebook). The app signs in through Supabase in
the browser and carries no Facebook SDK or key.

## 3. Changes made to the website repository

All backwards-compatible. **None has been deployed or applied** — that needs
your go-ahead.

### 3.1 `app/api/ai/search/route.ts`
- Accepts `Authorization: Bearer <Supabase access token>`. The token is
  verified with `auth.getUser(token)`; only then does the query run as that
  user (higher rate limit, the user's RLS). An invalid or expired token is
  treated as anonymous, never as an error. Cookie callers are unchanged.
- Malformed JSON now returns **400** (it returned an unhandled **500**, seen on
  the live deployment during the audit).
- `constraints` is copied field by field with type checks (ids must match
  `[a-z0-9_-]{1,40}`, numbers bounded) instead of being passed through.
- Verified: `npx tsc --noEmit` and `next build` both pass.

### 3.2 `app/api/account/route.ts` (new) — `DELETE /api/account`
In-app account deletion, which both app stores require. The user to delete is
taken from the verified access token only; the body must be
`{"confirm": true}`. Deletes the auth user (foreign keys cascade to profile,
listings and their inquiries and exact locations, saved searches, favourites;
inquiries the user *sent* keep their text with `sender_id` set null), then
empties `listing-photos/<user id>/`. Needs `SUPABASE_SERVICE_ROLE_KEY` on the
server (the crawler already does). Until it is deployed the app falls back to
a prefilled email to privacy@akarat.ai, which is what the privacy policy says.

### 3.3 `supabase/migrations/0014_favorites.sql` (new, additive)
One table, `favorites(user_id, property_id, created_at)`, RLS private to the
owner, insert allowed only for listings the caller can see, `anon` grant
revoked. Changes nothing existing. **Not applied.** Until it is, the app keeps
saved properties on the device and says so ("Your account can't store saved
properties yet…").

## 4. One-time setup in dashboards (needs your access)

1. **Supabase → Authentication → URL Configuration → Redirect URLs**: add
   `ai.akarat.app://login-callback`. Without it, email-confirmation,
   password-reset and Google redirects fall back to the website's Site URL —
   confirmation still succeeds (Supabase verifies before redirecting), but the
   app is not reopened and password reset from the app cannot complete.
2. **Run `0014_favorites.sql`** in the SQL Editor (optional; enables
   cross-device saved properties).
3. **Deploy** the website changes in §3 (push the branch; Vercel builds it).
4. **Google sign-in** is already enabled on the project. The app uses the
   browser flow through Supabase's callback, so no Google Cloud change is
   needed beyond step 1.
5. **Maps**: with Google Maps keys (`GOOGLE_MAPS_ANDROID_KEY`,
   `GOOGLE_MAPS_IOS_KEY`; steps in PUBLISHING.md) the maps are Google's
   native SDKs, free per map load, with Map / Satellite switching. Without
   them the app draws `flutter_map` raster tiles from `MAP_TILE_URL`
   (OpenStreetMap's own server by default, meant for light use).
6. **Phone sign-in**: Supabase → Authentication → Providers → **Phone** on,
   provider **Twilio** (Account SID, Auth Token, Messaging Service SID), and a
   low hourly SMS limit under Rate Limits. The app offers phone sign-in by
   itself once this is on (`PHONE_SIGNIN=auto`), and it is on already: until
   codes can be delivered (WhatsApp's template is pending, and SMS to Jordan
   needs a registered Sender ID), build with `PHONE_SIGNIN=off`, as the website
   is. Full steps, costs and the per-country rules: `SUPABASE.md` → Phone
   sign-in.
7. **Facebook sign-in**: a Meta for Developers app with Facebook Login, its
   *Valid OAuth Redirect URIs* set to the project's Supabase callback
   (`https://<project-ref>.supabase.co/auth/v1/callback`), the website's
   `/privacy` and `/data-deletion` pages as its privacy policy and data-deletion
   URLs, and the app switched to Live. Then Supabase →
   Authentication → Providers → **Facebook** on, with the App ID and App Secret.
   For connecting Facebook from Profile, also turn on **manual linking**
   (Authentication settings). Turn on *Confirm email* first (SECURITY_AUDIT.md
   S23). The app offers Facebook by itself once it is on (`FACEBOOK_SIGNIN=auto`).
8. **Sign in with Apple**: in the Apple Developer account, *Sign in with Apple*
   on the App ID `ai.akarat.app`, a **Services ID** whose return URL is the
   project's Supabase callback, and a **Key** for Sign in with Apple (`.p8`,
   with its Key ID and your Team ID). Then Supabase → Authentication →
   Providers → **Apple** on, *Client IDs* `ai.akarat.app,<Services ID>`, and
   the secret generated from the key (renew it every six months). For
   revoking on account deletion, `APPLE_TEAM_ID`, `APPLE_KEY_ID` and
   `APPLE_PRIVATE_KEY` in Vercel's production environment. The app offers
   Apple by itself once it is on (`APPLE_SIGNIN=auto`). Steps: the iOS guide.
9. **Reports**: run `supabase/migrations/0015_listing_reports.sql`, and read
   new reports daily (Table Editor → `listing_reports`). Until it runs,
   *Report this listing* sends an email instead.
10. **Universal / App Links (optional)**: to open `https://www.akarat.ai/en/property/<id>`
   straight in the app, publish `/.well-known/assetlinks.json` (Android, with
   the release SHA-256) and `/.well-known/apple-app-site-association` (iOS,
   with your Team ID) from the website, and add the Associated Domains
   entitlement in Xcode. The Android intent filter is already declared; until
   those files exist the links simply open the website.

## 5. Data flows, both directions

| Action | Where it lands | Seen on the other client |
|---|---|---|
| Sign up in the app | `auth.users` + `profiles` (trigger) | Sign in on the website with the same email/password |
| Sign in with a website account | same user | — |
| Sign up by phone in the app | `auth.users` (phone, confirmed by the code) + `profiles` (trigger, with the name given) | On the website only once its phone sign-in is switched on (`PHONE_SIGNIN` in `Akarat.dc.html`) |
| Continue with Facebook in the app | `auth.users` + an `auth.identities` row for Facebook + `profiles` (trigger, name from Facebook). A Facebook account whose verified email matches an existing account joins that account | On the website only once it offers Facebook too |
| Connect Facebook in the app (Profile) | an `auth.identities` row on the same user | "Continue with Facebook" then reaches this account |
| Add a phone number in the app (Profile) | the same `auth.users` row (`phone_change`, confirmed by a code to the new number) | Phone sign-in on either client then reaches this same account |
| Publish a listing in the app | `properties` (status `active`), payload gzipped exactly like the web form, photos in `listing-photos/<uid>/` | On Buy/Rent and in AI search immediately. Note: the website loads the 60 most expensive public listings (`listPublicProperties`); once there are more than 60 a cheap new listing will not show on its browse pages until that query is paginated |
| Save as draft in the app | `properties` (status `draft`) | Website dashboard lists it as Draft; its Publish button makes it live |
| Edit / hide / mark sold / delete on the website | `properties` | Next refresh: pull to refresh, returning to the app after 3 min, or reopening the listing |
| Edit / hide / mark sold / delete in the app | `properties` (+ Storage cleanup on delete) | Website on reload |
| Exact pin | `property_locations` (owner only); `properties.lat/lng` = blurred point (identical algorithm, parity-tested) | Website edit form reopens on the exact pin |
| Send an inquiry from the app | `inquiries` (policy from 0008) | Website dashboard → Inquiries |
| Save a property | `favorites` (after 0014) or device | Website keeps saved listings in memory only today |
| Save a search | `saved_searches` | Website's Saved searches tab is a placeholder today |
| Change language while signed in | `profiles.locale` | Stored on the account; the website does not read it yet |

Realtime subscriptions are not used: Realtime publication on these tables is
not configured in the migrations, and polling would cost more than it gives.
Lists refresh on pull, on return from background, and after any write made
from this device (`refreshTickProvider`).

## 6. Feature parity

Audit basis: `Akarat.dc.html` logic block, `lib/*.js`, `app/**`, migrations
0001–0011, and read-only probes of the live API and database (35 public
listings, external index empty, both crawl sources disabled, `favorites`
absent, Google + email auth enabled, email confirmation required).

| Feature | Website (actual code) | Mobile | Status |
|---|---|---|---|
| Browse buy / rent | 60 rows by price, filtered in the browser (city, type, beds, price), sort | Server-side filters (city, area, type, beds, baths, price, size, hide closed), sort, paginated 20 at a time with real counts | ✅ superset |
| Sold / rented shown greyed | yes (0011) | yes, greyscale + badge, never offered as a match | ✅ |
| AI search parsing (EN/AR, Jordanian Arabic) | `lib/aisearch.js` in browser | Dart port, **identical on 46 of 47 website parses**; reads further in the 47th ("بحدود مليون" said as a word). On top: spoken numbers in both languages, dialect words, more place spellings, "about 500 m", mixed Arabic-English | ✅ parity-tested + extended |
| Voice search | none | on-device speech recognition (Android recogniser, Apple Speech), EN and AR (Jordanian locale first), live transcript, real voice-level waveform, review-and-edit before searching | ➕ mobile only |
| Ranking + "why this matches" | `scoreListing` / `explain` | Dart port, **identical on 140 item×query pairs, both languages** | ✅ parity-tested |
| Internal retrieval | browser filters its loaded 60 | `POST /api/ai/search` (RLS, rate-limited), same post-filter; falls back to a direct query on network/5xx (not on 429) and says so | ✅ |
| External index | `external_properties_grouped` | same query | ✅ (index empty in production) |
| Portal deep links + "drops X" notes | `lib/providers.js` | Dart port, identical URLs/notes | ✅ parity-tested |
| Execution trace | timed animation | real progress (stages tick on real events) | ✅ |
| Editable brief / refinement | yes | chips remove + re-search, refine by typing, clarifications for deal / location | ✅ |
| Save a search | tab placeholder, never written | `saved_searches` create / list / run / delete | ➕ mobile only |
| Detail page | gallery, video, lightbox, specs, amenities, location (approx/exact), call, copy, share, save, similar | same + WhatsApp, pinch-zoom viewer, map preview (pin or 300 m circle) | ✅ |
| Enquire | `mailto:hello@akarat.ai` | real inquiry into `inquiries`, reaches the owner's dashboard | ➕ improved |
| Saved properties | memory only, lost on reload | persisted (account after 0014, device until then) | ➕ |
| Email sign-up / sign-in / reset | yes | yes (deep-link redirects) | ✅ |
| Google sign-in | yes | yes (browser + PKCE); on iOS beside Sign in with Apple, once its provider is on (App Store 4.8) | ✅ |
| Facebook sign-in / connecting it | yes: beside Google; connect or disconnect under the dashboard's Ways to sign in | sign in, sign up, connect and disconnect in Profile (browser + PKCE). On iOS only beside Sign in with Apple, as Google | ✅ |
| Sign in with Apple / connecting it | none | iPhone: Apple's sheet (nonce-checked ID token); Android: Apple's page through Supabase. Sign in, sign up, connect and disconnect in Profile; deleting an Apple account revokes Akarat.ai's access (server, once `APPLE_*` are set) | ➕ app only |
| Report a listing / hide an advertiser | none | *More → Report this listing* (reason + words, into `listing_reports`, 0015) and *Hide this advertiser* (on the device, everywhere; Profile shows them again) | ➕ app only |
| Phone OTP sign-in / linking | built, switched off (`PHONE_SIGNIN=false`) | built: sign in (existing accounts only), sign up with a name, add or change the number in Profile; offered automatically once the Phone provider is on | ➕ app ahead; web needs its switch flipped |
| Owner dashboard | listings, hide/publish, mark sold/rented, relist, edit, delete, inquiries, stat cards | same; delete confirmed and removes photos; inquiries received **and** sent | ✅ |
| Listing form | one sheet; map pin with Places autocomplete; precision; up to 8 files / 2 videos; drag reorder | 9-step wizard, same fields, limits and precision rules; pin by tapping the map (no Places autocomplete); device draft + server draft | ✅ (autocomplete ➖) |
| Analytics | placeholder text | honest note, no numbers (`views`/`saves` columns are never written) | ✅ |
| Messages | placeholder text | not built (no chat backend) | ⏸ |
| Bilingual + RTL, remembered | yes, Arabic default | yes; device language, else Arabic | ✅ |
| Legal pages | privacy, terms | same text | ✅ |
| Account deletion | "email privacy@akarat.ai" | in-app via `/api/account`, email fallback | ➕ needs deploy |
| Notifications | none | none | — |
| SEO pages, sitemap, crawler | yes | not applicable / server only | — |

## 7. Known gaps, stated plainly

- **Voice search is on-device only** (your choice): no audio leaves the phone
  through the app, and there is no key or cost. Accuracy depends on the
  phone's recogniser: Google's Arabic on Android is good with Jordanian
  dialect; Apple's is weaker on dialect. The reader always sees and can edit
  the transcript before it is searched. Not verified with a real voice on a
  real phone: the emulator has no microphone input, so recognition itself was
  only exercised with a fake recogniser in tests; the permission prompt,
  refusal path, listening and "didn't catch that" states were checked on the
  emulator.
- **Understanding is rule-based** (your choice): requests are read by the
  parser, extended for Jordanian phrasing. It cannot invent listings or
  features, but phrasings it does not know are not understood; the chips
  show exactly what was read, and every part can be removed or adjusted.

- **iOS has not been built** (this was developed on Windows). The project is
  configured, but no Xcode build, signing or simulator run has happened.
- **Integration tests have not been executed**: no device or emulator was
  available. They are written and gated (TESTING.md).
- **Address autocomplete** (Google Places) is not in the app; owners place the
  pin on the map. Places from a mobile client needs its own restricted key and
  billing review.
- **Explore** opens on a map of every matching listing that has a location
  (one query, capped at 500), sale and rent in different colours, pins that
  overlap grouped into numbered bubbles. Listings without a location appear in
  the list view only.
- **Amenities** are not an Explore filter: they live inside the compressed
  payload, which SQL cannot filter. AI Search scores them, as on the website.
- **Website follow-ups** to complete the round trip: read `favorites` in
  `toggleSaved`, list `saved_searches` in the dashboard tab, and paginate
  `listPublicProperties`.
