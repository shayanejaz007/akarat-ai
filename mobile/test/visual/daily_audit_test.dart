// Visual audit of daily rentals, rendered with the real fonts, in English
// and Arabic, on a small phone and with large text. Any overflow fails.
//
//   flutter test test/visual/daily_audit_test.dart --tags visual --update-goldens --run-skipped
//
// Writes test/visual/goldens/daily/*.png for review.
@Tags(['visual'])
library;

import 'package:akarat/features/daily/availability_screen.dart';
import 'package:akarat/features/daily/bookings_screen.dart';
import 'package:akarat/features/daily/daily_screen.dart';
import 'package:akarat/features/daily/notifications_screen.dart';
import 'package:akarat/features/dashboard/dashboard_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/shared/models/daily_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import 'render.dart';

const _me = '44444444-4444-4444-8444-444444444444';

BookingRequest _req(BookingStatus status, {String? phone, String renter = _me, String owner = 'owner-9'}) =>
    BookingRequest(
      id: 'req-${status.name}',
      propertyId: dailyListing().id,
      ownerId: owner,
      renterId: renter,
      renterName: 'رنا العلي',
      checkIn: DateTime(2099, 11, 10),
      checkOut: DateTime(2099, 11, 13),
      nights: 3,
      guests: 2,
      nightlyPrice: 60,
      totalPrice: 180,
      status: status,
      createdAt: DateTime(2026, 10, 29),
      message: 'We are a family of four visiting Aqaba for the weekend.',
      ownerPhone: phone,
      titleEn: 'Sea-view chalet in Aqaba',
      titleAr: 'شاليه مطل على البحر في العقبة',
    );

