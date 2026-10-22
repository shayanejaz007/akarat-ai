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

/// Fires whenever the session changes. GoRouter re-runs its redirect on it,
/// so a protected screen bounces to sign-in the moment a session ends.
class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier(GoTrueClient auth) {
    _sub = auth.onAuthStateChange.listen((_) => notifyListeners(), onError: (Object _) {});
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
