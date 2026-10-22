# Testing

```bash
flutter pub get
dart format --set-exit-if-changed lib test integration_test
flutter analyze
flutter test                      # unit + widget, no network, no device
```

Don't run `flutter test`/`analyze`/`pub get` while a release build is in
progress: each rewrites `GeneratedPluginRegistrant.java` with dev-only plugins
(`integration_test`), which the release Gradle build then fails to compile.

No unit or widget test touches Supabase or Vercel: every repository is
replaced by a fake (`test/support/fakes.dart`, `harness.dart`), and the one
real `SupabaseClient` in the harness points at an unresolvable host.

## What runs today (last run on this branch)

| Suite | Tests | Result |
|---|---|---|
| `test/unit/query_parser_test.dart` | 52 — 47 parses (39 standalone queries + two 4-turn refinement chains) vs the website's `parseQuery`, plus 5 brief examples | ✅ pass |
| `test/unit/ranker_test.dart` | 140 item×query pairs × (score, explain EN, explain AR) vs the website | ✅ pass |
| `test/unit/geo_phone_links_test.dart` | blur, 300 m bound, area snapping, phone E.164/pretty, WhatsApp/tel targets, portal URLs + notes (EN/AR), reference data vs `data/market.js` | ✅ pass |
| `test/unit/payload_listing_test.dart` | payload packed by the website decodes; round trip; tolerant reads; `Listing.fromRow`; price/date formatting | ✅ pass |
| `test/unit/search_repository_test.dart` | through a fake HTTP adapter: request body is the website's constraints object; website filter (budget ×1.15, closed listings dropped); stable ranking; **429 stays "rate limited"** (a real bug this caught); partner-feed rows kept external | ✅ pass |
| `test/unit/controllers_test.dart` | interface language follows the device, live, until the reader picks one; favourites (guest, merge on sign-in, rollback, migration-missing fallback); wizard save (blur, exact pin, address rule, draft status, required fields, no double upload after a failure, edit keeps status, removed files deleted); AI search (refine, chip removal, 429); explore pagination; draft round trip | ✅ pass |
| `test/widget/screens_test.dart` | property card (fields, SOLD, heart); Home (real rows, honest empty, error + retry, Arabic RTL); AI search (idle, live preview without sending, results + reasons + portals, no-match); details (specs, amenities, approximate location, inquiry validation and delivery, sold takes no inquiries, missing listing); sign-in validation; filters sheet; listing wizard steps + Arabic digits; language switch keeps the session | ✅ pass |
| `test/widget/design_flows_test.dart` | the interactions the design pass changed: Saved tab links switch tabs every time; saved-search delete + Undo; dashboard actions behind More and a confirmed delete; no all-zero stats; count steppers (rapid taps, "not given"); review step's bar; "Search for similar" sends the listing's facts; contact actions appear once | ✅ pass |

| `test/widget/map_and_tours_test.dart` | text direction by first strong letter; Explore opens on the map with sale and rent pins, a pin opens its preview, Rent filters the map; map ↔ list; the spotlight tour forward/back/done; Home's tour runs once on first visit; the listing tour on a first listing | ✅ pass |

| `test/widget/voice_search_test.dart` | locale choice (Jordanian Arabic first, then Levantine); voice: live words → review → search with the right brief; refused microphone; Arabic switch; no Arabic recogniser; silence; conversation: no-match alternatives that really re-search, budget quick-picks | ✅ pass |

