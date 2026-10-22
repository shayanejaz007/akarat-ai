import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/utils/phone.dart';

/// A country and a number, as one field: the country's flag and dialling
/// code on a button that opens the list, then the number. The two sit left to
/// right in both languages, as a phone number is written; the label, hint and
/// any error follow the reader's language.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountry,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String country;
  final ValueChanged<String> onCountry;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = Phone.country(country);
    final digits = c.minLength == c.maxLength ? '${c.minLength}' : '${c.minLength}–${c.maxLength}';
    return Row(
      // The order only: the field's own words keep the reader's direction.
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountryButton(country: c, onTap: () => _pick(context)),
        const SizedBox(width: Space.xs),
        Expanded(
          child: TextFormField(
            controller: controller,
            autofocus: autofocus,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            // Spaces, dashes and Arabic numerals are folded away as typed;
            // fifteen digits is E.164's ceiling.
            inputFormatters: const [WesternDigitsFormatter(maxLength: 15)],
            onFieldSubmitted: onSubmitted,
            decoration: InputDecoration(
              labelText: l.fieldPhoneNumber,
              // The expected shape, visible before a number is refused.
              helperText: l.authPhoneHint(digits, c.dial),
              helperMaxLines: 3,
              errorMaxLines: 3,
            ),
            validator: (v) => Phone.toE164(v, country) == null ? l.authPhoneHint(digits, c.dial) : null,
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final lang = context.lang;
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _CountrySheet(selected: country, lang: lang),
    );
    if (picked != null && picked != country) onCountry(picked);
  }
}

class _CountryButton extends StatelessWidget {
  const _CountryButton({required this.country, required this.onTap});
  final PhoneCountry country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Semantics(
      button: true,
      label: l.authPhoneCountryA11y(country.name(context.lang), country.dial),
      excludeSemantics: true,
      child: Material(
        color: c.surfaceMuted,
        borderRadius: Radii.field,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.field,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Row(
                textDirection: TextDirection.ltr,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(country.flag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: Space.xxs),
                  Text('+${country.dial}', textDirection: TextDirection.ltr, style: context.text.bodyLarge),
                  Icon(Icons.arrow_drop_down_rounded, color: c.inkMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountrySheet extends StatelessWidget {
  const _CountrySheet({required this.selected, required this.lang});
  final String selected;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
          child: Text(l.fieldCountry, style: context.text.titleLarge),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: Space.lg),
            children: [
              for (final country in Phone.countries)
                ListTile(
                  leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(country.name(lang)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+${country.dial}',
                        textDirection: TextDirection.ltr,
                        style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                      ),
                      if (country.id == selected) ...[
                        const SizedBox(width: Space.xs),
                        Icon(Icons.check_rounded, color: c.emerald),
                      ],
                    ],
                  ),
                  selected: country.id == selected,
                  onTap: () => Navigator.pop(context, country.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The one-time code: digits only (Arabic numerals folded as typed), large
/// and spaced so it reads at a glance, and offered by the keyboard straight
/// from the message where the phone supports it. Calls [onCompleted] the
/// moment the last digit is in.
class OtpCodeField extends StatelessWidget {
  const OtpCodeField({super.key, required this.controller, required this.onCompleted, this.length = 6});

  final TextEditingController controller;
  final VoidCallback onCompleted;
  final int length;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [WesternDigitsFormatter(maxLength: length)],
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: context.text.headlineSmall?.copyWith(
        letterSpacing: 10,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(labelText: l.fieldCode, counterText: ''),
      onChanged: (v) {
        if (v.length == length) {
          unawaited(HapticFeedback.selectionClick());
          onCompleted();
        }
      },
      onSubmitted: (_) => onCompleted(),
    );
  }
}
