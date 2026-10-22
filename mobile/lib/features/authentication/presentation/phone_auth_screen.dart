import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OtpChannel, User;

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/motion.dart';
import '../../../shared/services/supabase_providers.dart';
import '../../tour/tour_store.dart';
import '../auth_service.dart';
import 'auth_scaffold.dart';
import 'phone_fields.dart';

/// Why the number is being confirmed.
enum PhoneAuthKind {
  /// Into an account that already has this number.
  signIn,

  /// A new account, with a name, made by confirming the number.
  signUp,

  /// Adding a number to (or changing it on) the account already signed in,
  /// so that signing in by phone later reaches this same account.
  link,
}

/// Phone sign-in, sign-up and linking: a number, then the code sent to it.
///
/// The code is made and checked by Supabase and delivered by Twilio, both
/// configured in the Supabase dashboard; nothing here holds a provider's
/// credentials. Each code is billed, so a resend waits a minute, and a number
/// of the wrong shape is refused before anything is sent.
class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key, required this.kind, this.next});

  final PhoneAuthKind kind;

  /// Where to go once signed in, as on the other auth pages.
  final String? next;

  /// Seconds before another code can be asked for.
  static const resendAfter = 60;

  /// Supabase's default code length (Authentication → Providers → Phone).
  static const codeLength = 6;

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _code = TextEditingController();

  /// Signing in can turn into creating an account with the same number.
  late PhoneAuthKind _kind = widget.kind;
  String _country = 'jo';

  /// The number the code went to; while set, the page asks for the code.
  String? _sentTo;
  String? _message;
  bool _ok = false;

  /// Signing in found no account with this number: offer to create one.
  bool _noAccount = false;
  int _resendIn = 0;
  Timer? _tick;
  bool _verifying = false;

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in [_name, _number, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  void _startResendWait() {
    _tick?.cancel();
    setState(() => _resendIn = PhoneAuthScreen.resendAfter);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _send({bool again = false}) async {
    final l = context.l10n;
    final lang = context.lang;
    final fallback = context.failureMessage;
    setState(() {
      _message = null;
      _noAccount = false;
    });
    if (!again && !_form.currentState!.validate()) return;
    final phone = again ? _sentTo! : Phone.toE164(_number.text, _country)!;
    final auth = ref.read(authServiceProvider);
    try {
      switch (_kind) {
        case PhoneAuthKind.signIn:
          await auth.sendPhoneCode(phone);
        case PhoneAuthKind.signUp:
          await auth.sendPhoneCode(
            phone,
            create: true,
            // As email sign-up: the name and language the profile starts
            // with, and the guided tour's state for the new account.
            data: {'full_name': _name.text.trim(), 'locale': lang, ...ref.read(tourStoreProvider).signUpData()},
          );
        case PhoneAuthKind.link:
          await auth.startPhoneLink(phone);
      }
      if (!mounted) return;
      setState(() {
        _sentTo = phone;
        _ok = again;
        _message = again ? l.authCodeResent : null;
        if (again) _code.clear();
      });
      _startResendWait();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _noAccount = _kind == PhoneAuthKind.signIn && isNoPhoneAccount(e);
        _message = phoneAuthErrorMessage(l, e, fallback);
      });
    }
  }

  Future<void> _verify() async {
    final sentTo = _sentTo;
    if (_verifying || sentTo == null) return;
    final l = context.l10n;
    final fallback = context.failureMessage;
    final code = WesternDigitsFormatter.fold(_code.text);
    if (code.length != PhoneAuthScreen.codeLength) {
      setState(() {
        _ok = false;
        _message = l.authCodeIncomplete;
      });
      return;
    }
    _verifying = true;
    setState(() => _message = null);
    final auth = ref.read(authServiceProvider);
    try {
      if (_kind == PhoneAuthKind.link) {
        await auth.confirmPhoneLink(sentTo, code);
        if (!mounted) return;
        showSuccess(context, l.authPhoneLinked);
        context.pop();
        return;
      }
      final user = await auth.verifyPhoneCode(sentTo, code);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      final name = _name.text.trim();
      if (_kind == PhoneAuthKind.signUp && _isNew(user)) {
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
      // The number already had an account: confirming it signed them in.
      showSuccess(context, l.authWelcomeBack);
      leaveAuth(context, widget.next);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _message = phoneAuthErrorMessage(l, e, fallback);
        });
      }
    } finally {
      _verifying = false;
    }
  }

  /// Made by this sign-up rather than found: created within the time a code
  /// stays valid.
  static bool _isNew(User? user) {
    final created = DateTime.tryParse(user?.createdAt ?? '');
    return created != null && DateTime.now().toUtc().difference(created.toUtc()) < const Duration(minutes: 30);
  }

  void _changeNumber() {
    _tick?.cancel();
    setState(() {
      _sentTo = null;
      _resendIn = 0;
      _message = null;
      _code.clear();
    });
  }

  void _createInstead() => setState(() {
    _kind = PhoneAuthKind.signUp;
    _noAccount = false;
    _message = null;
  });

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return sentTo == null ? _numberStep(context) : _codeStep(context, sentTo);
  }

  Widget _numberStep(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final hasPhone = (ref.watch(currentUserProvider)?.phone ?? '').isNotEmpty;
    final (title, body) = switch (_kind) {
      PhoneAuthKind.signIn => (l.authPhoneTitle, l.authPhoneBody),
      PhoneAuthKind.signUp => (l.authPhoneSignUpTitle, l.authPhoneSignUpBody),
      PhoneAuthKind.link => (hasPhone ? l.authPhoneChangeTitle : l.authPhoneLinkTitle, l.authPhoneLinkBody),
    };
    final note = switch (_kind) {
      PhoneAuthKind.signIn => l.authPhoneEmailNote,
      PhoneAuthKind.signUp => l.authPhoneSignUpNote,
      PhoneAuthKind.link => null,
    };
    return AuthScaffold(
      title: title,
      body: body,
      children: [
        if (_message != null) AuthMessage(text: _message!, ok: _ok),
        if (_noAccount) ...[
          BusyButton(
            label: l.authPhoneCreateInstead,
            style: BusyButtonStyle.tonal,
            onPressed: () async => _createInstead(),
          ),
          const SizedBox(height: Space.lg),
        ],
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              children: [
                if (_kind == PhoneAuthKind.signUp) ...[
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
                ],
                PhoneNumberField(
                  controller: _number,
                  country: _country,
                  autofocus: _kind != PhoneAuthKind.signUp,
                  onCountry: (id) => setState(() {
                    _country = id;
                    _message = null;
                  }),
                  onSubmitted: (_) => _send(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        BusyButton(label: l.authSendCode, busyLabel: l.authSending, onPressed: _send),
        if (_kind == PhoneAuthKind.signUp) ...[const SizedBox(height: Space.md), const AuthAgreement()],
        if (note != null) ...[
          const SizedBox(height: Space.lg),
          Text(note, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
        ],
        if (_kind != PhoneAuthKind.link) ...[
          const SizedBox(height: Space.lg),
          Center(
            child: TextButton(
              // Back to the email form this page was opened from.
              onPressed: () {
                final page = _kind == PhoneAuthKind.signUp ? Routes.signUp : Routes.signIn;
                context.pushReplacement(widget.next == null ? page : Routes.withNext(page, widget.next!));
              },
              child: Text(l.authUseEmail, textAlign: TextAlign.center),
            ),
          ),
        ],
      ],
    );
  }

  Widget _codeStep(BuildContext context, String sentTo) {
    final l = context.l10n;
    final c = context.colors;
    final shown = Phone.display(sentTo);
    final whatsapp = ref.watch(authServiceProvider).channel == OtpChannel.whatsapp;
    final body = whatsapp ? l.authCodeBodyWhatsapp : l.authCodeBodySms;
    final verify = switch (_kind) {
      PhoneAuthKind.signIn => l.authVerifySignIn,
      PhoneAuthKind.signUp => l.authVerifySignUp,
      PhoneAuthKind.link => l.authVerifyLink,
    };
    return AuthScaffold(
      title: l.authCodeTitle,
      body: body,
      children: [
        if (_message != null) AuthMessage(text: _message!, ok: _ok),
        // The number the code went to, so nobody has to remember it, and the
        // way back if it was mistyped.
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${l.authCodeSentTo} '),
                    TextSpan(
                      text: '\u2066$shown\u2069',
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
              ),
            ),
            TextButton(onPressed: _changeNumber, child: Text(l.authChangeNumber)),
          ],
        ),
        const SizedBox(height: Space.sm),
        OtpCodeField(controller: _code, length: PhoneAuthScreen.codeLength, onCompleted: _verify),
        const SizedBox(height: Space.lg),
        BusyButton(label: verify, busyLabel: l.authVerifying, onPressed: _verify),
        const SizedBox(height: Space.sm),
        Center(
          child: TextButton(
            onPressed: _resendIn > 0 ? null : () => _send(again: true),
            child: Text(_resendIn > 0 ? l.authResendIn(_resendIn) : l.authResend, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