| `test/widget/sign_up_test.dart` | sign-up says what happened: a full "Check your email" page when confirmation is on; an "account ready" confirmation, then Home, with the new account owed its welcome tour; the tours a guest already took travel with the account; signing in from the Log in button returns to where the reader was (under a real router) | ✅ pass |
| `test/widget/launch_splash_test.dart` | the opening: its first frame is the launch screen (the logo, its place and size); the intro plays muted, once, mixing with other audio, without keeping the screen on, fitted to the screen; the app starts once the intro is in and is only put on screen when it has settled; Skip (after a moment, clear of the gesture bar) and a tap end it; a slow start shows the loading line until the app is ready; a clip that cannot play gets the coded build, a slow one leaves the logo and goes to the app; an intro stalling mid-way still lets the app through; reduced motion; Skip in the reader's language; paused in the background; landscape. On Android: the natively prepared intro (mocked channel) plays from the first frame and is released | ✅ pass |
| `test/widget/onboarding_tour_test.dart` | tour progress: a new account is welcomed once; accounts from before (no tour keys) are never new, even on a phone that never showed the tour; Google's first sign-in is new, a later one is not; tours taken on another phone are not repeated; signing out and back in; a second person signing up on the same phone; offline completion reaches the account at the next launch; the sign-in sync uses the event's own user; a guest only after the introduction; steps resume. On screen: the welcome by first name then all eight steps; the short welcome after the guest tour; existing accounts not toured; closed mid-tour it reopens at the same step; switching language mid-tour; turning the phone mid-tour; Skip, back gesture, Got it, and a page taking over (offered again); replay from Profile → Guides; the listing tour; and the card inside the safe area at every step in 8 set-ups (English/Arabic, portrait/landscape/tablet, text ×1 to ×1.6) | ✅ pass |
| `test/widget/google_maps_test.dart` | with a key (a fake native map): Explore draws Google's map, nearby pins merge and part on zoom, a tap selects a pin; the satellite switch changes the map type and is remembered; pin images keep their shapes and are drawn once; without a key the key-free map and no switch; pin grouping; Street View link, offered only at an exact pin | ✅ pass |
| `test/widget/fading_branches_test.dart` | switching tabs keeps every tab's state through reordering; the chosen tab is on top and takes taps; mid-switch the incoming tab fades in over the outgoing one | ✅ pass |
| `test/unit/api_client_test.dart` | the user's sign-in token goes only to the site's own host over HTTPS | ✅ pass |
| `test/widget/media_viewer_test.dart` | the photo viewer: title at the top, the tile sheet at the bottom (a real layout bug this would have caught), a tile jumps to its photo and the count follows | ✅ pass |
| `test/widget/nav_bar_test.dart` | at 360, 390 and 430 px, signed in and out, with each tab chosen: no tab name is cut short, every tab keeps its spoken name, and Log in keeps its label | ✅ pass |
| `test/widget/deep_links_test.dart` | links follow only our own pages; after signing in, never back to a sign-in page. Links given whole, as Android and iOS hand them over: a sign-in link on the first launch shows the introduction, then sign-in (it used to end on Home); a link to a page that needs an account returns there after sign-in (it used to end on Profile); a website listing link opens the listing before any introduction; a link to another site inside one is dropped | ✅ pass |
| `test/widget/listing_image_test.dart` | while a listing photo loads, a smaller copy already decoded stands in, or else the skeleton (it used to draw nothing: a blank space, most visible in dark mode) | ✅ pass |
| `test/widget/phone_auth_test.dart` | phone sign-in against a fake Supabase: a number of the wrong length is refused before anything is sent; a local number (07…) goes out as E.164; Arabic numerals; another country; the minute's wait before another code; a wrong code; Change number; no account with the number → link advice and a new account with it (name, language and tour state carried); the provider switched off; codes on WhatsApp say so; sign-up lands on Home, an existing number just signs in; adding a number from Profile (change-of-number codes, not sign-in); a number on another account; the phone options only when switched on; Profile's sign-in number row; an account with no email; both steps at large text in English and Arabic | ✅ pass |
| `test/widget/facebook_test.dart` | Continue with Facebook on sign-in and sign-up once switched on, never while off, never on iPhone; the provider switched off said plainly; Profile connects it (and remembers it asked), says when connecting is switched off, disconnects after confirming, and never removes an account's only way in; a connected account keeps its row when Facebook is later switched off; coming back with a Facebook account already used elsewhere, or cancelled, is said as such; every linking error in words | ✅ pass |
| `test/unit/phone_auth_unit_test.dart` | stored numbers (bare digits) split into a country and read as said; flags; every phone error in words; the WhatsApp change-of-number request (method, path, session, channel) and Supabase's refusals as its own errors | ✅ pass |
| `test/widget/onboarding_layout_test.dart` | the introduction at the largest text size (×1.6), in the app's real fonts, at 360 and 390 px, English and Arabic: nothing overflows (its header did, by 22 to 55 px), and the header stays at the top of the photo | ✅ pass |

`map_and_tours_test.dart` also checks that map cards put pinned listings first
and that a guest's tour ends on the Log in wording.