void main() {
  setUpAll(loadRealFonts);

  for (final lang in ['en', 'ar']) {
    testWidgets('daily tab $lang', (t) async {
      final daily = FakeDailyRepository(
        listings: [
          dailyListing(),
          dailyListing(
            id: '66666666-6666-4666-8666-666666666666',
            price: 140,
            maxGuests: 10,
            minNights: 1,
            titleEn: 'Farm with a pool in Jerash',
          ),
        ],
      );
      await render(
        t,
        'daily-tab-$lang',
        const DailyScreen(),
        overrides: await TestDeps(daily: daily).overrides(),
        lang: lang,
        folder: 'daily',
      );
    });

    testWidgets('daily listing, booking sheet $lang', (t) async {
      final l = dailyListing(owner: '99999999-9999-4999-8999-999999999999');
      final deps = TestDeps(
        listings: FakeListingsRepository(rows: [l]),
        daily: FakeDailyRepository(listings: [l], taken: {DateTime(2099, 11, 20)}),
      );
      await render(
        t,
        'booking-sheet-$lang',
        PropertyDetailsScreen(id: l.id, initial: l),
        overrides: await deps.overrides(user: fakeUser(id: _me)),
        lang: lang,
        folder: 'daily',
        interact: (t) async {
          await t.tap(find.text(lang == 'ar' ? 'اطّلع على التوفر' : 'Check availability'));
        },
      );
    });

    testWidgets('approved request on the listing $lang', (t) async {
      final l = dailyListing(owner: '99999999-9999-4999-8999-999999999999');
      final deps = TestDeps(
        listings: FakeListingsRepository(rows: [l]),
        daily: FakeDailyRepository(
          listings: [l],
          requests: [_req(BookingStatus.approved, phone: '0791234567', owner: l.ownerId)],
        ),
      );
      await render(
        t,
        'approved-$lang',
        PropertyDetailsScreen(id: l.id, initial: l),
        overrides: await deps.overrides(user: fakeUser(id: _me)),
        lang: lang,
        folder: 'daily',
        interact: (t) async {
          await t.drag(find.byType(Scrollable).first, const Offset(0, -520));
        },
      );
    });

    testWidgets('owner requests $lang', (t) async {
      final daily = FakeDailyRepository(
        listings: [dailyListing()],
        requests: [
          _req(BookingStatus.pending, renter: 'someone', owner: _me),
          _req(BookingStatus.approved, phone: '0791112222', renter: 'someone', owner: _me),
        ],
      );
      await render(
        t,
        'owner-requests-$lang',
        const BookingsScreen(initialTab: 'requests'),
        overrides: await TestDeps(daily: daily).overrides(user: fakeUser(id: _me)),
        lang: lang,
        folder: 'daily',
      );
    });
  }

  testWidgets('daily tab, small phone, large Arabic text', (t) async {
    await render(
      t,
      'daily-tab-ar-compact-large',
      const DailyScreen(),
      overrides: await TestDeps(daily: FakeDailyRepository(listings: [dailyListing()])).overrides(),
      lang: 'ar',
      device: Device.compact,
      textScale: 1.3,
      folder: 'daily',
    );
  });

  testWidgets('owner requests, small phone, large text', (t) async {
    final daily = FakeDailyRepository(
      listings: [dailyListing()],
      requests: [_req(BookingStatus.pending, renter: 'x', owner: _me)],
    );
    await render(
      t,
      'owner-requests-en-compact-large',
      const BookingsScreen(initialTab: 'requests'),
      overrides: await TestDeps(daily: daily).overrides(user: fakeUser(id: _me)),
      device: Device.compact,
      textScale: 1.3,
      folder: 'daily',
    );
  });

  testWidgets('my bookings ar', (t) async {
    final daily = FakeDailyRepository(
      listings: [dailyListing()],
      requests: [
        _req(BookingStatus.confirmed, phone: '0791234567'),
        _req(BookingStatus.rejected).copyForTest(closedReason: 'dates_taken'),
      ],
    );
    await render(
      t,
      'my-bookings-ar',
      const BookingsScreen(initialTab: 'mine'),
      overrides: await TestDeps(daily: daily).overrides(user: fakeUser(id: _me)),
      lang: 'ar',
      folder: 'daily',
    );
  });

  testWidgets('availability ar', (t) async {
    final l = dailyListing(owner: _me);
    final daily = FakeDailyRepository(
      listings: [l],
      requests: [_req(BookingStatus.confirmed, renter: 'x', owner: _me)],
    )..blocked[l.id] = {DateTime.now().add(const Duration(days: 3))};
    await render(
      t,
      'availability-ar',
      AvailabilityScreen(listingId: l.id),
      overrides: await TestDeps(
        listings: FakeListingsRepository(rows: [l]),
        daily: daily,
      ).overrides(user: fakeUser(id: _me)),
      lang: 'ar',
      folder: 'daily',
    );
  });

  testWidgets('notifications en', (t) async {
    final daily = FakeDailyRepository(
      alerts: [
        AppNotification(
          id: 'n1',
          kind: 'booking_new',
          data: const {
            'title_en': 'Sea-view chalet',
            'renter_name': 'Rana',
            'check_in': '2099-11-10',
            'check_out': '2099-11-13',
          },
          createdAt: DateTime(2026, 10, 29),
        ),
        AppNotification(
          id: 'n2',
          kind: 'listing_rejected',
          data: const {'title_en': 'Farm in Jerash', 'note': 'The photos are of another property.'},
          createdAt: DateTime(2026, 10, 28),
          readAt: DateTime(2026, 10, 28),
        ),
        AppNotification(
          id: 'n3',
          kind: 'booking_approved',
          data: const {'title_en': 'Sea-view chalet'},
          createdAt: DateTime(2026, 10, 27),
          readAt: DateTime(2026, 10, 27),
        ),
      ],
    );
    await render(
      t,
      'notifications-en',
      const NotificationsScreen(),
      overrides: await TestDeps(daily: daily).overrides(user: fakeUser(id: _me)),
      folder: 'daily',
    );
  });

  testWidgets('dashboard with a daily listing in review ar', (t) async {
    final rows = [
      dailyListing(review: 'pending'),
      dailyListing(id: '77777777-7777-4777-8777-777777777777', review: 'rejected', note: 'Photos are blurry'),
    ];
    await render(
      t,
      'dashboard-review-ar',
      const DashboardScreen(),
      overrides: await TestDeps(listings: FakeListingsRepository(rows: rows)).overrides(user: fakeUser()),
      lang: 'ar',
      device: Device.compact,
      folder: 'daily',
    );
  });
}

extension on BookingRequest {
  BookingRequest copyForTest({String? closedReason}) => BookingRequest(
    id: '$id-2',
    propertyId: propertyId,
    ownerId: ownerId,
    renterId: renterId,
    renterName: renterName,
    checkIn: checkIn,
    checkOut: checkOut,
    nights: nights,
    guests: guests,
    nightlyPrice: nightlyPrice,
    totalPrice: totalPrice,
    status: status,
    createdAt: createdAt,
    closedReason: closedReason,
    titleEn: titleEn,
    titleAr: titleAr,
  );
}
