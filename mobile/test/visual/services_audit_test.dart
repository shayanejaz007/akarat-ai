// Visual audit of Services: the categories, the request form and My service
// requests, in both languages and both themes.
//
//   flutter test test/visual/services_audit_test.dart --tags visual --update-goldens --run-skipped
//
// Writes test/visual/goldens/services/*.png for review. Tagged `visual`, so
// the normal `flutter test` run skips it (dart_test.yaml).
@Tags(['visual'])
library;

import 'package:akarat/features/services/my_service_requests_screen.dart';
import 'package:akarat/features/services/service_request_screen.dart';
import 'package:akarat/features/services/services_models.dart';
import 'package:akarat/features/services/services_screen.dart';
import 'package:akarat/features/services/services_ui.dart';
import 'package:akarat/shared/reference/places.dart';
import 'package:akarat/shared/reference/places_provider.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/harness.dart';
import 'render.dart';

const _cats = [
  ServiceCategory(
    id: 'plumbing',
    en: 'Plumbing',
    ar: 'السباكة',
    examplesEn: 'Water leaks, blocked drains, pipe repairs',
    examplesAr: 'تسريب المياه، انسداد المصارف، إصلاح الأنابيب',
    icon: 'plumbing',
    custom: false,
  ),
  ServiceCategory(
    id: 'bathroom',
    en: 'Bathroom repairs',
    ar: 'إصلاحات الحمّامات',
    examplesEn: 'Toilets, showers, faucets',
    examplesAr: 'المراحيض، الدش، الحنفيات',
    icon: 'bathroom',
    custom: false,
  ),
  ServiceCategory(
    id: 'electrical',
    en: 'Electrical',
    ar: 'الكهرباء',
    examplesEn: 'Wiring, switches, lights, sockets',
    examplesAr: 'التمديدات، المفاتيح، الإنارة، المقابس',
    icon: 'electrical',
    custom: false,
  ),
  ServiceCategory(
    id: 'ac',
    en: 'Air conditioning',
    ar: 'التكييف',
    examplesEn: 'AC repair, servicing, installation',
    examplesAr: 'إصلاح المكيفات وصيانتها وتركيبها',
    icon: 'ac',
    custom: false,
  ),
  ServiceCategory(
    id: 'cleaning',
    en: 'Cleaning',
    ar: 'التنظيف',
    examplesEn: 'Home, apartment and deep cleaning',
    examplesAr: 'تنظيف المنازل والشقق',
    icon: 'cleaning',
    custom: false,
  ),
  ServiceCategory(
    id: 'custom',
    en: 'Custom service',
    ar: 'خدمة أخرى',
    examplesEn: 'Something not listed here',
    examplesAr: 'خدمة غير موجودة في القائمة',
    icon: 'custom',
    custom: true,
  ),
];

final _mine = [
  ServiceRequest.fromRow({
    'id': 'r1',
    'ref': 'SR-000042',
    'status': 'accepted',
    'category_id': 'plumbing',
    'category_en': 'Plumbing',
    'category_ar': 'السباكة',
    'icon': 'plumbing',
    'description': 'The kitchen sink is leaking under the cabinet.',
    'governorate_id': 'amman',
    'city_id': 'amman',
    'neighborhood_id': 'abdoun',
    'address': 'Cairo St, building 9',
    'preferred_date': '2026-11-15',
    'preferred_window': 'morning',
    'urgency': 'urgent',
    'photos': <String>[],
    'created_at': '2026-11-12T08:10:00Z',
    'cancellable': true,
    'events': [
      {'at': '2026-11-12T08:10:00Z', 'kind': 'created', 'status': 'pending', 'by': 'customer'},
      {
        'at': '2026-11-12T10:00:00Z',
        'kind': 'status',
        'status': 'accepted',
        'note': 'A plumber will call you before 11.',
        'by': 'admin',
      },
    ],
  }),
  ServiceRequest.fromRow({
    'id': 'r2',
    'ref': 'SR-000017',
    'status': 'completed',
    'category_id': 'ac',
    'category_en': 'Air conditioning',
    'category_ar': 'التكييف',
    'icon': 'ac',
    'description': 'Yearly service for two split units.',
    'governorate_id': 'irbid',
    'city_id': 'irbid',
    'address': 'University St',
    'preferred_date': '2026-10-02',
    'preferred_window': 'any',
    'urgency': 'normal',
    'photos': <String>[],
    'created_at': '2026-09-28T12:00:00Z',
    'cancellable': false,
    'events': <Object>[],
  }),
];

Future<List<Override>> _deps() async => [
  ...await TestDeps().overrides(user: fakeUser()),
  serviceCategoriesProvider.overrideWith((ref) async => _cats),
  myServiceRequestsProvider.overrideWith((ref) async => _mine),
  placesProvider.overrideWith((ref) async => PlacesState(Places.bundled, inDatabase: true)),
];

void main() {
  setUpAll(loadRealFonts);

  for (final lang in ['en', 'ar']) {
    testWidgets('services $lang', (t) async {
      await render(
        t,
        'services_$lang',
        const ServicesScreen(),
        overrides: await _deps(),
        lang: lang,
        folder: 'services',
      );
    });
    testWidgets('request form $lang', (t) async {
      await render(
        t,
        'request_$lang',
        const ServiceRequestScreen(categoryId: 'plumbing'),
        overrides: await _deps(),
        lang: lang,
        folder: 'services',
      );
    });
    testWidgets('my requests $lang', (t) async {
      await render(
        t,
        'mine_$lang',
        const MyServiceRequestsScreen(),
        overrides: await _deps(),
        lang: lang,
        folder: 'services',
      );
    });
  }
  testWidgets('services dark', (t) async {
    await render(
      t,
      'services_dark',
      const ServicesScreen(),
      overrides: await _deps(),
      brightness: Brightness.dark,
      folder: 'services',
    );
  });
  testWidgets('request form, errors, large text ar', (t) async {
    await render(
      t,
      'request_errors_ar',
      const ServiceRequestScreen(categoryId: 'plumbing'),
      overrides: await _deps(),
      lang: 'ar',
      textScale: 1.4,
      folder: 'services',
      interact: (t) async {
        final form = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
        // Jump, not drag: a drag over the pin map moves the map.
        final pos = t.state<ScrollableState>(form).position;
        for (var k = 0; k < 6 && find.text('أرسل الطلب').evaluate().isEmpty; k++) {
          pos.jumpTo(pos.maxScrollExtent);
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.tap(find.text('أرسل الطلب'));
        await t.pump(const Duration(milliseconds: 300));
        t.state<ScrollableState>(form).position.jumpTo(0);
        await t.pump(const Duration(milliseconds: 300));
      },
    );
  });
}