Total: 334 tests (plus the visual renders, run on demand). The production
pass (17 October) added the last three suites above; each was run against the
old code first and failed there. The link tests first passed a bare path and
missed the bug a device showed (the platform hands over the whole link);
they now give links whole. The opening's
tests caught the coded logo build silently reusing the launch logo's state (it
never animated or finished; fixed with keys).
Earlier, the onboarding tests
caught tour cards overflowing their screen (by 13 to 201 px, Next out of reach)
at large text and in landscape, and a tour that blocked later tours once it was
left open; both fixed. The parser tests now also hold the Phase 2 brief's English,
Jordanian Arabic and spoken-land examples, spoken amounts in both languages,
dialect words and mixed Arabic-English. A voice test caught a crash on the
first voice level (a fixed-length list), fixed before it reached a device.
The design-pass tests caught two real bugs (Undo using a disposed widget ref;
stepper taps reading a stale value), both fixed. Widget tests run at 390×844 and fail
on any layout overflow — two real overflows were found and fixed that way. Unit tests also caught a race in favourites sync and an error-wrapping bug in search; both fixed.

## On a device (Android emulator)

Run on an Android 16 (API 36) emulator, Pixel 7 profile, debug build, against
the production project, read-only: onboarding, the first-run tour, Home,
Explore map (clusters, pins, preview, filters, map ↔ list), property details
(gallery, map preview, contact), AI Search (live query), Saved, Profile and
its Guides, English and Arabic, light and dark. Nothing was signed up, listed,
saved to an account or sent. Findings and fixes are in DESIGN_AUDIT.md
("Found on a device").

Signed in with a test account the owner provided, still read-only: Profile,
the dashboard, Inquiries and Saved searches (debug build), then after the
redesign on a release build: signing in from the Log in button, signing out,
Profile, Saved, and the listing form up to its tour (closed without
publishing). Publishing a listing, sending an
inquiry and saving to the account were left to widget tests, so as not to
write to production.

### Opening (Phase 3), release build, Android emulator

The intro plays on a cold start and fades into the app; the hand-over from
Android's own splash shows no seam (the logo measured 363 and 365 px wide
either side of it). The emulator is slow to start graphics and video: the
first frame takes 1 to 2.5 s to reach the screen and its video decoder about
2 s more to show the intro's first frame, so there the logo holds for a few
seconds before the intro. Preparing the clip natively (IntroPlayer.kt) got it
on screen where video_player, in the same runs, never did within the window.
Not tried on a physical phone, where both take a fraction of that, nor on iOS.

### Onboarding (Phase 2), release build, production project

With three throwaway test accounts made for this (named "QA Test", listed for
deletion in the hand-over, credentials never in the repo):

- Fresh install → introduction → Home: the guest tour starts by itself; closed
  from the app switcher at step 4, it reopened at step 4; finished.
- Signed up in the app: back on Home, the short welcome ("Welcome, Nour", 3
  steps) started by itself; the account held `tour_pending: true` and the
  guest tour in `tours_done`. Closed at step 2, it reopened at step 2; when it
  ended the account held `tour_pending: false`. Relaunched: no tour.
- Profile → Guides → Viewing a property: the listing tour on the newest
  listing (photos, the heart, Send inquiry); recorded on the account.
