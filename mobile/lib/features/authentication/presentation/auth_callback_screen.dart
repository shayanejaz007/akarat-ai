import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/motion.dart';
import '../../../shared/services/preferences.dart';
import '../../../shared/services/supabase_providers.dart';
import '../../tour/tour_store.dart';
import '../auth_service.dart';
import 'auth_scaffold.dart';

/// Where Supabase's redirects land: email confirmation, Google, Facebook,
/// connecting Facebook to an account, password reset. supabase_flutter
/// exchanges the code in the link for a session on its own; this screen
/// waits for the outcome and moves on.
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key, required this.params});
  final Map<String, String> params;

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  StreamSubscription<AuthState>? _sub;
  Timer? _timeout;
  bool _failed = false;
  bool _left = false;

  /// Why it failed, as Supabase put it (`identity_already_exists`,
  /// `access_denied`…), or empty.
  String _failure = '';

  @override
  void initState() {
    super.initState();
    final params = widget.params;
    if (params.containsKey('error') || params.containsKey('error_description')) {
      _failed = true;
      _failure = params['error_code'] ?? params['error'] ?? '';
      unawaited(ref.read(preferencesProvider).setPendingLink(null));
      return;
    }
    final auth = ref.read(supabaseClientProvider).auth;
    _sub = auth.onAuthStateChange.listen(
      (s) {
        if (!mounted) return;
        if (s.event == AuthChangeEvent.passwordRecovery) return; // the app routes this one
        if (s.session != null) _arrive(s.session!.user);
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    if (auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _arrive(auth.currentUser);
      });
    }
    _timeout = Timer(const Duration(seconds: 15), () {
      if (mounted && ref.read(supabaseClientProvider).auth.currentSession == null) setState(() => _failed = true);
    });
  }

  /// On, once. Facebook connected from Profile goes back there, saying so;
  /// a brand-new account starts on Home, where its welcome tour begins;
  /// anyone else lands on their profile.
  void _arrive(User? user) {
    if (_left) return;
    _left = true;
    final prefs = ref.read(preferencesProvider);
    if (prefs.pendingLink == 'facebook') {
      unawaited(prefs.setPendingLink(null));
      if (facebookIdentity(user) != null) {
        showSuccess(context, context.l10n.facebookConnected);
        context.go(Routes.profile);
        return;
      }
    }
    context.go(TourStore.isNewAccount(user) ? Routes.home : Routes.profile);
  }

  static String _failureText(AppLocalizations l, String reason) => switch (reason) {
    'identity_already_exists' => l.facebookTaken,
    'manual_linking_disabled' => l.facebookLinkDisabled,
    'access_denied' => l.authCancelled,
    _ => l.authLinkExpired,
  };

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_failed) {
      // Signed in (connecting Facebook from Profile): back there; otherwise
      // to sign-in.
      final signedIn = ref.watch(currentUserProvider) != null;
      final text = _failureText(l, _failure);
      return AuthScaffold(
        title: l.authCallbackFailedTitle,
        body: text,
        children: [
          AuthMessage(text: text),
          FilledButton(
            onPressed: () => context.go(signedIn ? Routes.profile : Routes.signIn),
            child: Text(signedIn ? l.authBackToProfile : l.actionSignIn),
          ),
        ],
      );
    }
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 56),
            const SizedBox(height: Space.lg),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator.adaptive(strokeWidth: 2.6)),
            const SizedBox(height: Space.md),
            Text(l.authCallbackWorking, style: context.text.bodyLarge),
          ],
        ),
      ),
    );
  }
}
