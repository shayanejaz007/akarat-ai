// Writes the pins Google's map shows (drawn as images) to
// test/visual/goldens/pins/, with the app's real fonts, for review:
//
//   flutter test test/visual --update-goldens --run-skipped
//
// Skipped by a normal `flutter test` run (dart_test.yaml).
@Tags(['visual'])
library;

import 'dart:io';

import 'package:akarat/core/widgets/map_pin_images.dart';
import 'package:akarat/core/widgets/maps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:material_ui/material_ui.dart';

import 'render.dart';

void main() {
  setUpAll(loadRealFonts);

  testWidgets('map pins as images', (tester) async {
    await tester.runAsync(() async {
      for (final (lang, style) in [
        ('en', const TextStyle(fontFamily: 'Inter', fontFamilyFallback: ['IBMPlexSansArabic'])),
        ('ar', const TextStyle(fontFamily: 'IBMPlexSansArabic')),
      ]) {
        final images = MapPinImages(devicePixelRatio: 3, textStyle: style, textScale: 1);
        final pins = {
          'sale': await images.price(
            lang == 'ar' ? '١٥٠ ألف' : '150K',
            background: MapPins.sale,
            foreground: MapPins.saleText,
            selected: false,
          ),
          'rent': await images.price('2.4K', background: MapPins.rent, foreground: MapPins.rentText, selected: false),
          'chosen': await images.price('1.25M', background: MapPins.sale, foreground: MapPins.saleText, selected: true),
          'sold': await images.price('98K', background: MapPins.closed, foreground: Colors.white, selected: false),
          'cluster': await images.cluster(12, background: MapPins.sale, foreground: MapPins.saleText),
          'mixed': await images.cluster(5, background: MapPins.sale, foreground: MapPins.saleText, ring: MapPins.rent),
          'place': await images.place(MapPins.sale),
        };
        Directory('test/visual/goldens/pins').createSync(recursive: true);
        for (final MapEntry(:key, :value) in pins.entries) {
          final bytes = (value.icon as BytesMapBitmap).byteData;
          File('test/visual/goldens/pins/${lang}_$key.png').writeAsBytesSync(bytes);
        }
      }
    });
  });
}
