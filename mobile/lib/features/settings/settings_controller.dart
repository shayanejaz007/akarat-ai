import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/repositories/account_repositories.dart';
import '../../shared/services/preferences.dart';
import '../../shared/services/supabase_providers.dart';

/// The interface language. Order of authority: what the reader chose, then
/// the device language if it is English or Arabic, then Arabic — the
/// website's default, because most of the people Akarat.ai serves read
/// Arabic first.
final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => _chosen ?? _device();

  Locale? get _chosen => switch (ref.read(preferencesProvider).lang) {
    final String l when l == 'en' || l == 'ar' => Locale(l),
    _ => null,
  };

  static Locale _device() =>
      Locale(WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en' ? 'en' : 'ar');

  /// The device language changed while the app was open: follow it, unless
  /// the reader chose a language here.
  void followDevice() {
    if (_chosen != null) return;
    final device = _device();
    if (device != state) state = device;
  }

  /// Switches immediately, remembers the choice, and — when signed in —
  /// writes it to the profile so the account's language follows the reader
  /// to the website. A failed profile write never blocks the switch.
  Future<void> set(String lang) async {
    if (lang != 'en' && lang != 'ar') return;
    state = Locale(lang);
    await ref.read(preferencesProvider).setLang(lang);
    if (ref.read(isSignedInProvider)) {
      unawaited(ref.read(profileRepositoryProvider).update(locale: lang).catchError((Object _) {}));
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => switch (ref.read(preferencesProvider).theme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(preferencesProvider).setTheme(mode.name);
  }
}
