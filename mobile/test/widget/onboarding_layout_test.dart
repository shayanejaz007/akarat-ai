import 'package:akarat/features/onboarding/onboarding_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/harness.dart';
import '../visual/render.dart' show Device, loadRealFonts;

/// The introduction at the largest text size the app allows, in the app's
/// own fonts (the test font is far wider than Inter, so it would measure
/// overflows no phone shows).
void main() {
  setUpAll(loadRealFonts);

  for (final device in [Device.compact, Device.phone]) {
    for (final lang in ['en', 'ar']) {
      testWidgets('fits ${device.name} at text ×1.6 [$lang]', (tester) async {
        await pumpScreen(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: const OnboardingScreen(),
            ),
          ),
          overrides: await TestDeps().overrides(prefs: {'akarat.onboarded': false}),
          lang: lang,
          size: device.size,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
        expect(find.text('English'), findsOneWidget);
        expect(find.text('العربية'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('English')).dy,
          lessThan(80),
          reason: 'the header sits at the top of the photo',
        );
      });
    }
  }
}
