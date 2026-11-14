// The Services screens: the categories and their search, the request form's
// checks and its place picker, and My service requests, in both languages.
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

const _cats = [
  ServiceCategory(
    id: 'plumbing',
    en: 'Plumbing',
    ar: 'السباكة',
    examplesEn: 'Water leaks, blocked drains',
    examplesAr: 'تسريب المياه',
    icon: 'plumbing',
    custom: false,
  ),
  ServiceCategory(
    id: 'ac',
    en: 'Air conditioning',
    ar: 'التكييف',
    examplesEn: 'AC repair, servicing',
    examplesAr: 'إصلاح المكيفات',
    icon: 'ac',
    custom: false,
  ),
  ServiceCategory(
    id: 'cleaning',
    en: 'Cleaning',
    ar: 'التنظيف',
    examplesEn: 'Home and deep cleaning',
    examplesAr: 'تنظيف المنازل',
    icon: 'cleaning',
    custom: false,
  ),
  ServiceCategory(
    id: 'custom',
    en: 'Custom service',
    ar: 'خدمة أخرى',
    examplesEn: 'Something not listed',
    examplesAr: 'خدمة غير موجودة',
    icon: 'custom',
    custom: true,
  ),
];

final _request = ServiceRequest.fromRow({
  'id': 'r1',
  'ref': 'SR-000042',
  'status': 'accepted',
  'category_id': 'plumbing',
  'category_en': 'Plumbing',
  'category_ar': 'السباكة',
  'icon': 'plumbing',
  'description': 'The kitchen sink is leaking.',
  'governorate_id': 'amman',
  'city_id': 'amman',
  'neighborhood_id': 'abdoun',
  'address': 'Cairo St 9',
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
});

Future<List<Override>> _deps({List<ServiceRequest> mine = const []}) async => [
  ...await TestDeps().overrides(user: fakeUser()),
  serviceCategoriesProvider.overrideWith((ref) async => _cats),
  myServiceRequestsProvider.overrideWith((ref) async => mine),
  placesProvider.overrideWith((ref) async => PlacesState(Places.bundled, inDatabase: true)),
];

void main() {
  testWidgets('the categories, a search over them in either language, and a way out when nothing matches', (
    tester,
  ) async {
    await pumpScreen(tester, const ServicesScreen(), overrides: await _deps());
    await tester.pumpAndSettle();
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Request a service'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'clean');
    await tester.pumpAndSettle();
    expect(find.text('Cleaning'), findsOneWidget);
    expect(find.text('Plumbing'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No service matches “zzzz”.'), findsOneWidget);
    expect(find.text('Describe a custom service'), findsOneWidget);
  });

  testWidgets('in Arabic, an Arabic search finds the category without its article', (tester) async {
    await pumpScreen(tester, const ServicesScreen(), overrides: await _deps(), lang: 'ar');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'تكييف');
    await tester.pumpAndSettle();
    expect(find.text('التكييف'), findsOneWidget);
    expect(find.text('السباكة'), findsNothing);
  });

  testWidgets('sending with nothing filled in says what is missing, next to each field', (tester) async {
    await pumpScreen(tester, const ServiceRequestScreen(categoryId: 'plumbing'), overrides: await _deps());
    await tester.pumpAndSettle();
    final form = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    // Jump, not drag: a drag over the pin map moves the map, not the form.
    final pos = tester.state<ScrollableState>(form).position;
    for (var k = 0; k < 6 && find.text('Send request').evaluate().isEmpty; k++) {
      pos.jumpTo(pos.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(find.text('Some details need a look. They are marked below.'), findsOneWidget);
    // Back to the top without dragging: a drag over the pin map moves the map, not the form.
    tester.state<ScrollableState>(form).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Describe the problem in at least 10 characters.'), findsOneWidget);
    expect(find.text('Choose the city or town.'), findsOneWidget);
  });

  testWidgets('the place picker finds a neighbourhood by search and fills in its city', (tester) async {
    await pumpScreen(tester, const ServiceRequestScreen(categoryId: 'plumbing'), overrides: await _deps());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Area *'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Area *'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'City, town or neighbourhood'), 'abdoon');
    await tester.pumpAndSettle();
    expect(find.text('Abdoun'), findsOneWidget);
    await tester.tap(find.text('Abdoun'));
    await tester.pumpAndSettle();
    expect(find.text('Abdoun · Amman'), findsOneWidget);
  });

  testWidgets("my requests: where each stands, the team's note, and cancelling while it still can be", (tester) async {
    await pumpScreen(tester, const MyServiceRequestsScreen(), overrides: await _deps(mine: [_request]));
    await tester.pumpAndSettle();
    expect(find.text('SR-000042'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('A plumber will call you before 11.'), findsOneWidget);
    expect(find.text('Cancel request'), findsOneWidget);
    expect(find.textContaining('Abdoun · Amman'), findsOneWidget);
  });
}
