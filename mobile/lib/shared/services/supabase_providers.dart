import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Supabase client: the website's own project, publishable key only.
/// Overridable so tests never reach a real database.
final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Auth events, as they happen: sign-in, sign-out, token refresh, and
/// PASSWORD_RECOVERY when a reset link brings the reader back.
final authEventsProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// The signed-in user, or null. Re-evaluated on every auth event, so anything
/// that watches it refreshes on sign-in and sign-out without polling.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authEventsProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

final isSignedInProvider = Provider<bool>((ref) => ref.watch(currentUserProvider) != null);

/// Fires when a session ends. GoRouter re-runs its redirect on it, so a
/// protected screen bounces to sign-in the moment the session goes.
///
/// A new session is not announced here. The screen that signed someone in
/// leaves by itself (back where they were, or on to where they were going),
/// as does the auth callback page after a sign-in in the browser. A router
/// redirect fired by the same event raced that: on a sign-in page opened over
/// another screen, the router moved and the page stayed on screen.
class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier(GoTrueClient auth) {
    _sub = auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) notifyListeners();
    }, onError: (Object _) {});
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
