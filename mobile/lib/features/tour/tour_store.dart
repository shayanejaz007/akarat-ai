import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/services/preferences.dart';
import '../../shared/services/supabase_providers.dart';
import 'tour.dart';

/// Where the guided tours' progress lives.
///
/// Finished (or skipped) tours are kept on the device, and, for a signed-in
/// reader, in their Supabase account (auth user metadata, the reader's own
/// profile data): so a tour is not repeated after a reinstall, on a second
/// phone, or after signing out and back in. Nothing here grants anything;
/// the database never reads these keys.
///
/// Account keys:
/// * `tours_done`: the tours this person has finished or skipped.
/// * `tour_pending`: the account's welcome is owed. Set when the account is
///   created in the app (or on a Google account's very first sign-in) and
///   cleared when the welcome ends. Accounts that existed before are never
///   treated as new.
///
/// The step reached is kept only on the device, so a tour cut short by
/// closing the app picks up where it was.
final tourStoreProvider = Provider<TourStore>(
  (ref) => TourStore(
    ref.watch(preferencesProvider),
    user: () => ref.read(currentUserProvider),
    save: (data) => ref.read(supabaseClientProvider).auth.updateUser(UserAttributes(data: data)),
  ),
);

class TourStore {
  TourStore(this._prefs, {required User? Function() user, required Future<Object?> Function(Map<String, Object>) save})
    : _currentUser = user,
      _saveToAccount = save;

  final Preferences _prefs;
  final User? Function() _currentUser;

  /// Merges keys into the signed-in account's metadata.
  final Future<Object?> Function(Map<String, Object>) _saveToAccount;

  User? get _user => _currentUser();
  Map<String, dynamic> get _meta => _user?.userMetadata ?? const {};

  Set<String> get _accountDone => _doneOn(_meta);
  static Set<String> _doneOn(Map<String, dynamic> meta) => {...?(meta['tours_done'] as List?)?.whereType<String>()};
  Set<String> get _deviceDone => {
    for (final t in TourId.values)
      if (_prefs.tourSeen(t.name)) t.name,
  };

  /// Finished or skipped, here or on the account.
  bool done(TourId id) => _prefs.tourSeen(id.name) || _accountDone.contains(id.name);

  /// The signed-in account is new (see [isNewAccount]) and this device has
  /// not welcomed it yet.
  bool get welcomeOwed {
    final user = _user;
    return user != null && isNewAccount(user) && !_prefs.welcomed(user.id);
  }

  /// A brand-new account: made by the app's sign-up form (its welcome tour
  /// is owed), or signing in for the very first time, moments after it was
  /// created (Google). Accounts that existed before are never new.
  static bool isNewAccount(User? user) {
    if (user == null) return false;
    if (user.userMetadata?['tour_pending'] == true) return true;
    final meta = user.userMetadata ?? const {};
    if (meta.containsKey('tours_done') || meta.containsKey('tour_pending')) return false;
    return _firstSignIn(user);
  }

  static bool _firstSignIn(User user) {
    final created = DateTime.tryParse(user.createdAt);
    final signedIn = DateTime.tryParse(user.lastSignInAt ?? '');
    return created != null && signedIn != null && signedIn.difference(created).inMinutes.abs() < 3;
  }

  /// Whether [id] should start by itself on its screen.
  ///
  /// The main tour (finding, saving, listing) greets a new account after
  /// sign-up, and a first-time guest after the introduction; never an
  /// existing account. The other tours explain their own screen the first
  /// time it is reached.
  bool shouldStart(TourId id) {
    if (!_prefs.onboarded) return false;
    // Signed in, the main tour is a new account's welcome.
    if (id == TourId.explore && _user != null) return welcomeOwed;
    return !done(id);
  }

  /// The step a tour cut short was on. The welcome counts its own steps, so
  /// it never resumes at a place in the guest tour, or the other way round.
  int step(TourId id, {bool welcome = false}) => _prefs.tourStep(_stepKey(id, welcome));
  Future<void> setStep(TourId id, int step, {bool welcome = false}) => _prefs.setTourStep(_stepKey(id, welcome), step);
  static String _stepKey(TourId id, bool welcome) => welcome ? 'welcome' : id.name;

  /// The tour ended (finished, or skipped on purpose). Ending the main tour
  /// signed in is the account's welcome, given.
  Future<void> markDone(TourId id) async {
    await _prefs.setTourSeen(id.name);
    await _prefs.clearTourStep(id.name);
    final main = id == TourId.explore;
    if (main) await _prefs.clearTourStep('welcome');
    final user = _user;
    if (user == null) return;
    if (main) await _prefs.setWelcomed(user.id);
    await _save({
      'tours_done': ({..._accountDone, ..._deviceDone}.toList()..sort()),
      if (main) 'tour_pending': false,
    });
  }

  /// Account data for a new sign-up: the welcome is owed, and the tours
  /// already seen on this device travel with the account.
  Map<String, Object> signUpData() => {'tour_pending': true, 'tours_done': _deviceDone.toList()..sort()};

  /// On sign-in and at launch: brings the account and the device into line.
  /// An account made outside the app's sign-up form (Google, the website)
  /// has no tour keys yet; it is new only if this is its very first
  /// sign-in, moments after it was created.
  ///
  /// [signedIn] is the user the auth event carries: at that moment the app's
  /// own idea of the current user may not have caught up yet.
  Future<void> sync([User? signedIn]) async {
    final user = signedIn ?? _user;
    if (user == null) return;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final accountDone = _doneOn(meta);
    for (final t in accountDone) {
      if (TourId.values.any((v) => v.name == t)) await _prefs.setTourSeen(t);
    }
    if (!meta.containsKey('tours_done') && !meta.containsKey('tour_pending')) {
      await _save({
        'tour_pending': _firstSignIn(user) && !_prefs.welcomed(user.id),
        'tours_done': _deviceDone.toList()..sort(),
      });
      return;
    }
    // Tours finished offline or as a guest, and a welcome given offline, not
    // yet on the account.
    final missing = _deviceDone.difference(accountDone);
    final welcomedHere = meta['tour_pending'] == true && _prefs.welcomed(user.id);
    if (missing.isNotEmpty || welcomedHere) {
      await _save({
        'tours_done': ({...accountDone, ..._deviceDone}.toList()..sort()),
        if (welcomedHere) 'tour_pending': false,
      });
    }
  }

  /// Offline, the device keeps the record and [sync] sends it later.
  Future<void> _save(Map<String, Object> data) async {
    try {
      await _saveToAccount(data);
    } on Object {
      // Kept on the device; synced at the next launch or sign-in.
    }
  }
}
