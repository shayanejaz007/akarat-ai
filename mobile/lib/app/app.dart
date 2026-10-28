import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/settings/settings_controller.dart';
import '../features/tour/tour_store.dart';
import '../shared/services/activity.dart';
import '../shared/services/refresh.dart';
import '../shared/services/supabase_providers.dart';
import 'localization/l10n.dart';
import 'router/app_router.dart';
import 'router/routes.dart';
import 'theme/app_theme.dart';

class AkaratApp extends ConsumerStatefulWidget {
  const AkaratApp({super.key});

  @override
  ConsumerState<AkaratApp> createState() => _AkaratAppState();
}

class _AkaratAppState extends ConsumerState<AkaratApp> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _auth;
  DateTime _pausedAt = DateTime.now();

  /// "On Akarat.ai right now" in the admin panel: a ping on open and once a
  /// minute while the app is in front. Stopped in the background.
  Timer? _beat;

  void _startBeat() {
    _beat?.cancel();
    unawaited(ref.read(activityProvider).heartbeat());
    _beat = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(ref.read(activityProvider).heartbeat()));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBeat();
    // A password-reset link signs the reader in with a recovery session; the
    // only sensible next screen is "choose a new password".
    _auth = ref.read(supabaseClientProvider).auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        ref.read(routerProvider).go(Routes.resetPassword);
      }
      // Tours seen on this device and on the account, brought into line
      // (and a brand-new Google account owed its welcome tour). With the
      // event's own user: this listener can run before the app's user state
      // has heard of the sign-in.
      if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.initialSession) {
        unawaited(ref.read(tourStoreProvider).sync(state.session?.user));
      }
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _beat?.cancel();
    unawaited(_auth?.cancel());
    super.dispose();
  }

  /// The device language changed (the app follows it until the reader picks
  /// one in the app). Mid-tour too: the tour's words follow.
  @override
  void didChangeLocales(List<Locale>? locales) => ref.read(localeProvider.notifier).followDevice();

  /// Coming back after a while: listings may have changed on the website, so
  /// lists refetch rather than presenting old availability as current.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      _beat?.cancel();
    }
    if (state == AppLifecycleState.resumed) {
      _startBeat();
      if (DateTime.now().difference(_pausedAt) > const Duration(minutes: 3)) {
        ref.read(refreshTickProvider.notifier).bump();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final mode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    final lang = locale.languageCode;
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      theme: AppTheme.build(brightness: Brightness.light, lang: lang),
      darkTheme: AppTheme.build(brightness: Brightness.dark, lang: lang),
      themeMode: mode,
      themeAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, child) {
        // Honour the reader's text size, within a range every layout here
        // has been checked at.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.6)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
