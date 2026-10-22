# Akarat.ai — mobile

The native iOS and Android client for Akarat.ai, in Flutter. It is a second
client of the **same** Supabase project and Vercel API as the website: one set
of accounts, one set of listings, one set of inquiries.

| Doc | What is in it |
|---|---|
| [INTEGRATION.md](INTEGRATION.md) | How the app shares the backend; config; the website changes made; dashboard steps that need you; **feature-parity report**; known gaps |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Layers, search pipeline, state, navigation, security decisions |
| [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) | Tokens, type, components, RTL |
| [DESIGN_AUDIT.md](DESIGN_AUDIT.md) | The design and UX audit: every finding, its severity and how it was resolved |
| [PUBLISHING.md](PUBLISHING.md) | Where the code lives, signing, building, and getting the app to people (GitHub Releases, Google Play, App Store) |
| `SECURITY_AUDIT.md` | Security review. Kept on the owner's machine, out of this public repo, until the fixes it describes are live |
| [TESTING.md](TESTING.md) | What is tested, how parity with the website is enforced, device tests, manual checks |
| [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) | Everything between this branch and the stores |

## What it does

Home with real recent (and, when an admin flags them, featured) listings ·
Explore with server-side filters, sort and infinite scroll · AI Search in
English or Jordanian Arabic, using the website's own parser and ranker,
the Vercel search route and the market index, with match explanations and
honest portal links · listing details with gallery, video, privacy-respecting
location, call / WhatsApp / in-app inquiry · saved properties and saved
searches · email and Google sign-in, password reset · a 9-step listing flow
with photo/video upload, map pin and drafts · owner dashboard and inquiries ·
English and Arabic with full RTL · light and dark.

## Setup

Requirements: Flutter 3.47+ (Dart 3.13), and for builds Android SDK 36 /
JDK 17, or Xcode on macOS.

```bash
cd mobile
flutter pub get
flutter run                       # uses the production project's public defaults
```

To point at another environment (public values only — see INTEGRATION.md §2):

```bash
cp env/example.json env/staging.json      # git-ignored
flutter run --dart-define-from-file=env/staging.json
```

Never put `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET` or any provider/LLM key
in these files. Nothing in the app needs them.

## Build

```bash
# Android: one APK per processor type, and the bundle for Play (needs android/key.properties)
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols   --dart-define-from-file=env/production.json
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols   --dart-define-from-file=env/production.json

# iOS (macOS only)
flutter build ipa --release --obfuscate --split-debug-info=build/symbols   --dart-define-from-file=env/production.json
```

Keep each release's `build/symbols`: crash stack traces from an obfuscated
build can only be read with it (`flutter symbolize`).

Without `android/key.properties` a release build is signed with the debug key:
fine for testing, refused by Play. Maps are Google's when
`GOOGLE_MAPS_ANDROID_KEY` / `GOOGLE_MAPS_IOS_KEY` are set (with Map / Satellite
switching and Street View); without them, OpenStreetMap tiles from
`MAP_TILE_URL`. How to make the keys: PUBLISHING.md.

Verified on this branch (Windows, Flutter 3.47.7, JDK 17) on 17 October 2026:
`flutter analyze` clean, 347 tests passing, and the release commands above
succeed: APKs of 21.6 MB (armv7), 23.9 MB (arm64) and 25.4 MB (x86_64), and the
app bundle. The release package was checked (package `ai.akarat.app`, target
SDK 36, not debuggable, only the launcher activity exported, 16 KB-aligned
native libraries, Dart names obfuscated) and scanned: no service-role key,
cron secret or JWT; only the public publishable key. The x86_64 APK runs on an
Android 16 emulator. **iOS has not been built** (needs macOS), and no build
has run on a physical phone yet.

## Quality gates

```bash
dart format --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

## Regenerating shared artefacts

```bash
node tool/gen_reference.mjs          # data/market.js → lib/shared/reference/market_data.g.dart
node tool/gen_parity_fixtures.mjs    # website JS → test/fixtures/*.json
python tool/gen_native_assets.py     # brand mark → launcher icons
flutter test test/visual/launch_logo_test.dart --run-skipped && python tool/make_launch_images.py
                                     # the opening's logo → launch screen images
flutter gen-l10n                     # ARB → lib/app/localization/gen (also runs on build)
```

## Before it can ship

The app works against production today for browsing, search, sign-in,
listing, editing, inquiries and saved searches. These need someone with
dashboard access (details in INTEGRATION.md §4 and RELEASE_CHECKLIST.md):

1. Add `ai.akarat.app://login-callback` to Supabase Auth redirect URLs.
2. Get the website's domain serving the newest deployment (on 21 October it was stuck on 19 October's, so the app's two API routes were not live: RELEASE_CHECKLIST.md, first section).
3. Apply `supabase/migrations/0014_favorites.sql` for cross-device saved properties.
4. Done: `supabase/migrations/0013_protect_trust_fields.sql`. Still to do: turn on email confirmation.
5. Apply `supabase/migrations/0015_listing_reports.sql`, so *Report this listing* files reports (both stores require it), and read them daily.
6. Signing keys and store listings, with a review account.
7. Optional: phone sign-in (`SUPABASE.md` → Phone sign-in; then `PHONE_SIGNIN=auto`), and Sign in with Apple (the iOS guide; with it iPhones also offer Google and Facebook).