- Signed out: no tour as a guest; signed back in: no tour.
- Arabic (Android's per-app language): the tour right to left; turned to
  landscape mid-step, the spotlight followed the control and the card moved
  beside it; switched to English mid-tour, the same step in English, left to
  right, without a restart. Sign-up in Arabic, then Skip: recorded.
- An account made through the public sign-up API (as the website makes them),
  signed in 20 minutes later on a fresh install: no welcome, and the account
  recorded as not new. This run found the sign-in sync reading the user too
  early (nothing was written); fixed and re-checked on the device.

Not tried on a device: Google sign-in (no Google account on the emulator; its
first-sign-in rule is unit-tested), iOS, a physical tablet.

To run it yourself:

```bash
flutter emulators --launch akarat_pixel   # or any Android device with USB debugging
flutter run                               # debug build, production public config
```

## Frame timing (device)

Measured on the emulator with SurfaceFlinger's present times (a scratch
script reading `dumpsys SurfaceFlinger --latency` for the app's surface):
Home scrolling and map panning hold 60 fps (median 16.7 ms); see
DESIGN_AUDIT.md ("Speed") for the table and caveats.


`integration_test/perf_test.dart` scrolls Home, swipes the Explore map cards
and scrolls the Explore list in profile mode, read-only, and records Flutter's
own frame build and raster times (Android's `gfxinfo` cannot see Flutter's
frames):

```bash
flutter drive --profile -d <device> \
  --driver test_driver/perf_driver.dart --target integration_test/perf_test.dart
# results: build/perf_summary.json
```

## Visual audit

```bash
flutter test test/visual --update-goldens --run-skipped
```

Renders 67 screens and states with the bundled fonts and real shadows into
`test/visual/goldens/audit/` (gitignored) for review: five device sizes,
English and Arabic, light and dark, loading/empty/error, 1.6× text. Tagged
`visual`, so plain `flutter test` skips it. These are review images, not
pixel-diff goldens. Findings and their status are in `DESIGN_AUDIT.md`.

## Parity fixtures

Five pieces of website logic are ported to Dart. Their fixtures are produced
by the website's own JavaScript:

```bash
node tool/gen_parity_fixtures.mjs   # writes test/fixtures/*.json
node tool/gen_reference.mjs         # regenerates lib/shared/reference/market_data.g.dart
```

Re-run both whenever `lib/aisearch.js`, `lib/geo.js`, `lib/providers.js`,
`lib/phone.js`, `lib/supabase.js` (payload) or `data/market.js` change; a
diverging port then fails `flutter test`.

## Integration tests (on a device)

**Not executed during development** — no device or emulator was available.
They are written and compile (`flutter analyze` covers them).

```bash
# Read-only: safe against any backend, including production.
flutter test integration_test/marketplace_test.dart -d <device> \
  --dart-define-from-file=env/staging.json

# Writes, with a dedicated test account. Refuses to run against the
# production project unless IT_ALLOW_PRODUCTION=true is also given.
flutter test integration_test/account_test.dart -d <device> \
  --dart-define-from-file=env/staging.json \
  --dart-define=IT_EMAIL=qa+mobile@example.com --dart-define=IT_PASSWORD=… \
  --dart-define=IT_ALLOW_WRITES=true
```

| Journey (brief §10) | Where |
|---|---|
| 1 sign in (sign-up needs an inbox; see below) | `account_test` |
| 2 search real properties, 3 filter, 4 open details | `marketplace_test` |
| 5 save a property | covered by widget + controller tests; on device via the heart |
| 6 create a listing, 8 edit it | `account_test` (draft, verified in the database, then deleted) |
| 7 upload images | manual — image_picker needs the system picker (checklist below) |
| 9 submit an inquiry | widget test; on device manually (needs another account's active listing) |
| 10 switch language | `marketplace_test` |
| 11 sign out and back in | `account_test` |
| 12 network interruption | manual (below) |
| 13 web ⇄ mobile sync | manual (below) |

### Staging

Run write tests against a staging Supabase project, never production data:
create a project, run migrations 0001–0014 in order, deploy a Vercel preview
with its keys, and point `env/staging.json` at both.

### Manual checks before a release

- [ ] Sign up in the app; confirm from the email **on the phone** (app reopens) and once **on a desktop** (website; then sign in on the phone)
- [ ] Sign in on the website with the account made in the app, and the reverse
- [ ] Google sign-in returns to the app (needs the redirect URL, INTEGRATION.md §4)
- [ ] Forgot password from the app → email link → app opens "Choose a new password"
- [ ] Publish with 3 photos + 1 video; open it on the website; photos and video play
- [ ] Reorder photos; the first is the cover on both clients
- [ ] Turn on airplane mode mid-upload → clear error, nothing saved; retry succeeds and no photo is duplicated in Storage
- [ ] Approximate pin: the website shows "approximate location" and the map link is near, not at, the building; Edit reopens on the exact pin
- [ ] Mark sold on the website → greyed and SOLD in the app after pull to refresh
- [ ] Send an inquiry from the app → it appears in the website dashboard's Inquiries tab
- [ ] Delete a listing in the app → gone on the website; its files gone from Storage
- [ ] Offline banner appears and disappears; lists show a retry, not a blank screen
- [ ] Arabic: every screen right to left, no clipped text at the largest system font size
- [ ] Dark mode on every screen
- [ ] TalkBack / VoiceOver: tabs, cards, heart, chips and buttons are announced
