import 'package:akarat/core/utils/formatters.dart';
import 'package:akarat/features/daily/stay_pick.dart';
import 'package:akarat/shared/models/daily_models.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('Daily listing rows', () {
    test('a daily row reads its deal, guests, stay and review', () {
      final l = dailyListing(review: 'rejected', note: 'Photos are blurry', maxGuests: 6, minNights: 3);
      expect(l.deal, DealType.daily);
      expect(l.isDaily, isTrue);
      expect(l.isRent, isFalse);
      expect(l.maxGuests, 6);
      expect(l.minimumNights, 3);
      expect(l.dailyReview, DailyReview.rejected);
      expect(l.dailyReviewNote, 'Photos are blurry');
    });

    test('rows written before daily rentals read as before', () {
      final l = listing(deal: 'rent');
      expect(l.deal, DealType.rent);
      expect(l.dailyReview, isNull);
      expect(l.minimumNights, 1);
      expect(DealType.parse('nonsense'), DealType.sale);
    });

    test('a nightly price says so in both languages', () {
      expect(Fmt.price(60, lang: 'en', night: true), '60 JOD/night');
      expect(Fmt.price(60, lang: 'ar', night: true), '60 دينار لليلة');
      expect(Fmt.price(500, lang: 'en', rent: true), '500 JOD/mo');
    });
  });

  group('Picking a stay', () {
    DateTime d(int n) => DateTime(2026, 11, n);

    test('first tap is check-in, second check-out, a third starts over', () {
      var p = const StayPick().tap(d(10));
      expect(p.checkIn, d(10));
      expect(p.complete, isFalse);
      p = p.tap(d(13));
      expect(p.checkOut, d(13));
      expect(p.nights, 3);
      p = p.tap(d(20));
      expect(p.checkIn, d(20));
      expect(p.checkOut, isNull);
    });

    test('tapping before check-in moves check-in', () {
      final p = const StayPick().tap(d(10)).tap(d(8));
      expect(p.checkIn, d(8));
      expect(p.checkOut, isNull);
    });

    test('a taken night cannot start a stay, or be stayed through', () {
      final taken = {d(12)};
      expect(const StayPick().tap(d(12), taken: taken).checkIn, isNull);
      final crossed = const StayPick().tap(d(10), taken: taken).tap(d(14), taken: taken);
      expect(crossed.crossedTaken, isTrue);
      expect(crossed.checkOut, isNull);
      expect(crossed.checkIn, d(14), reason: 'starts again from the day tapped');
    });

    test('but it can be the morning someone leaves', () {
      final taken = {d(12)};
      final p = const StayPick().tap(d(10), taken: taken).tap(d(12), taken: taken);
      expect(p.complete, isTrue);
      expect(p.nights, 2);
    });

    test('nights are counted by calendar day, whatever the clock does', () {
      // Jordan's clocks change in spring and autumn; nights stay whole.
      expect(nightsBetween(DateTime(2026, 2, 26, 23), DateTime(2026, 3, 2, 1)), 4);
      expect(nightsBetween(DateTime(2026, 10, 29), DateTime(2026, 11, 1)), 3);
    });
  });

  group('Booking requests', () {
    Map<String, Object?> row(String status, {String? phone, String checkIn = '2099-11-10'}) => {
      'id': 'req-1',
      'property_id': '55555555-5555-4555-8555-555555555555',
      'owner_id': 'o',
      'renter_id': 'r',
      'renter_name': 'Rana',
      'check_in': checkIn,
      'check_out': '2099-11-13',
      'nights': 3,
      'guests': 2,
      'nightly_price': 60,
      'total_price': 180,
      'status': status,
      'owner_phone': phone,
      'created_at': '2026-10-29T10:00:00Z',
      'properties': {'title_en': 'Chalet', 'title_ar': 'شاليه'},
    };

    test('the phone shows only once approved or confirmed', () {
      expect(BookingRequest.fromRow(row('pending')).phoneShown, isFalse);
      expect(BookingRequest.fromRow(row('approved', phone: '0791234567')).phoneShown, isTrue);
      expect(BookingRequest.fromRow(row('confirmed', phone: '0791234567')).phoneShown, isTrue);
      // Even if a number were ever left behind on a rejected one.
      expect(BookingRequest.fromRow(row('rejected', phone: '0791234567')).phoneShown, isFalse);
    });

    test('reads its dates, totals and listing', () {
      final r = BookingRequest.fromRow(row('pending'));
      expect(r.checkIn, DateTime(2099, 11, 10));
      expect(r.nights, 3);
      expect(r.totalPrice, 180);
      expect(r.title('ar'), 'شاليه');
      expect(r.isOpen, isTrue);
    });

    test('a pending request past its check-in has expired', () {
      final r = BookingRequest.fromRow(row('pending', checkIn: '2026-01-01'));
      expect(r.expiredOn(DateTime(2026, 10, 29)), isTrue);
    });
  });
}
