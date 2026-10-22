# Release checklist

Nothing below has been done yet unless marked. Items marked **(you)** need
access only you have: dashboards, store accounts, signing keys. How to sign,
build and distribute, and where the code should live: `PUBLISHING.md`.
Step-by-step guides for the owner, as PDFs kept outside the repository:
*Akarat-Android-Deployment-Guide* and *Akarat-iOS-Deployment-Guide*.

## First: the website is not serving what is on `main`

- [ ] **(you)** On 21 October 2026, `www.akarat.ai` (and `akarat-ai-swart.vercel.app`) served a build from **19 October**: no `/privacy`, `/terms` or `/data-deletion` pages, no Facebook button, and none of the app's API routes. Vercel had built every push since then successfully (GitHub shows each production deployment as completed), but none of them reached the domain. That is what an *Instant Rollback* or a manual *Promote* of an older deployment leaves behind: Vercel stops assigning new production deployments to the domains until it is undone. In Vercel → the project GitHub deploys to (deployment URLs `akarat-…-shayans-projects-….vercel.app`) → **Deployments**: open the newest production deployment and **Promote to Production** (or **Undo Rollback** if a banner offers it), and check **Settings → Domains** lists `www.akarat.ai` on that project. Then `https://www.akarat.ai/en/privacy` loads and `DELETE https://www.akarat.ai/api/account` (no token) answers 401 instead of 404. Until then the app's account deletion falls back to email, which App Review does not accept

## Both stores

- [x] **Report and block.** Every listing (not your own) has *More → Report this listing / Hide this advertiser*, and *Report this listing* at the foot of the page. Reports go into `listing_reports` (migration 0015) with a reason and the reporter's words; hiding an advertiser removes all their listings everywhere in the app, on that device (Profile → *Hidden advertisers* brings them back). The terms (in the app and on the website) forbid unlawful, discriminatory, offensive or abusive content. That is what App Store guideline 1.2 and Google Play's user-generated content policy ask for
- [ ] **(you)** Run `supabase/migrations/0015_listing_reports.sql` before the first review, then the website's `0016_revoke_stray_anon_reads.sql`, which takes back read access 0015 left to signed-out callers through the schema's default privileges. Until it runs, a report opens an email to `hello@akarat.ai` instead, which a reviewer's device may not be able to send
- [ ] **(you)** Someone reads new reports every day (Supabase → Table Editor → `listing_reports`, `status` = `open`) and acts on them within 24 hours, the standard Apple sets for apps with user content: hide or delete the listing, and set `status` to `removed`, `reviewed` or `dismissed`
- [ ] **(you)** Make sure `hello@akarat.ai` and `privacy@akarat.ai` receive mail: the app names them for help, reports and deletion requests, and both stores want working contact details
- [ ] **(you)** A review account: an email-and-password account made for App Review and Google Play's review (not your own, not the development test account), confirmed, with one sample listing; enter it under App Store Connect → *App Review Information* and Play Console → *App access*. Reviewers should not need phone sign-in

## Backend (before the first store build)

