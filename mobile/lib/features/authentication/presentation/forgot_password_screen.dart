import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../auth_service.dart';
import 'auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _message;
  bool _ok = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _message = null);
    if (!_form.currentState!.validate()) return;
    final l = context.l10n;
    final fallback = context.failureMessage;
    try {
      await ref.read(authServiceProvider).sendPasswordReset(_email.text);
      // Same answer whether or not the address has an account, so the form
      // cannot be used to find out who is registered.
      if (mounted) {
        setState(() {
          _ok = true;
          _message = l.authResetSent;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _message = authErrorMessage(l, e, fallback);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthScaffold(
      title: l.authForgotTitle,
      body: l.authForgotBody,
      children: [
        if (_message != null) AuthMessage(text: _message!, ok: _ok),
        Form(
          key: _form,
          child: TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: l.fieldEmail),
            validator: (v) => emailPattern.hasMatch((v ?? '').trim()) ? null : l.validationEmail,
          ),
        ),
        const SizedBox(height: Space.lg),
        BusyButton(label: l.authSendLink, busyLabel: l.previewWorking, onPressed: _submit),
      ],
    );
  }
}
