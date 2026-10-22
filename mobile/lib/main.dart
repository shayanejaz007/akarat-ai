import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/launch_splash.dart';
import 'core/config/env.dart';
import 'core/security/secure_session_storage.dart';
import 'core/widgets/map_layer.dart';
import 'shared/services/preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The bundled fonts' licences (SIL OFL), on the open-source licences page.
  LicenseRegistry.addLicense(() async* {
    for (final (font, file) in const [
      ('Inter', 'OFL-Inter.txt'),
      ('IBM Plex Sans Arabic', 'OFL-IBMPlexSansArabic.txt'),
      ('Poppins', 'OFL-Poppins.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/$file'));
    }
  });

  if (kReleaseMode) {
    // No crash-reporting service is configured, so release builds keep
    // errors out of the device log rather than printing internals.
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // The opening is on screen from the first frame, picking up exactly where
  // the launch screen leaves off. It starts the app (below) when it is ready
  // for the work, and puts it on screen behind itself when that will not
  // show: so its intro plays without stutter, and the app is there at its end.
  final prefs = SharedPreferences.getInstance();
  runApp(LaunchSplash(start: () => _start(prefs), language: prefs.then((p) => Preferences(p).lang)));
}

/// What the first screen needs, in parallel, then the app. Reading the
/// session from the keystore is the slow part (a moment on many phones, two
/// seconds on an emulator); the splash plays over it.
Future<Widget> _start(Future<SharedPreferences> preferences) async {
  final (prefs, _, _, _) = await (
    preferences,
    // The one date format the app uses (core/utils/formatters.dart); every
    // locale's data was most of a second of start-up for nothing.
    initializeDateFormatting('en_GB'),
    // Google's maps when a key is built in; the key-free maps otherwise.
    GoogleMapsSetup.init(),
    Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        // PKCE: the auth code in a redirect is useless without the verifier
        // this device stored, so an intercepted link cannot be replayed.
        authFlowType: AuthFlowType.pkce,
        localStorage: SecureSessionStorage(),
        pkceAsyncStorage: SecurePkceStorage(),
      ),
      debug: false,
    ),
  ).wait;

  return ProviderScope(
    overrides: [preferencesProvider.overrideWithValue(Preferences(prefs))],
    // Riverpod 3 retries failed providers by default. A failed listing
    // query is shown with a retry button instead of being re-sent silently.
    retry: (retryCount, error) => null,
    child: const AkaratApp(),
  );
}