- [ ] **(you)** Supabase → Auth → URL Configuration: add `ai.akarat.app://login-callback` to Redirect URLs
- [ ] **(you)** Review and run `supabase/migrations/0014_favorites.sql` (optional but recommended)
- [x] Deploy the website changes: `app/api/ai/search/route.ts`, `app/api/account/route.ts` (type-checked, then pushed to `main` with the app on 21 October 2026; Vercel deploys from it — but see the first section)
- [ ] **(you)** Confirm `SUPABASE_SERVICE_ROLE_KEY` is set for the Vercel production environment (account deletion and the shared rate limiter need it)
- [ ] Smoke-test `POST /api/ai/search` with and without a bearer token, and `DELETE /api/account` with a throwaway account
- [ ] **(you)** Custom SMTP in Supabase (the default mailer is rate-limited and lands in spam — SUPABASE.md)
- [ ] **(you)** Leaked-password protection on, password minimum 8, email confirmation on. On 21 October Google and Facebook were both switched on with *Confirm email* still off: see SECURITY_AUDIT.md S23, and turn it on now
- [x] **(you)** Apply `supabase/migrations/0013_protect_trust_fields.sql` (trust fields and maintenance functions; see the security audit kept outside the repo). Applied before the push; on 21 October 2026 the maintenance function refused the public key
- [ ] **(you)** Delete the development test account (or change its password), and the three QA accounts made for the onboarding tests (their addresses are in `SECURITY_AUDIT.md`, which stays out of the repo)
- [ ] **(you)** Privacy policy: add voice search, maps, phone codes, Sign in with Apple and in-app deletion (draft in PUBLISHING.md) to the website's policy, which both stores link to
- [ ] **(you)** Phone sign-in (optional, billed per message): Twilio Messaging Service with an SMS number (or an approved WhatsApp sender), **Geo Permissions** for only the countries you serve, a **spend limit**; then Supabase → Authentication → Providers → **Phone** on with the Twilio Account SID, Auth Token and Messaging Service SID, code length 6, expiry 300 s, and a low SMS limit under Rate Limits. Steps: `SUPABASE.md` → Phone sign-in
- [x] **(you)** Facebook sign-in: Supabase showed the Facebook provider **on** on 21 October 2026. Still to check: the Meta app is **Live**, its privacy policy and data-deletion URLs are the website's `/privacy` and `/data-deletion` (live only once the first section is fixed), and **manual linking** is on for Profile's "connect Facebook". On iPhone the app offers Facebook only beside Sign in with Apple
- [ ] **(you)** Sign in with Apple (optional; with it, iPhones also offer Google and Facebook): in the Apple Developer account, the App ID `ai.akarat.app` with *Sign in with Apple*; a **Services ID** (e.g. `ai.akarat.web`) with the domain `<project-ref>.supabase.co` and the return URL `https://<project-ref>.supabase.co/auth/v1/callback`; a **Key** with Sign in with Apple (download the `.p8` once; note its Key ID and your Team ID). Supabase → Authentication → Providers → **Apple** on: *Client IDs* `ai.akarat.app,<your Services ID>`, and the secret key generated from the `.p8` (it expires after six months — set a reminder to make a new one). Register the sending addresses for Apple's private relay (Apple Developer → *Sign in with Apple for Email Communication*) so mail reaches "Hide My Email" users. Steps: the iOS guide, Step 3c
- [ ] **(you)** For Sign in with Apple accounts, revoking on deletion (Apple requires it): in Vercel → Settings → Environment Variables (Production), `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` (the `.p8` file's text). Without them accounts are still deleted, but Akarat.ai stays listed under the person's Apple ID until they remove it
- [ ] **(you)** Optional: Supabase **test phone numbers** (a fixed code, no SMS sent) for your own testing and for Google Play's reviewers

## Configuration

- [x] `env/production.json` from `env/example.json`: the production Supabase URL and publishable key, `SITE_URL` = `https://www.akarat.ai` (public values only; git-ignored). Maps keys still empty
- [x] `APPLE_SIGNIN` = `auto` in `env/production.json` (Supabase's Apple provider was on by 22 October, so the button shows); `FACEBOOK_SIGNIN` = `off`, as on the website, until the Meta app is **Live**: in Development mode Facebook refuses everyone without a role on the app, which looks like a broken button
- [x] `PHONE_SIGNIN` = `off` in `env/production.json` (21 October 2026), as on the website, until codes can be delivered: the website keeps it off until Twilio approves the WhatsApp template, and SMS to Jordan needs a registered Sender ID (SUPABASE.md → Phone sign-in). Then `auto`, with `OTP_CHANNEL` = `whatsapp` (as the website) or `sms`
- [x] `APP_VERSION` and `version:` in `pubspec.yaml` agree: `1.0.0+1` for the first release. Every later release: bump both, and the build number after `+`
- [ ] **(you)** Google Maps: two keys locked to the app (Android: package + SHA-1s; iOS: bundle ID), Maps SDK only, in `env/production.json` as `GOOGLE_MAPS_ANDROID_KEY` / `GOOGLE_MAPS_IOS_KEY` (PUBLISHING.md). Without them the app uses OpenStreetMap tiles (`MAP_TILE_URL`), which need a commercial provider for real traffic
- [ ] **(you)** Website Maps key (public at `/config.js`): restricted to your domains, Maps JavaScript + Places only, with a quota and a budget alert

## Android

- [x] Application id `ai.akarat.app`, label, adaptive icon, Android 12+ splash
- [x] INTERNET permission in the main manifest (Flutter only adds it to debug)
- [x] Backups disabled; R8 + resource shrinking on
- [x] Release build verified on 17 October 2026 with the commands below (debug-signed until the upload key exists): obfuscated, R8 and resource shrinking on; split APKs 21.6 MB (armv7), 23.9 MB (arm64), 25.4 MB (x86_64); app bundle builds
- [x] Release package checked: not debuggable; no cleartext; backup and device transfer off; permissions internet, network state, microphone, wake lock; exported only the launcher activity and a system receiver behind `DUMP`; no secrets (only the publishable key); Dart names obfuscated; native libraries 16 KB page-aligned (Play's requirement for Android 15+ targets)
- [x] Release APK run on the emulator (Android 16): intro video, matte-black dark mode, Explore, a listing, a sign-in link on a fresh install
- [ ] Install and smoke-test on a physical device (not yet done)
- [ ] **(you)** Create an upload keystore; `android/key.properties`:
  ```
  storeFile=/absolute/path/upload-keystore.jks
  storePassword=…
  keyAlias=upload
  keyPassword=…
  ```
- [ ] With the upload key in place:
  `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/production.json`.
  Keep that release's `build/symbols` (crash stack traces need it): copy it somewhere safe, named by version
- [ ] **(you)** Play Console: app, Data safety form (account, listing content, photos; no location, no ads), content rating, privacy policy URL
- [ ] **(you)** Account deletion URL in Play Console (Google requires a web page as well as the in-app path): the website's `/data-deletion`
- [ ] **(you)** App Links: the manifest claims `https://akarat.ai` with auto-verify. The domain is yours (it serves the website), so publish `/.well-known/assetlinks.json` with the Play signing SHA-256 once the app is in Play Console

## iOS (not yet built — needs a Mac)

- [x] Bundle id `ai.akarat.app`, display name, URL scheme, launch screen, icons (no alpha)
- [x] Permission prompts (camera, photos, microphone, speech), each naming every use (listing photos and videos, the profile picture, voice search), in English and Arabic (`en.lproj`, `ar.lproj`), which also lists Arabic on the App Store page; a location string for the Google Maps SDK, which Apple's upload check can ask for although the app never requests location
- [x] **iPhone only for 1.0** (`TARGETED_DEVICE_FAMILY = 1`), portrait only: the tablet pass is not done, and an iPad build is reviewed on an iPad. iPhone apps still run on iPads. To add iPad later: finish the tablet layouts, set `1,2`, test on iPad, and add iPad screenshots
- [x] Privacy manifest `Runner/PrivacyInfo.xcprivacy`: no tracking; account details, photos, listings and inquiries, search history, all for the app's functioning; UserDefaults and file-timestamp reasons. The plugins carry their own
- [x] Sign in with Apple capability (`Runner/Runner.entitlements`). Signing it needs the paid developer program: a free Personal Team cannot. To try the app on your own iPhone before enrolling, remove the capability in Xcode → Signing & Capabilities for that run
- [x] `ios/Podfile` with `platform :ios, '15.0'`: Google Maps comes through CocoaPods (the other plugins through Swift Package Manager), and 15.0 resolves Google Maps SDK 9
- [x] Sign in with Apple in the app: Apple's sheet with a SHA-256 nonce, Apple's button design, first on iPhones; sign-up, sign-in and Profile → Apple to connect or disconnect; the name Apple shares only the first time is kept; deleting an Apple account asks Apple to confirm and revokes the token on the server (once `APPLE_*` are set in Vercel)
- [ ] **(you)** Apple Developer Program ($99/year); App ID `ai.akarat.app` with Sign in with Apple; the app in App Store Connect
- [ ] Build on a Mac (`flutter build ipa --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/production.json`) or on Codemagic (project path `mobile`, `env/production.json` supplied from a secret variable); automatic signing with your team
- [x] The app's code is on GitHub (`main`, 21 October 2026), for a Mac or a cloud build to check out
- [ ] Associated Domains + `apple-app-site-association` (optional)
- [ ] **(you)** App Store Connect: App Privacy answers (PUBLISHING.md), age rating, the review account and a note for the reviewer (where Report and Delete account are), support URL and privacy policy URL (`https://www.akarat.ai/privacy`)
- [ ] TestFlight round on a real device

## Quality gates

- [x] `flutter analyze` — no issues; `dart format` clean
- [x] `flutter test` — 347 passing (plus the visual renders, run on demand)
- [x] Known advisories (OSV database, 17 October 2026): none for any of the 174 Dart packages in `pubspec.lock`. Native Android and iOS libraries not scanned
- [ ] Integration tests on a physical Android and iPhone (TESTING.md)
- [ ] Manual release checks (TESTING.md)
- [ ] Profile on a mid-range Android (e.g. 4 GB RAM): Home and Explore scroll at 60 fps in profile mode
