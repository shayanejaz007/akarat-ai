# Publishing the app

How to get Akarat.ai onto people's phones, where the code should live, and
what has to happen first. Steps marked **(you)** need accounts or keys only
you have. The step-by-step tick list is `RELEASE_CHECKLIST.md`.

## 1. Where the code lives: same repo, `mobile/` folder, on `main`

Keep the app where it is now, in `mobile/` inside `shayanejaz007/akarat-ai`,
and merge it into `main` with a pull request from `feat/flutter-mobile`. Don't
keep it on a separate permanent branch.

- **One product, one history.** The app depends on the website's API routes
  (`app/api/ai/search`, `app/api/account`) and on the database migrations in
  `supabase/`. A change often touches all three (migration 0013 is an
  example). On one branch they are reviewed and shipped together; on two
  permanent branches they drift apart.
- **Branches are for work in progress.** Use short-lived branches
  (`feat/…`, `fix/…`) for changes to either the site or the app, and merge
  them into `main`.
- **Shared tooling.** `tool/gen_parity_fixtures.mjs` reads the website's
  search code to keep the app's answers identical. It needs both in one
  checkout.

**(you)** In Vercel → Project → Settings → Git → *Ignored Build Step*, add
the command below so that commits touching only `mobile/` don't redeploy the
website:

```bash
git diff --quiet HEAD^ HEAD -- . ':(exclude)mobile'
```

### Before the first push: the repo is public

Everything pushed is visible to anyone. Already handled:

- Signing keys, `key.properties`, certificates and built APK/AAB/IPA files are
  git-ignored anywhere under `mobile/`.
- `SECURITY_AUDIT.md` is git-ignored: it describes weaknesses that are open
  until migration 0013 is applied. Commit it after that, if you like.
- No secrets in the 279 files of the first push (checked again on 21 October
  2026, just before it) or in the history before it (checked on 15 October).

**Apply migration 0013 before the first push.** The migration goes up with
everything else, and anyone reading it can see the gap it closes (described in
the security audit kept outside the repo). Applied first, there is nothing left
to find.

Run `git status` before every push and look for anything unexpected.

## 2. Signing (Android): do this once, keep it forever

Every update must be signed with the same key. Lose the key and you can't
update the app (Google can reset it for Play-signed apps; for direct
downloads there is no recovery).

**(you)**, from `mobile/android/`:

```bash
keytool -genkey -v -keystore ~/akarat-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

Then create `mobile/android/key.properties` (git-ignored):

```
storeFile=C:/Users/<you>/akarat-upload.jks
storePassword=<the password you chose>
keyAlias=upload
keyPassword=<the password you chose>
```

Back up the `.jks` file and both passwords somewhere safe outside the repo
(a password manager). Without `key.properties` the build falls back to the
debug key, which is fine for testing but must never be distributed.

## 3. Build

From `mobile/`, with `env/production.json` created from `env/example.json`:

```bash
# For Google Play (one bundle; Play delivers the right size per phone)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
  --dart-define-from-file=env/production.json

# For direct download (one APK per processor type, ~20 MB each instead of 65)
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols \
  --dart-define-from-file=env/production.json
```

Keep `build/symbols` for each release (it turns crash reports back into
readable stack traces). The build warns that the generated library "contains
unobfuscated DWARF debugging information": that is the intermediate file; the
library packed into the APK and bundle is stripped (checked).

Upload the `.aab` only to Google Play, never anywhere public (such as a GitHub
release): it carries the debug symbols Play uses to read native crash reports,
with the code's original names. Play strips them before anything reaches a
phone; the APKs carry none.

`env/production.json` already exists on the development machine with the
production Supabase URL, publishable key and site URL. Add the Maps keys to it
when you have them (section 5). Bump `version:` in `pubspec.yaml` every release:
`1.0.0+1` → `1.0.1+2` (the number after `+` must always go up).

## 4. Ways to let people download it

| Route | Cost | Good for | Notes |
|---|---|---|---|
| **GitHub Releases** (APK) | free | testers, early users, a "Download for Android" link on the site | Works because the repo is public. People must allow "Install unknown apps"; Play Protect may warn; no automatic updates |
| **Google Play** | $25 once | everyone on Android | Automatic updates, trusted install. New personal developer accounts must run a closed test (12 testers, 14 days) before going public; organisation accounts are exempt |
| **App Store** (iPhone) | $99 / year | everyone on iPhone | Needs a Mac with Xcode, or a cloud Mac build (Codemagic, GitHub Actions macOS runners). TestFlight for testers, then App Review. iPhones cannot install from a download link |

**Suggested order:** a GitHub Release for testers now, Google Play's closed
test in parallel (it takes two weeks), and the App Store once you have Apple
access.

### GitHub Release, step by step

1. Build the split APKs (section 3).
2. **(you)** GitHub → the repo → *Releases* → *Draft a new release*. Tag
   `v1.0.0`, title "Akarat.ai 1.0.0", a few lines on what's new.
3. Attach `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (nearly
   every phone from the last eight years) renamed to `akarat-android.apk`,
   plus the `armeabi-v7a` APK for very old phones.
