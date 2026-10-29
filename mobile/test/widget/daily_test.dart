import 'package:akarat/features/daily/bookings_screen.dart';
import 'package:akarat/features/daily/daily_screen.dart';
import 'package:akarat/features/dashboard/dashboard_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/shared/models/daily_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

const _renter = '44444444-4444-4444-8444-444444444444';
const _owner = '22222222-2222-4222-8222-222222222222';

BookingRequest _request({
  BookingStatus status = BookingStatus.pending,
  String? phone,
  String renter = _renter,
  String owner = _owner,
}) => BookingRequest(
  id: 'req-1',
  propertyId: dailyListing().id,
  ownerId: owner,
  renterId: renter,
  renterName: 'Rana',
  checkIn: DateTime(2099, 11, 10),
  checkOut: DateTime(2099, 11, 13),
  nights: 3,
  guests: 2,
  nightlyPrice: 60,
  totalPrice: 180,
  status: status,
  createdAt: DateTime(2026, 10, 29),
  ownerPhone: phone,
  titleEn: 'Sea-view chalet in Aqaba',
);

void main() {
  testWidgets('the Daily tab lists approved places, priced per night and marked verified', (tester) async {
    final daily = FakeDailyRepository(
      listings: [
        dailyListing(),
        dailyListing(id: '66666666-6666-4666-8666-666666666666', review: 'pending', titleEn: 'Waiting for review'),
      ],
    );
    await pumpScreen(tester, const DailyScreen(), overrides: await TestDeps(daily: daily).overrides());
    await tester.pumpAndSettle();
    expect(find.text('Sea-view chalet in Aqaba'), findsOneWidget);
    expect(find.text('Waiting for review'), findsNothing, reason: 'only approved places are public');
    expect(find.text('60 JOD/night'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('Sleeps 4'), findsOneWidget);
  });

  testWidgets('a daily listing offers dates, not a phone, and asks a guest to sign in', (tester) async {
    final l = dailyListing(owner: '99999999-9999-4999-8999-999999999999');
    final deps = TestDeps(
      listings: FakeListingsRepository(rows: [l]),
      daily: FakeDailyRepository(listings: [l]),
    );
    await pumpScreen(
      tester,
      PropertyDetailsScreen(id: l.id, initial: l),
      overrides: await deps.overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Check availability'), findsOneWidget);
    expect(find.text('Call'), findsNothing, reason: 'the number comes only with an approval');
    await tester.tap(find.text('Check availability'));
    await tester.pumpAndSettle();
    expect(find.text('Request to book'), findsOneWidget);
    expect(find.text('Sign in to request'), findsOneWidget);
  });

  testWidgets('once the owner approves, the guest sees the number and WhatsApp', (tester) async {
    final l = dailyListing(owner: '99999999-9999-4999-8999-999999999999');
    final daily = FakeDailyRepository(
      listings: [l],
      requests: [_request(status: BookingStatus.approved, phone: '0791234567', owner: l.ownerId)],
    );
    final deps = TestDeps(
      listings: FakeListingsRepository(rows: [l]),
      daily: daily,
    );
    await pumpScreen(
      tester,
      PropertyDetailsScreen(id: l.id, initial: l),
      overrides: await deps.overrides(user: fakeUser(id: _renter)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your request'), findsWidgets);
    expect(find.text('0791234567'), findsOneWidget);
    expect(find.text('Contact on WhatsApp'), findsOneWidget);
  });

  testWidgets('while the request waits, no number is shown', (tester) async {
    final l = dailyListing(owner: '99999999-9999-4999-8999-999999999999');
    final daily = FakeDailyRepository(
      listings: [l],
      requests: [_request(owner: l.ownerId)],
    );
    final deps = TestDeps(
      listings: FakeListingsRepository(rows: [l]),
      daily: daily,
    );
    await pumpScreen(
      tester,
      PropertyDetailsScreen(id: l.id, initial: l),
      overrides: await deps.overrides(user: fakeUser(id: _renter)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waiting for the owner'), findsOneWidget);
    expect(find.text('Contact on WhatsApp'), findsNothing);
  });

  testWidgets('the owner approves a request and chooses the number to share', (tester) async {
    final daily = FakeDailyRepository(
      listings: [dailyListing()],
      requests: [_request(renter: 'someone-else', owner: _renter)],
    );
    await pumpScreen(
      tester,
      const BookingsScreen(initialTab: 'requests'),
      overrides: await TestDeps(daily: daily).overrides(user: fakeUser(id: _renter)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rana'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Approve and share your number'), findsOneWidget);
    // Prefilled with the number last shared.
    expect(find.text('0791112222'), findsOneWidget);
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(daily.responses.single.$2, BookingAction.approve);
    expect(daily.responses.single.$3, '0791112222');
    expect(find.text('Confirm stay'), findsOneWidget, reason: 'approved, it can now be confirmed');
  });

  testWidgets('the owner sees a daily listing waiting for review with a grey check', (tester) async {
    final l = dailyListing(review: 'pending');
    await pumpScreen(
      tester,
      const DashboardScreen(),
      overrides: await TestDeps(listings: FakeListingsRepository(rows: [l])).overrides(user: fakeUser()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waiting for review'), findsOneWidget);
  });
}
