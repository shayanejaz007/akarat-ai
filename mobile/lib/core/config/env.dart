import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
/// Every value here is PUBLIC: it ends up inside the app bundle, where anyone
/// can read it. That is safe only for things designed to be exposed, which is
/// the same rule the website follows for its `NEXT_PUBLIC_*` variables:
///
/// * the Supabase project URL and publishable key, bounded by Row Level
///   Security on the server;
/// * the URL of the existing Vercel deployment, whose API routes hold every
///   privileged credential server-side;
/// * the Google Maps keys for the native map SDKs: public by design like the
///   website's Maps key, and safe because Google Cloud locks each one to this
///   app (Android package + signing certificate, iOS bundle id) and to the
///   Maps SDK alone. Map loads in the mobile SDKs are free, so a copied key
///   cannot run up a bill.
///
/// `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET` and any search-provider or LLM
/// key must never be passed here. Nothing in the app needs them: privileged
/// work happens behind `/api` on Vercel.
///
/// Values come from `--dart-define` or `--dart-define-from-file`:
///
/// ```sh
/// flutter run --dart-define-from-file=env/production.json
/// ```
///
/// The fallbacks are the project's production URL and publishable key, which
/// the website also ships as literals in lib/supabase.js. They exist so a fresh
/// checkout runs; set the defines to point a build at a staging project.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ppqftdcdpshfokjqnuhq.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_Xrp8dp25j0fk4-XNpbS5eQ_hXZnIfrH',
  );

  /// The deployed website. Its `/api/ai/search` route runs the search
  /// pipeline, and its `/en|ar/property/<id>` pages are what shared links open.
  static const String siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://www.akarat.ai');

  /// Raster map tiles (`{z}/{x}/{y}`). The default is OpenStreetMap's own
  /// server, which needs no key and suits development and light use; its
  /// usage policy asks heavy users to bring their own provider, so point this
  /// at a commercial tile service (MapTiler, Stadia, Mapbox raster) for a
  /// release with real traffic. Attribution is shown on every map.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Google Maps SDK keys, one per platform: Google Cloud restricts a key to
  /// one kind of app. Android's also reaches the manifest at build time
  /// (android/app/build.gradle.kts reads it from the same dart-defines). With
  /// no key for the platform, maps are drawn from [mapTileUrl] instead.
  static const String googleMapsAndroidKey = String.fromEnvironment('GOOGLE_MAPS_ANDROID_KEY');
  static const String googleMapsIosKey = String.fromEnvironment('GOOGLE_MAPS_IOS_KEY');

  /// This platform's Google Maps key, or empty.
  static String get googleMapsKey => switch (defaultTargetPlatform) {
    TargetPlatform.android => googleMapsAndroidKey,
    TargetPlatform.iOS => googleMapsIosKey,
    _ => '',
  };

  /// Phone sign-in: `auto` (the default) offers it once the Supabase
  /// project's Phone provider is switched on, read from the project's public
  /// auth settings, so it appears without an app update; `off` never offers
  /// it; `on` always does (to try the screens before the provider is ready).
  static const String phoneSignIn = String.fromEnvironment('PHONE_SIGNIN', defaultValue: 'auto');

  /// Facebook sign-in, and connecting Facebook to an account in Profile:
  /// `auto` (the default) offers it once the project's Facebook provider is
  /// switched on; `off` never; `on` always (to try the screens first). On iOS
  /// only beside Sign in with Apple, which Apple requires next to any social
  /// login. The Facebook App ID and secret live in Supabase, never here.
  static const String facebookSignIn = String.fromEnvironment('FACEBOOK_SIGNIN', defaultValue: 'auto');

  /// Sign in with Apple, and connecting Apple to an account in Profile:
  /// `auto` (the default) offers it once the project's Apple provider is
  /// switched on; `off` never; `on` always (to try the screens first). On an
  /// iPhone it is Apple's own sheet; elsewhere, Apple's page in the browser.
  /// While it is offered, iPhones offer Google and Facebook too (App Store
  /// guideline 4.8). Apple's keys live in Supabase, never here.
  static const String appleSignIn = String.fromEnvironment('APPLE_SIGNIN', defaultValue: 'auto');

  /// How one-time codes travel: `sms`, or `whatsapp` once Twilio has approved
  /// a WhatsApp sender with its authentication template. Twilio's credentials
  /// live in Supabase (Authentication → Providers → Phone), never here; this
  /// only names the channel. The website's equivalent is OTP_CHANNEL in
  /// lib/supabase.js.
  static const String otpChannel = String.fromEnvironment('OTP_CHANNEL', defaultValue: 'sms');

  /// Custom URL scheme registered by both native projects. Used for the auth
  /// redirects Supabase sends back to the app and for in-app deep links.
  static const String appScheme = 'ai.akarat.app';

  /// Where Supabase sends the browser after email confirmation, Google
  /// sign-in, and password recovery. Must be listed under Authentication →
  /// URL Configuration → Redirect URLs, or Supabase falls back to the site.
  static const String authCallbackUrl = '$appScheme://login-callback';

  /// Shown in Profile. Keep in step with `version:` in pubspec.yaml, or pass
  /// --dart-define=APP_VERSION from CI.
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  static const String supportEmail = 'hello@akarat.ai';
  static const String privacyEmail = 'privacy@akarat.ai';

  static Uri get searchEndpoint => Uri.parse('$siteUrl/api/ai/search');
  static Uri get accountEndpoint => Uri.parse('$siteUrl/api/account');

  static Uri listingWebUrl(String id, String lang) => Uri.parse('$siteUrl/${lang == 'ar' ? 'ar' : 'en'}/property/$id');
}
