import 'dart:convert';
import 'dart:io';

import 'package:akarat/shared/models/daily_models.dart';
import 'package:akarat/shared/repositories/daily_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the app sends to PostgREST for daily rentals, read off the wire, and
/// checked against what 0019_daily_rentals.sql actually defines: a column or
/// a parameter name that drifts from the migration fails here, not in front
/// of a renter.

const _uid = '44444444-4444-4444-8444-444444444444';
const _listing = '55555555-5555-4555-8555-555555555555';
final _sql = File('../supabase/migrations/0019_daily_rentals.sql').readAsStringSync();

String _b64(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// An access token the client can read: it only decodes the payload.
final _jwt =
    '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({'sub': _uid, 'role': 'authenticated', 'exp': 4102444800})}.sig';

typedef _Seen = ({String method, Uri url, Map<String, String> headers, Object? body});

http.Response _json(Object? body, http.Request req, {int status = 200}) =>
    http.Response(jsonEncode(body), status, request: req, headers: {'content-type': 'application/json'});

Map<String, Object?> _bookingRow({String status = 'pending', String? phone}) => {
  'id': 'req-1',
  'property_id': _listing,
  'owner_id': 'owner-1',
  'renter_id': _uid,
  'renter_name': 'Rana',
  'check_in': '2099-11-10',
  'check_out': '2099-11-13',
  'nights': 3,
  'guests': 2,
  'message': null,
  'nightly_price': 60,
  'total_price': 180,
  'status': status,
  'owner_phone': phone,
  'response_note': null,
  'closed_reason': null,
  'cancelled_by': null,
  'responded_at': null,
  'created_at': '2026-10-29T10:00:00+00:00',
};

/// A client signed in through the mock, and everything it sent after that.
Future<(DailyRepository, List<_Seen>)> _signedIn(http.Response Function(http.Request req) answer) async {
  final seen = <_Seen>[];
  final client = SupabaseClient(
    'https://db.example.invalid',
    'publishable-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((req) async {
      if (req.url.path.startsWith('/auth/v1/token')) {
        return _json({
          'access_token': _jwt,
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': 4102444800,
          'refresh_token': 'refresh',
          'user': {
            'id': _uid,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'rana@example.com',
            'app_metadata': <String, Object?>{},
            'user_metadata': {'full_name': 'Rana Renter'},
            'created_at': '2026-09-01T00:00:00Z',
          },
        }, req);
      }
      seen.add((
        method: req.method,
        url: req.url,
        headers: req.headers,
        body: req.body.isEmpty ? null : jsonDecode(req.body),
      ));
      return answer(req);
    }),
  );
  addTearDown(client.dispose);
  await client.auth.signInWithPassword(email: 'rana@example.com', password: 'x');
  return (DailyRepository(client), seen);
}

/// The parameter list of a function in the migration, by name.
Set<String> _params(String fn) {
  final at = _sql.indexOf('create or replace function public.$fn(');
  expect(at, isNonNegative, reason: '$fn is in 0019');
  final open = _sql.indexOf('(', at);
  final close = _sql.indexOf(')\nreturns', open);
  return RegExp(r'\b(p_[a-z_]+)\b').allMatches(_sql.substring(open, close)).map((m) => m[1]!).toSet();
}

/// The columns of booking_requests as the migration creates it.
Set<String> _bookingColumns() {
  final at = _sql.indexOf('create table if not exists public.booking_requests (');
  final block = _sql.substring(at, _sql.indexOf('\n);', at));
  return RegExp(r'^\s{2}([a-z_]+)\s', multiLine: true).allMatches(block).map((m) => m[1]!).toSet();
}

