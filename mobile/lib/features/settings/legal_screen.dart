import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';

/// The website's privacy policy and terms of use, word for word, in both
/// languages. Legal text is not rewritten for the app.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});
  final String doc;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final privacy = doc != 'terms';
    final sections = privacy
        ? [
            (l.privacyH1, l.privacyP1),
            (l.privacyH2, l.privacyP2),
            (l.privacyH3, l.privacyP3),
            (l.privacyH4, l.privacyP4),
          ]
        : [(l.termsH1, l.termsP1), (l.termsH2, l.termsP2), (l.termsH3, l.termsP3), (l.termsH4, l.termsP4)];
    return Scaffold(
      appBar: AppBar(title: Text(privacy ? l.settingsPrivacy : l.settingsTerms)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xxl),
        children: [
          Text(l.legalUpdated, style: context.text.bodySmall),
          const SizedBox(height: Space.lg),
          for (final (h, p) in sections) ...[
            Semantics(header: true, child: Text(h, style: context.text.titleMedium)),
            const SizedBox(height: Space.xs),
            Text(p, style: context.text.bodyLarge),
            const SizedBox(height: Space.lg),
          ],
        ],
      ),
    );
  }
}
