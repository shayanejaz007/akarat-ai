# Architecture

Flutter 3.47 / Dart 3.13, Material 3 via the `material_ui` package, Riverpod 3
for state, go_router 18 for navigation, supabase_flutter 2.18 for data and
auth, Dio for the Vercel API.

## Layout

```
lib/
  main.dart                 init (prefs, date symbols, Supabase with keystore session + PKCE), runApp
  app/
    app.dart                MaterialApp.router; locale + theme; password-recovery routing; resume refresh
    router/                 routes, GoRouter (5-tab StatefulShellRoute, guards, deep links), nav bar
    theme/                  tokens.dart (colours, spacing, radii, motion, shadows), app_theme.dart
    localization/           arb/app_en.arb, arb/app_ar.arb → gen/ (flutter gen-l10n), l10n.dart helpers
  core/
    config/env.dart         build-time PUBLIC config (--dart-define)
    errors/app_failure.dart every error reduced to a FailureKind; screens map kinds to sentences
    networking/             Dio client with bearer interceptor; connectivity stream
    security/               Supabase session + PKCE verifier in flutter_secure_storage
    utils/                  payload codec, geo (blur, snapping), phone (E.164), formatters, input formatters
    widgets/                skeletons, images, empty/error states, buttons, brand, maps
  shared/
    models/                 Listing (+payload, media), filters, search constraints, account models
    reference/              market_data.dart + market_data.g.dart (generated from data/market.js)
    repositories/           listings, media, favorites, saved searches, inquiries, profile, account
    services/               supabase providers, preferences, refresh tick
    widgets/                property card/row, favourite button, badges, choice sheets
  features/
    onboarding/ home/ explore/ ai_search/{domain,data,presentation}/ property_details/
    favorites/ saved_searches/ inquiries/ listings/{domain,application,presentation}/
    dashboard/ profile/ settings/ authentication/{presentation}
```

Presentation never touches Supabase or Dio directly: screens watch providers,
providers call repositories, repositories own every query and map every
exception through `AppFailure.from`. Swapping any repository for a fake is a
one-line `overrideWithValue`, which is how the tests run.

## Search pipeline

```
text ─► QueryParser (on device, port of lib/aisearch.js) ─► SearchConstraints
           │                                                     │
           │ live, debounced preview chips                        ├─► POST /api/ai/search  (Dio, CancelToken, bearer)
           │                                                     │     internal rows (RLS) + partner feeds + coverage
           │                                                     │     ↳ network / 5xx → direct RLS query, flagged "servedDirect"
           │                                                     │     ↳ 429 → shown as rate-limited, never bypassed
           │                                                     └─► external_properties_grouped (read-only index)
           ▼
     website's searchInternal filter ─► Ranker.score (port of scoreListing) ─► stable sort
     Ranker.explain (port of explain) per card;  PortalLinks.build (port of providers.js) below
```

The parser, ranker, explanations, portal links, blur, snapping and phone
rules are ports, not reinventions. `tool/gen_parity_fixtures.mjs` runs the
website's JavaScript over fixed inputs and the Dart tests demand identical
output. Changing search behaviour means changing `lib/aisearch.js` first,
regenerating fixtures, then the port.

Only the newest search may finish: each run cancels the previous request at
the socket (`CancelToken`) and ignores it if it lands anyway.

## Listings: the payload

`properties` keeps indexed facts as columns and everything bulky in
`payload_gz` = `gz:` + base64(gzip(JSON)). `PayloadCodec` reads `gz:`, `raw:`
and bare JSON, and writes `gz:` exactly as the website's `packPayload` does
(`payload_bytes`, `raw_bytes`; never a `ratio` column). Tested against a
payload packed by the website's own code.

Saving a listing (`ListingWizardController.save`) follows the website's
`submitListing` order: upload new media first (resized natively to 1600 px /
q85 — the web form's numbers), publish the exact pin or the deterministic
blurred point, write the row (owner from the session, never the client),
write the exact pin to the owner-only `property_locations`, then delete files
removed during the edit. A file that uploaded before a failure is remembered,
so a retry never sends it twice (tested).

## State

| Provider | Kind | Notes |
|---|---|---|
| `currentUserProvider` | derived from `onAuthStateChange` | everything account-shaped watches it |
| `exploreProvider` | AsyncNotifier | page 0 on filter change; `loadMore` appends, dedupes, discards stale pages |
| `aiSearchProvider` | Notifier | turns, constraints, real stage progress, outcome; cancellation |
| `favoritesProvider` | Notifier | optimistic toggle with rollback; device ⇄ account merge; coalesced sync |
| `listingWizardProvider(editId)` | autoDispose family | draft persisted to the device as typed (new listings) |
| `refreshTickProvider` | Notifier<int> | bumped on resume (>3 min) and after writes; lists watch it |

Riverpod's automatic retry is disabled app-wide: a failed query shows an
error with a retry button rather than being re-sent invisibly.

## Navigation

`StatefulShellRoute.indexedStack` keeps each tab's stack and scroll position.
Details, auth, the listing wizard, dashboard and inquiries are pushed on the
root navigator over the bar. Guards: `/listing`, `/dashboard`, `/inquiries`
need a session; browsing, searching and saving never do. First launch shows
onboarding unless a deep link brought the reader to a listing or back from an
auth email. Deep links: `ai.akarat.app://open/property/<id>`, the website's
`/{en,ar}/property/<id>`, and `ai.akarat.app://login-callback?code=…`.

## Security decisions

- Session and PKCE verifier in the keystore (`SecureSessionStorage`), not
  SharedPreferences. Android backup and device transfer are disabled.
- PKCE auth flow: an intercepted redirect is useless without this device's
  verifier.
- Only public config in Dart. Google Maps keys are app-locked client keys
  (package + certificate / bundle ID, Maps SDK only, free map loads);
  without them maps use raster tiles from `MAP_TILE_URL`. The service-role
  key exists only on Vercel.
- Every write the app makes is also bounded by RLS; the repositories add
  `owner_id` / `user_id` filters as a second guard, and never accept an owner
  from a caller.
- Error text shown to readers comes from `FailureKind`, never from raw
  PostgREST/Storage/HTTP messages.
- External links open only `https` URLs, in the external browser.
- `debugPrint` is silenced in release builds.

## Decisions worth knowing

- **No freezed/json_serializable.** The models are few and their parsing is
  bespoke (gzipped payload, bilingual fallbacks, tolerant numerics), which a
  generator would not express; hand-written `fromRow`/`toJson` keep the build
  free of a codegen step. Revisit if the model count grows.
- **material_ui instead of `package:flutter/material.dart`.** Flutter 3.44+
  moved Material into its own package and go_router 18 builds its pages from
  it; mixing the two would give go_router a different `MaterialApp` type.
- **No Realtime.** Pull-to-refresh, resume refresh and write-triggered
  invalidation keep lists current without holding sockets open; Realtime
  publication is not configured on these tables.
- **Western digits in Arabic** for prices and dates, matching the website and
  Jordanian listing conventions; Arabic-Indic input is accepted everywhere.
