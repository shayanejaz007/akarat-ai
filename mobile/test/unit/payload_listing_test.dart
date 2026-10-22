import 'package:akarat/core/utils/formatters.dart';
import 'package:akarat/core/utils/payload_codec.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../support/fixtures.dart';

void main() {
  group('PayloadCodec', () {
    final f = fixture('payload.json')! as Map<String, Object?>;

    test('reads a payload the website packed', () {
      expect(PayloadCodec.unpack(f['packed']! as String), f['object']);
    });

    test('round-trips, and the website-shaped prefix is gz:', () {
      final object = f['object']! as Map<String, Object?>;
      final packed = PayloadCodec.pack(object);
      expect(packed.payloadGz, startsWith('gz:'));
      expect(packed.rawBytes, f['raw_bytes']);
      expect(PayloadCodec.unpack(packed.payloadGz), object);
      expect(packed.toColumns().keys, containsAll(['payload_gz', 'payload_bytes', 'raw_bytes']));
      expect(packed.toColumns().containsKey('ratio'), isFalse);
    });

    test('raw: and bare JSON are tolerated, garbage is not fatal', () {
      expect(PayloadCodec.unpack('raw:eyJhIjoxfQ=='), {'a': 1});
      expect(PayloadCodec.unpack('{"a":2}'), {'a': 2});
      expect(PayloadCodec.unpack('gz:not-base64!'), isEmpty);
      expect(PayloadCodec.unpack(null), isEmpty);
    });
  });

  group('Listing.fromRow', () {
    test('a stray non-text value does not break the row (seen in production)', () {
      final row = <String, Object?>{
        'id': 'a1b2c3d4-0000-4000-8000-000000000001',
        'status': 'active',
        'deal': 'sale',
        'property_type': 'apartment',
        'price_jod': 90000,
        'title_en': 'Flat',
        'title_ar': false,
        'address': true,
        'payload_gz': PayloadCodec.pack({
          'description_en': false,
          'contact': {'phone': false, 'whatsapp': true},
        }).payloadGz,
      };
      final l = Listing.fromRow(row);
      expect(l.titleAr, isNull);
      expect(l.address, isNull);
      expect(l.payload.descriptionEn, isEmpty);
      expect(l.payload.contact.phone, isEmpty);
      expect(l.payload.contact.whatsapp, isTrue);
    });

    final packed = PayloadCodec.pack({
      'amenities': ['garden'],
      'description_en': 'English text',
      'description_ar': '',
      'images': [
        {'url': 'https://x.invalid/clip.mp4', 'path': 'u/clip.mp4'},
        {'url': 'https://x.invalid/a.jpg', 'path': 'u/a.jpg', 'type': 'image'},
      ],
      'contact': {'phone': ' 0791234567 ', 'whatsapp': true, 'messaging': true},
    });
    final row = <String, Object?>{
      'id': '11111111-1111-1111-1111-111111111111',
      'owner_id': '22222222-2222-2222-2222-222222222222',
      'status': 'sold',
      'deal': 'rent',
      'property_type': 'apartment',
      'city_id': 'amman',
      'neighborhood_id': 'abdoun',
      'lat': 31.9,
      'lng': '35.8',
      'price_jod': 500,
      'bedrooms': 3,
      'title_en': 'Bright flat',
      'title_ar': null,
      'payload_gz': packed.payloadGz,
      'created_at': '2026-09-01T10:00:00Z',
      'location_precision': 'approximate',
    };
    final l = Listing.fromRow(row);

    test('columns and payload are read', () {
      expect(l.status, ListingStatus.sold);
      expect(l.isClosed, isTrue);
      expect(l.isRent, isTrue);
      expect(l.lng, 35.8);
      expect(l.payload.contact.phone, '0791234567');
      expect(l.payload.amenities, ['garden']);
      expect(l.locationPrecision, LocationPrecision.approximate);
    });

    test('a video URL is a video even without a type, and the cover skips it', () {
      expect(l.media.first.isVideo, isTrue);
      expect(l.coverUrl, 'https://x.invalid/a.jpg');
    });

    test('Arabic falls back to English, never to a translation', () {
      expect(l.title('ar'), 'Bright flat');
      expect(l.description('ar'), 'English text');
      expect(l.place('en'), 'Abdoun · Amman');
      expect(l.place('ar'), 'عبدون · عمان');
    });

    test('a database without migration 0010 leaves precision null', () {
      final legacy = Listing.fromRow({...row}..remove('location_precision'));
      expect(legacy.locationPrecision, isNull);
    });
  });

  group('Fmt', () {
    test('prices match the website wording', () {
      expect(Fmt.price(150000, lang: 'en'), '150,000 JOD');
      expect(Fmt.price(500, lang: 'en', rent: true), '500 JOD/mo');
      expect(Fmt.price(150000, lang: 'ar'), '150,000 دينار');
      expect(Fmt.price(500, lang: 'ar', rent: true), '500 دينار شهرياً');
      expect(Fmt.price(null, lang: 'en'), 'Not provided');
    });

    test('dates use Jordanian month names in Arabic', () async {
      await initializeDateFormatting('en_GB');
      final d = DateTime(2026, 9, 20, 12);
      expect(Fmt.date(d, lang: 'ar'), '20 أيلول 2026');
      expect(Fmt.date(DateTime(2026, 8, 1, 12), lang: 'ar'), '1 آب 2026');
      expect(Fmt.date(d, lang: 'en'), '20 Sept 2026');
    });

    test('compact prices', () {
      expect(Fmt.compactPrice(150000, lang: 'en'), '150K JOD');
      expect(Fmt.compactPrice(1250000, lang: 'en'), '1.3M JOD');
      expect(Fmt.compactPrice(900, lang: 'en'), '900 JOD');
    });
  });
}
