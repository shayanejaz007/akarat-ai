// On-device journeys against a real backend. READ-ONLY: nothing here writes
// to the database, so it is safe against production.
//
//   flutter test integration_test/marketplace_test.dart \
//     --dart-define-from-file=env/staging.json -d <device-id>
//
// See TESTING.md for what each journey checks and how to run on CI.

import 'dart:async';

import 'package:akarat/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [Duration max = const Duration(seconds: 15)]) async {
  final end = DateTime.now().add(max);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (!tester.binding.hasScheduledFrame) break;
  }
}

Future<void> launch(WidgetTester tester, {String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues({
    'akarat.onboarded': true,
    'akarat.lang': lang,
    // Tours stay out of the way of these journeys.
    'akarat.tour.explore': true,
    'akarat.tour.map': true,
    'akarat.tour.listing': true,
    'akarat.tour.property': true,
  });
  unawaited(app.main());
  await settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home loads real listings or says honestly that there are none', (tester) async {
    await launch(tester);
    expect(find.text('Find your place in Jordan'), findsOneWidget);
    final hasListings =
        find.text('Recently listed').evaluate().isNotEmpty &&
        find.text('The marketplace is opening').evaluate().isEmpty;
    expect(hasListings || find.text('The marketplace is opening').evaluate().isNotEmpty, isTrue);
  });

  testWidgets('explore: filter, open a listing, see its details', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Explore'));
    await settle(tester);
    expect(find.textContaining('on the map'), findsWidgets, reason: 'Explore opens on the map');
    await tester.tap(find.text('List'));
    await settle(tester);
    expect(find.textContaining('propert'), findsWidgets, reason: 'the result count is shown');
    await tester.tap(find.text('Rent'));
    await settle(tester);
    final cards = find.textContaining('JOD/mo');
    if (cards.evaluate().isEmpty) return; // No rentals on this backend: the empty state was shown instead.
    await tester.tap(cards.first);
    await settle(tester);
    expect(find.text('Property details'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
  });

  testWidgets('AI search: English and Jordanian Arabic both parse and search', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('AI Search'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Find me a 3-bedroom apartment in Abdoun under 150,000 JOD');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, const Duration(seconds: 20));
    expect(find.bySemanticsLabel('Remove Abdoun'), findsOneWidget, reason: 'the brief is editable chips');
    expect(find.text('Abdoun'), findsWidgets);
    expect(find.text('3+ bedrooms'), findsWidgets);
    expect(find.text('On Akarat.ai'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'بدي شقة بعمان غرفتين وبسعر أقل من ٨٠ ألف دينار');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, const Duration(seconds: 20));
    expect(find.text('2+ bedrooms'), findsWidgets);
    expect(find.textContaining('80,000'), findsWidgets);
  });

  testWidgets('switching to Arabic flips the layout', (tester) async {
    await launch(tester);
    // Signed out, Profile is reached from Home's account button.
    await tester.tap(find.bySemanticsLabel('Profile').first);
    await settle(tester);
    await tester.tap(find.text('العربية'));
    await settle(tester);
    expect(find.text('حسابي'), findsWidgets);
    expect(Directionality.of(tester.element(find.text('حسابي').first)), TextDirection.rtl);
  });
}
