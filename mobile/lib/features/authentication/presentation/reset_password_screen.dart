import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../../shared/services/supabase_providers.dart';
import '../auth_service.dart';
import 'auth_scaffold.dart';

/// Reached from the password-reset email, after the recovery link has
/// signed the reader in with a short-lived session.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final l = context.l10n;
    final fallback = context.failureMessage;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authServiceProvider).updatePassword(_password.text);
      messenger.showSnackBar(SnackBar(content: Text(l.authPasswordUpdated)));
      if (mounted) context.go(Routes.profile);
    } on Object catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(l, e, fallback));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final signedIn = ref.watch(isSignedInProvider);
    return AuthScaffold(
      title: l.authResetTitle,
      body: l.authResetBody,
      children: [
        if (!signedIn) AuthMessage(text: l.authLinkExpired),
        if (_error != null) AuthMessage(text: _error!),
        Form(
          key: _form,
          child: PasswordField(
            controller: _password,
            label: l.fieldNewPassword,
            newPassword: true,
            onSubmitted: (_) => _submit(),
            validator: (v) => (v ?? '').length < 8 ? l.validationPasswordShort(8) : null,
          ),
        ),
        const SizedBox(height: Space.lg),
        BusyButton(label: l.authSavePassword, busyLabel: l.previewWorking, onPressed: signedIn ? _submit : null),
        if (!signedIn) ...[
          const SizedBox(height: Space.sm),
          TextButton(onPressed: () => context.go(Routes.forgotPassword), child: Text(l.authSendLink)),
        ],
      ],
    );
  }
}
