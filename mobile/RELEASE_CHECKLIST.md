# Release checklist

Nothing below has been done yet unless marked. Items marked **(you)** need
access only you have: dashboards, store accounts, signing keys. How to sign,
build and distribute, and where the code should live: `PUBLISHING.md`.
Step-by-step guides for the owner, as PDFs kept outside the repository:
*Akarat-Android-Deployment-Guide* and *Akarat-iOS-Deployment-Guide*.

## Both stores

- [ ] **A way to report listings.** Google Play's user-generated-content policy and App Store guideline 1.2 expect apps where people post content others see to let users report objectionable content and abusive users. The app (and the website) have no "Report this listing" yet; add one before the first review (a prefilled email to the support address needs no database change; a reports table needs a migration)

## Backend (before the first store build)

- [ ] **(you)** Supabase → Auth → URL Configuration: add `ai.akarat.app://login-callback` to Redirect URLs
- [ ] **(you)** Review and run `supabase/migrations/0014_favorites.sql` (optional but recommended)
- [x] Deploy the website changes: `app/api/ai/search/route.ts`, `app/api/account/route.ts` (type-checked, then pushed to `main` with the app on 21 October 2026; Vercel deploys from it)
- [ ] **(you)** Confirm `SUPABASE_SERVICE_ROLE_KEY` is set for the Vercel production environment (account deletion and the shared rate limiter need it)
- [ ] Smoke-test `POST /api/ai/search` with and without a bearer token, and `DELETE /api/account` with a throwaway account
- [ ] **(you)** Custom SMTP in Supabase (the default mailer is rate-limited and lands in spam — SUPABASE.md)
- [ ] **(you)** Leaked-password protection on, password minimum 8, email confirmation on
- [x] **(you)** Apply `supabase/migrations/0013_protect_trust_fields.sql` (trust fields and maintenance functions; see the security audit kept outside the repo). Applied before the push; on 21 October 2026 the maintenance function refused the public key
- [ ] **(you)** Delete the development test account (or change its password), and the three QA accounts made for the onboarding tests (their addresses are in `SECURITY_AUDIT.md`, which stays out of the repo)
- [ ] **(you)** Privacy policy: add voice search, maps, inquiries and in-app deletion (draft in PUBLISHING.md)
- [ ] **(you)** Phone sign-in (optional, billed per message): Twilio Messaging Service with an SMS number (or an approved WhatsApp sender), **Geo Permissions** for only the countries you serve, a **spend limit**; then Supabase → Authentication → Providers → **Phone** on with the Twilio Account SID, Auth Token and Messaging Service SID, code length 6, expiry 300 s, and a low SMS limit under Rate Limits. The app offers phone sign-in by itself once it is on. Steps: `SUPABASE.md` → Phone sign-in
- [ ] **(you)** Facebook sign-in (optional): turn on *Confirm email* first (SECURITY_AUDIT.md S23). Then a Meta for Developers app with Facebook Login: *Valid OAuth Redirect URIs* = `https://<project-ref>.supabase.co/auth/v1/callback`, privacy policy URL and data-deletion URL (the website's `/privacy` and `/data-deletion`), icon, category, switched to **Live**. Supabase → Authentication → Providers → **Facebook** on with the App ID and App Secret, and **manual linking** on for Profile's "connect Facebook". The app shows Facebook by itself once it is on (Android only)
- [ ] **(you)** Optional: Supabase **test phone numbers** (a fixed code, no SMS sent) for your own testing and for Google Play's reviewers

## Configuration

- [x] `env/production.json` from `env/example.json`: the production Supabase URL and publishable key and the site URL (public values only; git-ignored). Maps keys still empty
- [x] `FACEBOOK_SIGNIN` = `auto` in `env/production.json`
- [ ] `PHONE_SIGNIN` in `env/production.json`: `off` until codes can be delivered. Supabase's Phone provider is on, so `auto` shows phone sign-in now, but the website keeps it off until Twilio approves the WhatsApp template, and SMS to Jordan needs a registered Sender ID (SUPABASE.md → Phone sign-in). Then `auto`, with `OTP_CHANNEL` = `whatsapp` (as the website) or `sms`
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
- [ ] **(you)** Account deletion URL in Play Console (Google requires a web page as well as the in-app path)
- [ ] **(you)** App Links: the manifest claims `https://akarat.ai` with auto-verify. If you own the domain, publish `/.well-known/assetlinks.json` with the Play signing SHA-256; if not, remove that intent filter

## iOS (not yet built — needs a Mac)

- [x] Bundle id `ai.akarat.app`, display name, URL scheme, photo/camera/microphone purpose strings, launch screen, icons (no alpha)
- [ ] **(you)** Apple Developer Program ($99/year); App ID `ai.akarat.app`; the app in App Store Connect
- [ ] **Decide iPhone only or iPad too** before the first upload: the project targets both (`TARGETED_DEVICE_FAMILY = 1,2`). With iPad, review tests on iPad and iPad screenshots are needed, and later versions cannot drop it; iPhone-only for 1.0 is the safer choice until the tablet pass is done
- [ ] Build on a Mac (`flutter build ipa --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/production.json`) or on Codemagic (project path `mobile`, `env/production.json` supplied from a secret variable); automatic signing with your team
- [x] The app's code is on GitHub (`main`, 21 October 2026), for a Mac or a cloud build to check out
- [ ] Associated Domains + `apple-app-site-association` (optional)
- [ ] **(you)** App Store Connect: privacy nutrition labels, account deletion (in-app path exists), Sign in with Apple: guideline 4.8 requires it wherever Google sign-in is offered, so the app hides Google on iOS today. To offer Google on iOS, enable the Apple provider in Supabase, add the capability, and add an Apple button
- [ ] TestFlight round on a real device
- [ ] If App Store Connect reports a missing privacy declaration (ITMS-91053) on the first upload, add a `PrivacyInfo.xcprivacy` to Runner in Xcode. The plugins carry their own; the app's own code uses none of the APIs Apple lists

## Quality gates

- [x] `flutter analyze` — no issues; `dart format` clean
- [x] `flutter test` — 302 passing (plus the visual renders, run on demand)
- [x] Known advisories (OSV database, 17 October 2026): none for any of the 174 Dart packages in `pubspec.lock`. Native Android and iOS libraries not scanned
- [ ] Integration tests on a physical Android and iPhone (TESTING.md)
- [ ] Manual release checks (TESTING.md)
- [ ] Profile on a mid-range Android (e.g. 4 GB RAM): Home and Explore scroll at 60 fps in profile mode
