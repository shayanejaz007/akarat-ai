import 'package:akarat/core/widgets/map_pin_images.dart';
import 'package:akarat/core/widgets/maps.dart';
import 'package:akarat/features/explore/explore_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_google_maps.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

final _rows = [
  listing(),
  listing(
    id: '44444444-4444-4444-8444-444444444444',
    deal: 'rent',
    type: 'villa',
    hood: 'dabouq',
    price: 2400,
    titleEn: 'Garden villa with a pool',
    lat: 31.99,
    lng: 35.83,
    precision: 'exact',
  ),
  // No location: a card, never a pin.
  listing(id: '77777777-7777-4777-8777-777777777777', titleEn: 'Flat with no pin', lat: null, lng: null),
];

/// Pins are drawn as images off the test clock: let that real work finish,
/// then rebuild.
Future<void> _drawPins(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('Google maps (with a key)', () {
    late FakeGoogleMapsPlatform google;

    setUp(() {
      google = FakeGoogleMapsPlatform();
      GoogleMapsFlutterPlatform.instance = google;
    });
    tearDown(() => google.close());

    Future<List<Override>> overrides() =>
        TestDeps(listings: FakeListingsRepository(rows: _rows)).overrides(googleMaps: true);

    testWidgets('Explore draws Google\'s map: nearby pins merge, part on zooming in, and a tap selects one', (
      tester,
    ) async {
      await pumpScreen(tester, const ExploreScreen(), overrides: await overrides());
      await tester.pump(const Duration(milliseconds: 300));
      await _drawPins(tester);
      expect(find.byKey(const ValueKey('fake-google-map')), findsOneWidget);
      expect(find.text('© OpenStreetMap'), findsNothing, reason: "Google's map, not the key-free one");

      // At the country view, the two Amman listings are one bubble.
      expect(google.markers.keys.single.value, startsWith('cluster:'));
      expect(google.circles, hasLength(1), reason: 'the approximate location is a shaded circle');

      // Zoomed in, each shows its own price pin; the one without a location
      // is not on the map.
      google.zoomTo(15);
      await tester.pump();
      await _drawPins(tester);
      expect(google.markers.keys.map((m) => m.value), unorderedEquals([_rows[0].id, _rows[1].id]));

      google.tapMarker(_rows[1].id);
      await tester.pump();
      await _drawPins(tester);
      expect(google.markers[MarkerId(_rows[1].id)]!.zIndexInt, 2, reason: 'the chosen pin is drawn on top');
      expect(google.markers[MarkerId(_rows[0].id)]!.zIndexInt, 1);
    });

    testWidgets('the satellite switch changes every map and is remembered', (tester) async {
      await pumpScreen(tester, const ExploreScreen(), overrides: await overrides());
      await tester.pump(const Duration(milliseconds: 300));
      expect(google.configuration.mapType, MapType.normal);

      await tester.tap(find.byTooltip('Switch to satellite view'));
      await tester.pump();
      expect(google.configuration.mapType, MapType.hybrid, reason: 'satellite imagery with street names');
      expect(find.byTooltip('Switch to map view'), findsOneWidget, reason: 'and back again');
      final prefs = ProviderScope.containerOf(tester.element(find.byType(ExploreScreen))).read(preferencesProvider);
      expect(prefs.mapLayer, 'satellite');
    });

    test('pins are drawn as images in the same shapes, once each', () async {
      final images = MapPinImages(devicePixelRatio: 2, textStyle: const TextStyle(fontSize: 13), textScale: 1);
      final short = await images.price('95K', background: MapPins.sale, foreground: Colors.white, selected: false);
      final long = await images.price('1.25M', background: MapPins.sale, foreground: Colors.white, selected: false);
      final chosen = await images.price('95K', background: MapPins.sale, foreground: Colors.white, selected: true);
      expect(long.size.width, greaterThan(short.size.width), reason: 'the label sizes the pin');
      expect(chosen.size.height, greaterThan(short.size.height), reason: 'the chosen pin is larger');
      expect(short.anchor.dx, 0.5);
      expect(short.anchor.dy, inExclusiveRange(0.8, 1.0), reason: "the pointer's tip, above the shadow margin");
      final bubble = await images.cluster(12, background: MapPins.sale, foreground: Colors.white);
      expect(bubble.anchor, const Offset(0.5, 0.5));
      expect(
        identical(
          images.price('95K', background: MapPins.sale, foreground: Colors.white, selected: false),
          images.price('95K', background: MapPins.sale, foreground: Colors.white, selected: false),
        ),
        isTrue,
        reason: 'drawn once, then reused',
      );
    });
  });

  group('Without a key', () {
    testWidgets('the key-free map draws, with no satellite switch', (tester) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: await TestDeps(listings: FakeListingsRepository(rows: _rows)).overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake-google-map')), findsNothing);
      expect(find.byTooltip('Switch to satellite view'), findsNothing);
      expect(find.text('2 on the map'), findsOneWidget);
    });
  });

  test('nearby pins group at a distance and part close up', () {
    final pins = _rows.where((l) => l.hasCoordinates).toList();
    expect(groupPins(pins, 7), hasLength(1));
    expect(groupPins(pins, 15), hasLength(2));
  });

  group('Street View', () {
    test("opens Google's Street View at the point", () {
      final uri = streetViewUri(31.99, 35.83);
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/@');
      expect(uri.queryParameters, {'api': '1', 'map_action': 'pano', 'viewpoint': '31.99,35.83'});
    });

    for (final (precision, shown) in [('exact', true), ('approximate', false)]) {
      testWidgets('offered at an $precision location: $shown', (tester) async {
        final row = listing(precision: precision);
        await pumpScreen(
          tester,
          PropertyDetailsScreen(id: row.id, initial: row),
          overrides: await TestDeps(listings: FakeListingsRepository(rows: [row])).overrides(),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Open in Maps'), 400, scrollable: find.byType(Scrollable).first);
        expect(find.text('Street View'), shown ? findsOneWidget : findsNothing);
      });
    }
  });
}
