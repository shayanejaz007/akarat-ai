import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/motion.dart';
import '../../tour/tour_store.dart';
import '../auth_service.dart';
import 'auth_scaffold.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key, this.next});
  final String? next;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _message;
  bool _ok = false;

  /// The address a confirmation link was sent to; the form gives way to a
  /// clear "check your email" page while it is set.
  String? _sentTo;

  // Above Supabase's default of 6; set the project minimum to match (SECURITY_AUDIT.md S6).
  static const minPassword = 8;

  @override
  void dispose() {
    for (final c in [_name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _facebook() async {
    setState(() => _message = null);
    final l = context.l10n;
    final fallback = context.failureMessage;
    try {
      await ref.read(authServiceProvider).signInWithFacebook();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _message = isProviderDisabled(e) ? l.authFacebookDisabled : authErrorMessage(l, e, fallback);
        });
      }
    }
  }

  /// A first Sign in with Apple makes the account (with the name Apple
  /// shares); on an iPhone it finishes here.
  Future<void> _apple() async {
    setState(() => _message = null);
    final l = context.l10n;
    final fallback = context.failureMessage;
    try {
      if (await ref.read(authServiceProvider).signInWithApple() != AuthOutcome.done || !mounted) return;
      arriveSignedIn(context, ref, widget.next);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _message = appleSignInErrorMessage(l, e, fallback);
        });
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _message = null);
    if (!_form.currentState!.validate()) return;
    final l = context.l10n;
    final lang = context.lang;
    final fallback = context.failureMessage;
    final name = _name.text.trim();
    try {
      final signedIn = await ref
          .read(authServiceProvider)
          .signUp(
            email: _email.text,
            password: _password.text,
            name: _name.text,
            locale: lang,
            extra: ref.read(tourStoreProvider).signUpData(),
          );
      if (!mounted) return;
      if (signedIn) {
        // Signed straight in: say so, on the root overlay, as the page
        // closes and the reader goes on to where they were going.
        TextInput.finishAutofillContext();
        showSuccess(context, name.isEmpty ? l.authAccountCreated : l.authAccountCreatedName(name));
        // A new account starts on Home, where its welcome tour begins,
        // unless it was on its way somewhere.
        if (widget.next == null) {
          context.go(Routes.home);
        } else {
          leaveAuth(context, widget.next);
        }
        return;
      }
      // Email confirmation is on: the account exists, but there is no
      // session until the link in the email is followed.
      setState(() {
        _sentTo = _email.text.trim();
        _password.clear();
      });
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
    final phone = ref.watch(phoneSignInAvailableProvider).value ?? false;
    final platform = Theme.of(context).platform;
    final apple = ref.watch(appleSignInAvailableProvider).value ?? false;
    final facebook =
        offersSocialLogin(platform, apple: apple) && (ref.watch(facebookSignInAvailableProvider).value ?? false);
    // Apple's way in leads on Apple's platforms, as its guidelines ask.
    final appleFirst = hasNativeAppleSignIn(platform);
    final appleButton = AppleButton(label: l.authApple, onPressed: _apple);
    final ways = <Widget>[
      if (apple && appleFirst) appleButton,
      // A Facebook user's first sign-in makes their account.
      if (facebook)
        BusyButton(
          label: l.authFacebook,
          leading: const FacebookMark(),
          style: BusyButtonStyle.outlined,
          onPressed: _facebook,
        ),
      if (apple && !appleFirst) appleButton,
      if (phone)
        BusyButton(
          label: l.authPhoneSignUpButton,
          icon: Icons.phone_iphone_rounded,
          style: BusyButtonStyle.outlined,
          onPressed: () async => context.pushReplacement(Routes.phoneSignUp(widget.next)),
        ),
    ];
    final sentTo = _sentTo;
    if (sentTo != null) {
      return _CheckEmail(
        email: sentTo,
        onSignIn: () =>
            context.pushReplacement(widget.next == null ? Routes.signIn : Routes.withNext(Routes.signIn, widget.next!)),
        onBack: () => setState(() => _sentTo = null),
      );
    }
    return AuthScaffold(
      title: l.authSignUpTitle,
      body: l.authSignUpBody,
      children: [
        if (_message != null) AuthMessage(text: _message!, ok: _ok),
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  maxLength: 120,
                  decoration: InputDecoration(labelText: l.fieldName, counterText: ''),
                  validator: (v) => (v ?? '').trim().isEmpty ? l.validationRequired : null,
                ),
                const SizedBox(height: Space.sm),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l.fieldEmail),
                  validator: (v) => emailPattern.hasMatch((v ?? '').trim()) ? null : l.validationEmail,
                ),
                const SizedBox(height: Space.sm),
                PasswordField(
                  controller: _password,
                  label: l.fieldPassword,
                  newPassword: true,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v ?? '').length < minPassword ? l.validationPasswordShort(minPassword) : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        BusyButton(label: l.authCreateAccount, busyLabel: l.previewWorking, onPressed: _submit),
        const SizedBox(height: Space.md),
        const AuthAgreement(),
        if (ways.isNotEmpty) const AuthDivider(),
        for (final (i, way) in ways.indexed) ...[if (i > 0) const SizedBox(height: Space.sm), way],
        const SizedBox(height: Space.xl),
        Center(
          child: TextButton(
            onPressed: () => context.pushReplacement(
              widget.next == null ? Routes.signIn : Routes.withNext(Routes.signIn, widget.next!),
            ),
            child: Text(l.authHaveAccount, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}

/// After sign-up with confirmation on: a whole page that says what happened
/// and what to do next, instead of a line the reader may never scroll to.
class _CheckEmail extends StatelessWidget {
  const _CheckEmail({required this.email, required this.onSignIn, required this.onBack});
  final String email;
  final VoidCallback onSignIn;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(leading: CloseButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home))),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.xxl),
              children: [
                Reveal(
                  child: Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(c.emerald.withValues(alpha: 0.12), c.surface),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.mark_email_read_outlined, size: 42, color: c.emerald),
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                Reveal(
                  index: 1,
                  child: Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(l.authCheckEmailTitle, textAlign: TextAlign.center, style: context.text.headlineSmall),
                  ),
                ),
                const SizedBox(height: Space.sm),
                Reveal(
                  index: 2,
                  child: Text(
                    l.authCheckEmailBody(email),
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                ),
                const SizedBox(height: Space.xl),
                FilledButton(onPressed: onSignIn, child: Text(l.authCheckEmailSignIn)),
                const SizedBox(height: Space.xs),
                TextButton(onPressed: onBack, child: Text(l.authCheckEmailWrong)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