void main() {
  test('search asks the migration\'s function with its own parameter names', () async {
    final (repo, seen) = await _signedIn((req) => _json([], req));
    await repo.search(checkIn: DateTime(2099, 11, 10), checkOut: DateTime(2099, 11, 13), guests: 2, cityId: 'aqaba');
    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.url.path, '/rest/v1/rpc/search_daily_rentals');
    expect(r.url.queryParameters['city_id'], 'eq.aqaba');
    expect(r.url.queryParameters['order'], startsWith('created_at.desc'));
    expect(r.body, {'p_check_in': '2099-11-10', 'p_check_out': '2099-11-13', 'p_guests': 2});
    expect((r.body! as Map).keys.toSet(), _params('search_daily_rentals'));
  });

  test('before 0019 runs, the Daily tab is empty, not an error', () async {
    final (repo, _) = await _signedIn(
      (req) => _json(
        {
          'code': 'PGRST202',
          'message': 'Could not find the function public.search_daily_rentals(p_check_in, p_check_out, p_guests) in the schema cache',
          'details': null,
          'hint': null,
        },
        req,
        status: 404,
      ),
    );
    expect(await repo.search(), isEmpty);
    expect(await repo.mine(), isEmpty);
  });

  test('the calendar reads plain dates', () async {
    final (repo, seen) = await _signedIn((req) => _json(['2099-11-11', '2099-11-12'], req));
    final off = await repo.unavailable(_listing, DateTime(2099, 11), DateTime(2099, 12));
    expect(off, {DateTime(2099, 11, 11), DateTime(2099, 11, 12)});
    expect(seen.single.url.path, '/rest/v1/rpc/daily_unavailable_days');
    expect((seen.single.body! as Map).keys.toSet(), _params('daily_unavailable_days'));
  });

  test('a request names the renter from the session and only columns that exist', () async {
    final (repo, seen) = await _signedIn((req) => _json(_bookingRow(), req, status: 201));
    final r = await repo.request(
      propertyId: _listing,
      checkIn: DateTime(2099, 11, 10),
      checkOut: DateTime(2099, 11, 13),
      guests: 2,
      message: '  Family of four ',
    );
    final sent = seen.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/rest/v1/booking_requests');
    final body = sent.body! as Map;
    expect(body['renter_id'], _uid);
    expect(body['renter_name'], 'Rana Renter');
    expect(body['check_in'], '2099-11-10');
    expect(body['message'], 'Family of four');
    // The owner and the prices are the database's to fill in.
    expect(body.containsKey('owner_id'), isFalse);
    expect(body.containsKey('total_price'), isFalse);
    expect(_bookingColumns(), containsAll(body.keys));
    expect(r.status, BookingStatus.pending);
    expect(r.totalPrice, 180);
  });

  test('a refusal from the database comes back as its reason and number', () async {
    final (repo, _) = await _signedIn(
      (req) => _json({'code': 'P0001', 'message': 'daily_min_nights', 'details': '2', 'hint': null}, req, status: 400),
    );
    await expectLater(
      repo.request(propertyId: _listing, checkIn: DateTime(2099, 11, 10), checkOut: DateTime(2099, 11, 11), guests: 1),
      throwsA(isA<DailyRefusal>().having((e) => e.key, 'key', 'daily_min_nights').having((e) => e.n, 'n', 2)),
    );
  });

  test('the lists select only columns booking_requests has', () async {
    final (repo, seen) = await _signedIn((req) => _json([_bookingRow(status: 'approved', phone: '0791234567')], req));
    final mine = await repo.mine();
    expect(mine.single.phoneShown, isTrue);
    // The embedded listing, properties(…), is the other table's columns.
    final select = seen.single.url.queryParameters['select']!.replaceAll(RegExp(r'\w+\([^)]*\)'), '');
    final columns = select.split(',').where((c) => c.isNotEmpty).toSet();
    expect(columns, hasLength(greaterThan(10)));
    expect(_bookingColumns(), containsAll(columns));
    expect(seen.single.url.queryParameters['renter_id'], 'eq.$_uid');
  });

  test('approving sends booking_respond its four parameters, and reads the row either way it comes', () async {
    for (final shape in ['object', 'list']) {
      final row = _bookingRow(status: 'approved', phone: '0791234567');
      final (repo, seen) = await _signedIn((req) => _json(shape == 'object' ? row : [row], req));
      final r = await repo.respond('req-1', BookingAction.approve, phone: '0791234567');
      expect(r.status, BookingStatus.approved, reason: shape);
      expect(seen.single.url.path, '/rest/v1/rpc/booking_respond');
      expect(seen.single.body, {'p_request': 'req-1', 'p_action': 'approve', 'p_phone': '0791234567', 'p_note': null});
      expect((seen.single.body! as Map).keys.toSet(), _params('booking_respond'));
    }
    // And every action the app can send is one the function knows.
    for (final a in BookingAction.values) {
      expect(_sql, contains("p_action = '${a.name}'"), reason: a.name);
    }
  });

  test('closing and opening a night', () async {
    final (repo, seen) = await _signedIn((req) => http.Response('', 201, request: req));
    await repo.setBlocked(_listing, DateTime(2099, 11, 20), blocked: true);
    await repo.setBlocked(_listing, DateTime(2099, 11, 20), blocked: false);
    expect(seen[0].method, 'POST');
    expect(seen[0].url.path, '/rest/v1/daily_blocked_days');
    expect(seen[0].url.queryParameters['on_conflict'], 'property_id,day');
    expect(seen[0].headers['Prefer'] ?? seen[0].headers['prefer'], contains('resolution=ignore-duplicates'));
    expect(seen[0].body, {'property_id': _listing, 'day': '2099-11-20'});
    expect(seen[1].method, 'DELETE');
    expect(seen[1].url.queryParameters['day'], 'eq.2099-11-20');
  });

  test('marking notifications read touches only the read flag of unread ones', () async {
    final (repo, seen) = await _signedIn((req) => http.Response('', 204, request: req));
    await repo.markAllRead();
    expect(seen.single.method, 'PATCH');
    expect(seen.single.url.queryParameters['read_at'], 'is.null');
    expect(seen.single.url.queryParameters['user_id'], 'eq.$_uid');
    expect((seen.single.body! as Map).keys, ['read_at']);
  });

  test('every refusal the migration raises has words in the app', () {
    final raised = RegExp(r"raise exception '(daily_[a-z_]+)'").allMatches(_sql).map((m) => m[1]!).toSet()
      // Only an app sending an action the function does not know can see
      // this one; it reads as the generic error.
      ..remove('daily_bad_action');
    expect(raised, hasLength(greaterThan(10)));
    final worded = File('lib/app/localization/l10n.dart').readAsStringSync();
    for (final key in raised) {
      expect(worded, contains("'$key'"), reason: '$key is worded');
    }
    final web = File('../Akarat.dc.html').readAsStringSync();
    for (final key in raised) {
      expect(web, contains('$key:'), reason: '$key is worded on the website');
    }
  });
}
