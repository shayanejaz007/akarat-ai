import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/brand.dart';

/// Signed in: close the auth page, back to where the reader was (the tab bar's
/// Log in, a listing, a saved search), or on to [next] when the page was the
/// destination itself. The router's redirect only re-routes pages it went to,
/// not ones that were pushed, so the page has to leave on its own.
void leaveAuth(BuildContext context, String? next) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(next ?? Routes.profile);
  }
}

/// Shared frame for the auth screens: brand, a title, a line of context and
/// the form, centred and width-capped so tablets do not stretch it.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.body, required this.children});

  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(leading: CloseButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home))),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, Space.xxl),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                const Align(alignment: AlignmentDirectional.centerStart, child: BrandMark(size: 48)),
                const SizedBox(height: Space.lg),
                Semantics(header: true, child: Text(title, style: context.text.headlineMedium)),
                const SizedBox(height: Space.xs),
                Text(body, style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
                const SizedBox(height: Space.xl),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "By creating an account, you agree to the Terms of use and Privacy
/// policy." — one sentence, the two documents as links within it.
class AuthAgreement extends StatefulWidget {
  const AuthAgreement({super.key});

  @override
  State<AuthAgreement> createState() => _AuthAgreementState();
}

class _AuthAgreementState extends State<AuthAgreement> {
  late final _terms = TapGestureRecognizer()..onTap = () => context.push(Routes.legal('terms'));
  late final _privacy = TapGestureRecognizer()..onTap = () => context.push(Routes.legal('privacy'));

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    // Markers stand in for the links so translators can place them freely.
    const t = '\u0001';
    const p = '\u0002';
    final sentence = l.authAgreement(t, p);
    final link = context.text.bodySmall?.copyWith(color: c.forest, fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    for (final part in sentence.split(RegExp('(?=[$t$p])|(?<=[$t$p])'))) {
      if (part == t) {
        spans.add(TextSpan(text: l.settingsTerms, style: link, recognizer: _terms));
      } else if (part == p) {
        spans.add(TextSpan(text: l.settingsPrivacy, style: link, recognizer: _privacy));
      } else if (part.isNotEmpty) {
        spans.add(TextSpan(text: part));
      }
    }
    return Text.rich(
      TextSpan(style: context.text.bodySmall, children: spans),
      textAlign: TextAlign.center,
    );
  }
}

/// Facebook's "f", in Facebook's blue, for its sign-in button.
class FacebookMark extends StatelessWidget {
  const FacebookMark({super.key});

  static const blue = Color(0xFF1877F2);

  @override
  Widget build(BuildContext context) => const Icon(Icons.facebook, color: blue, size: 22);
}

/// "— or —" between the email form and the other ways in.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Text(context.l10n.authOr, style: context.text.bodySmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class AuthMessage extends StatelessWidget {
  const AuthMessage({super.key, required this.text, this.ok = false});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = ok ? c.success : c.danger;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.md),
        padding: const EdgeInsets.all(Space.sm),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.08), c.surface),
          borderRadius: Radii.field,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.mark_email_read_outlined : Icons.error_outline_rounded, color: color, size: 20),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(text, style: context.text.bodySmall?.copyWith(color: c.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.newPassword = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool newPassword;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _hidden ? l.authShowPassword : l.authHidePassword,
          onPressed: () => setState(() => _hidden = !_hidden),
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}

final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