4. Link from the website. This URL always points at the newest release:
   `https://github.com/shayanejaz007/akarat-ai/releases/latest/download/akarat-android.apk`

Or from the command line, with the GitHub CLI:

```bash
gh release create v1.0.0 akarat-android.apk --title "Akarat.ai 1.0.0" --notes "First release"
```

Google is rolling out *developer verification* for apps installed outside
Play: on certified Android phones, apps must come from a registered
developer, starting with a few countries and widening over time. Check
whether it applies in Jordan yet, and register in the Android Developer
Console so the downloaded APK keeps installing.

### Optional: automatic builds

A GitHub Actions workflow can build and attach the APK whenever you push a
tag such as `v1.0.1`. It needs the keystore stored as a repository secret
(base64), never committed. Ask and it can be set up.

## 5. Google Maps keys for the app

The app uses Google's own map SDKs when it has a key, with Map / Satellite
switching and a Street View button on listings with an exact pin. Without a
key it falls back to its OpenStreetMap-style maps, so nothing breaks.

The website's key (`NEXT_PUBLIC_GOOGLE_MAPS_KEY` on Vercel) **can't be reused**:
it is (and must stay) locked to your website, and it is enabled only for the
Maps JavaScript and Places APIs. Make two more keys in the **same Google Cloud
project**. They take a couple of minutes:

1. **(you)** Google Cloud Console → *APIs & Services* → *Library*: enable
   **Maps SDK for Android** and **Maps SDK for iOS**.
2. **(you)** *Credentials* → *Create credentials* → *API key*, name it
   "Akarat Android":
   - *Application restrictions* → **Android apps** → add package
     `ai.akarat.app` with the SHA-1 of each key that signs the app:
     - your upload key: `keytool -list -v -keystore ~/akarat-upload.jks -alias upload`
     - once on Google Play: Play Console → *Test and release* → *App integrity*
       → *App signing key certificate* SHA-1
     - for test builds made on the development machine (debug key):
       `26:2E:7A:5F:81:A1:A9:80:27:68:C6:E4:0E:B3:0D:99:00:EC:CB:4D`
   - *API restrictions* → **Restrict key** → only **Maps SDK for Android**.
3. **(you)** Another key for iPhone: *Credentials* → *Create credentials* →
   *API key*, then *Edit API key*: name it "Akarat iOS"; *Application
   restrictions* → **iOS apps** → *Add an item* → bundle ID `ai.akarat.app`;
   *API restrictions* → **Restrict key** → only **Maps SDK for iOS**; *Save*.
   A restriction can take a few minutes to apply.
4. Put both in `mobile/env/production.json` (git-ignored, never committed):
   ```json
   "GOOGLE_MAPS_ANDROID_KEY": "AIza…",
   "GOOGLE_MAPS_IOS_KEY": "AIza…"
   ```
   and build with `--dart-define-from-file=env/production.json` as usual.
   That one file feeds both Dart and the Android manifest; iOS receives its
   key at launch.

These keys end up inside the app, like the website's key ends up in every
browser, and that is fine: each works only from your app (package + signing
certificate, or bundle ID), only for the Maps SDK, and Google charges nothing
for map loads in the mobile SDKs. Street View opens Google's own Maps app,
which costs nothing either.

While you are in the console, check the **website's** key, which anyone can
read at `/config.js`: *Application restrictions* should be **Websites** with
only your domains, *API restrictions* only Maps JavaScript + Places, plus a
daily quota and a budget alert on the billing account. If it is unrestricted,
restrict it now: that one is billed per use.

## 6. Before anything is public

These matter more than the store listing:

