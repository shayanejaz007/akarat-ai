import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/motion.dart';
import '../auth_service.dart';
import 'auth_scaffold.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.next});
  final String? next;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final l = context.l10n;
    final fallback = context.failureMessage;
    try {
      await ref.read(authServiceProvider).signIn(_email.text, _password.text);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      // On the root overlay, so it stays while the page closes.
      showSuccess(context, l.authWelcomeBack);
      leaveAuth(context, widget.next);
    } on Object catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(l, e, fallback));
    }
  }

  Future<void> _google() async {
    setState(() => _error = null);
    final l = context.l10n;
    final fallback = context.failureMessage;
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on Object catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(l, e, fallback));
    }
  }

  Future<void> _facebook() async {
    setState(() => _error = null);
    final l = context.l10n;
    final fallback = context.failureMessage;
    try {
      await ref.read(authServiceProvider).signInWithFacebook();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = isProviderDisabled(e) ? l.authFacebookDisabled : authErrorMessage(l, e, fallback));
      }
    }
  }

  Future<void> _apple() async {
    setState(() => _error = null);
    final l = context.l10n;
    final fallback = context.failureMessage;
    try {
      // On an iPhone it finishes here; elsewhere the browser takes over.
      if (await ref.read(authServiceProvider).signInWithApple() != AuthOutcome.done || !mounted) return;
      arriveSignedIn(context, ref, widget.next);
    } on Object catch (e) {
      if (mounted) setState(() => _error = appleSignInErrorMessage(l, e, fallback));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final platform = Theme.of(context).platform;
    final apple = ref.watch(appleSignInAvailableProvider).value ?? false;
    final social = offersSocialLogin(platform, apple: apple);
    final facebook = social && (ref.watch(facebookSignInAvailableProvider).value ?? false);
    final phone = ref.watch(phoneSignInAvailableProvider).value ?? false;
    // Apple's way in leads on Apple's platforms, as its guidelines ask.
    final appleFirst = hasNativeAppleSignIn(platform);
    final appleButton = AppleButton(label: l.authApple, onPressed: _apple);
    final ways = <Widget>[
      if (apple && appleFirst) appleButton,
      if (social)
        BusyButton(
          label: l.authGoogle,
          // Google's own mark, as its branding guidelines ask.
          leading: Image.asset('assets/images/google-g.png', width: 20, height: 20),
          style: BusyButtonStyle.outlined,
          onPressed: _google,
        ),
      if (facebook)
        BusyButton(
          label: l.authFacebook,
          leading: const FacebookMark(),
          style: BusyButtonStyle.outlined,
          onPressed: _facebook,
        ),
      if (apple && !appleFirst) appleButton,
      // Phone sign-in is the project's own (Supabase), not a third-party
      // login, so it is offered on iOS too.
      if (phone)
        BusyButton(
          label: l.authPhoneButton,
          icon: Icons.phone_iphone_rounded,
          style: BusyButtonStyle.outlined,
          onPressed: () async => context.pushReplacement(
            widget.next == null ? Routes.phoneSignIn : Routes.withNext(Routes.phoneSignIn, widget.next!),
          ),
        ),
    ];
    return AuthScaffold(
      title: widget.next != null ? l.authRequiredTitle : l.authSignInTitle,
      body: widget.next != null ? l.authRequiredBody : l.authSignInBody,
      children: [
        if (_error != null) AuthMessage(text: _error!),
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l.fieldEmail),
                  validator: (v) => emailPattern.hasMatch((v ?? '').trim()) ? null : l.validationEmail,
                ),
                const SizedBox(height: Space.sm),
                PasswordField(
                  controller: _password,
                  label: l.fieldPassword,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v ?? '').isEmpty ? l.validationRequired : null,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: () => context.push(Routes.forgotPassword), child: Text(l.authForgot)),
        ),
        const SizedBox(height: Space.xs),
        BusyButton(label: l.actionSignIn, busyLabel: l.previewWorking, onPressed: _submit),
        // Google and Facebook on iOS only beside Apple (offersSocialLogin);
        // email and phone everywhere. An account made any way is the same
        // account.
        if (ways.isNotEmpty) const AuthDivider(),
        for (final (i, way) in ways.indexed) ...[if (i > 0) const SizedBox(height: Space.sm), way],
        const SizedBox(height: Space.xl),
        Center(
          child: TextButton(
            onPressed: () => context.pushReplacement(
              widget.next == null ? Routes.signUp : Routes.withNext(Routes.signUp, widget.next!),
            ),
            // Centred like the form above it, also when large text wraps it.
            child: Text(l.authNoAccount, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
