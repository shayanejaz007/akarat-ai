// Frame timing on a real device, READ-ONLY (browsing only).
//
//   flutter drive --profile -d <device> \
//     --driver test_driver/perf_driver.dart --target integration_test/perf_test.dart
//
// Writes build/perf_summary.json: frame build and raster times while
// scrolling Home, swiping the Explore map cards and scrolling the list.

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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolling stays smooth', (tester) async {
    SharedPreferences.setMockInitialValues({
      'akarat.onboarded': true,
      'akarat.lang': 'en',
      'akarat.tour.explore': true,
      'akarat.tour.map': true,
      'akarat.tour.listing': true,
      'akarat.tour.property': true,
    });
    unawaited(app.main());
    await settle(tester);
    // Let the first listings and images arrive.
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);

    final home = find.byType(Scrollable).first;
    await binding.watchPerformance(() async {
      for (var i = 0; i < 3; i++) {
        await tester.fling(home, const Offset(0, -500), 1500);
        await settle(tester, const Duration(seconds: 3));
      }
      for (var i = 0; i < 3; i++) {
        await tester.fling(home, const Offset(0, 500), 1500);
        await settle(tester, const Duration(seconds: 3));
      }
    }, reportKey: 'home_scroll');

    await tester.tap(find.bySemanticsLabel('Explore'));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    final cards = find.byType(PageView).last;
    await binding.watchPerformance(() async {
      for (var i = 0; i < 4; i++) {
        await tester.fling(cards, const Offset(-300, 0), 1200);
        await settle(tester, const Duration(seconds: 3));
      }
    }, reportKey: 'map_cards');

    await tester.tap(find.text('List'));
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    final list = find.byType(Scrollable).first;
    await binding.watchPerformance(() async {
      for (var i = 0; i < 4; i++) {
        await tester.fling(list, const Offset(0, -600), 1800);
        await settle(tester, const Duration(seconds: 3));
      }
    }, reportKey: 'explore_list');
  });
}