- [ ] **(you)** Get `www.akarat.ai` serving the newest deployment again: on 21 October 2026 it was still on a build from 19 October, although every push since had deployed (RELEASE_CHECKLIST.md, first section). Until then the app's account deletion and the website's legal pages are not live
- [ ] **(you)** Run `supabase/migrations/0015_listing_reports.sql`, and have someone read new reports every day (Table Editor → `listing_reports`) and act within 24 hours
- [ ] **(you)** A review account (email and password, confirmed, one sample listing) for App Review and Google Play
- [x] **(you)** Apply `supabase/migrations/0013_protect_trust_fields.sql`, before the first push (done; checked on 21 October 2026)
- [x] Deploy the website's API changes the app relies on (`app/api/ai/search`, `app/api/account`): pushed to `main` with the app on 21 October 2026
- [ ] **(you)** Supabase: turn on email confirmation, add `ai.akarat.app://login-callback` to Redirect URLs, raise the password minimum to 8 and turn on leaked-password protection
- [ ] **(you)** Delete the test account used during development (or change its password), and the three QA accounts made for the onboarding tests (listed in `SECURITY_AUDIT.md`)
- [ ] **(you)** Decide on `akarat.ai` links: if you own the domain, publish `/.well-known/assetlinks.json` there; if not, remove that intent filter from `AndroidManifest.xml`
- [ ] **(you)** Update the privacy policy (website and app) with the wording below
- [ ] **(you)** Create the two app-locked Google Maps keys and check the website's key restrictions (section 5)
- [ ] Test on at least one real Android phone

### Privacy policy: suggested additions

The policy in the app is the website's earlier wording, word for word. The
website has since rewritten its own (`lib/legal.js`, served at `/privacy`);
neither covers what the app adds yet. Draft wording for you (and a lawyer, if you use one)
to review, and to translate for the Arabic version:

> **Voice search.** When you tap the microphone, your phone's own speech
> service (Apple's on iPhone, Google's on most Android phones) turns what you
> say into text. Depending on your phone this happens on the device or on
> Apple's or Google's servers, under their privacy policies. Akarat.ai
> receives only the text, never the recording, and treats it like a typed
> search.
>
> **Maps.** Maps are loaded from Google Maps, which sees your device's
> internet address and the area you are viewing, under Google's privacy
> policy.
>
> **Inquiries.** When you send an inquiry about a property, its owner sees
> the name, email address and phone number you enter, and your message.
>
> **Phone number.** If you sign up or sign in with your phone number, we keep
> the number on your account to sign you in. Each sign-in code is sent to it
> by text message or WhatsApp through our messaging provider, Twilio. We do
> not use the number for marketing. Phone numbers are sometimes passed to a
> new owner by the phone company: if you change your number, update it in
> Profile.
>
> **Sign in with Apple.** If you sign in with Apple, Apple tells us an account
> identifier, the email address you choose to share (it may be a private relay
> address that forwards to you) and, the first time only, your name. We use
> them only to sign you in. Deleting your account also removes Akarat.ai from
> your Apple ID.
>
> **Profile picture.** A picture you choose for your profile stays on your
> phone. It is not uploaded to Akarat.ai, and no one else sees it.
>
> **Reports and hidden advertisers.** You can report a listing from its page:
> we keep the report, your account and what you wrote, to review it. Hiding an
> advertiser is kept on your device only.
>
> **Facebook.** If you sign in with Facebook, Facebook tells us your name, your
> email address (if you have one there) and an account identifier, under
> Facebook's privacy policy; we use them only to sign you in. You can
> disconnect Facebook in Profile at any time.
>
> **Deleting your account.** You can delete your account and everything in it
> from the app (Profile → Delete account) or by writing to
> privacy@akarat.ai.

For the store forms: Google Play's *Data safety* and Apple's *App Privacy*
answers follow from the same facts: account details (name, email, and the phone
number for those who sign in with one), content you create (listings, photos,
inquiries), search text; no location, no advertising, no tracking, nothing
sold. Phone numbers are shared with Twilio only to deliver sign-in codes.
Sign in with Apple and Facebook sign-in add nothing to the forms beyond the
account details above (no Facebook SDK in the app); reports are user content,
like inquiries; the profile picture never leaves the phone, so it is not
collected; Meta asks for the privacy policy URL and a
data-deletion page for the Facebook app itself: the website's `/privacy` and
`/data-deletion`.
