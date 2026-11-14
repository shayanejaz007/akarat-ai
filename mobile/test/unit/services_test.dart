// Services (supabase/migrations/0024_services.sql) from the app: what the
// repository sends to the database's functions, how it reads what comes
// back, how it explains a refusal, and that the app, the website and the
// migration agree on every field of a request.
import 'dart:convert';
import 'dart:io';

import 'package:akarat/features/services/services_models.dart';
import 'package:akarat/features/services/services_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = '44444444-4444-4444-8444-444444444444';
final _sql = File('../supabase/migrations/0024_services.sql').readAsStringSync();

String _b64(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
final _jwt =
    '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({'sub': _uid, 'role': 'authenticated', 'exp': 4102444800})}.sig';

typedef _Seen = ({String method, Uri url, Object? body});

http.Response _json(Object? body, http.Request req, {int status = 200}) =>
    http.Response(jsonEncode(body), status, request: req, headers: {'content-type': 'application/json'});

Future<(ServicesRepository, List<_Seen>)> _repo(
  http.Response Function(http.Request req) answer, {
  bool signIn = true,
}) async {
  final seen = <_Seen>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'publishable',
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
            'email': 'lina@example.com',
            'app_metadata': <String, Object?>{},
            'user_metadata': {'full_name': 'Lina Haddad'},
            'created_at': '2026-09-01T00:00:00Z',
          },
        }, req);
      }
      seen.add((method: req.method, url: req.url, body: req.body.isEmpty ? null : jsonDecode(req.body)));
      return answer(req);
    }),
  );
  addTearDown(client.dispose);
  if (signIn) await client.auth.signInWithPassword(email: 'lina@example.com', password: 'x');
  return (ServicesRepository(client), seen);
}

const _mine = [
  {
    'id': 'r1',
    'ref': 'SR-000042',
    'status': 'accepted',
    'category_id': 'plumbing',
    'category_en': 'Plumbing',
    'category_ar': 'السباكة',
    'icon': 'plumbing',
    'custom_service': null,
    'description': 'The kitchen sink is leaking.',
    'governorate_id': 'amman',
    'city_id': 'amman',
    'neighborhood_id': 'abdoun',
    'address': 'Cairo St 9',
    'lat': 31.95,
    'lng': 35.88,
    'preferred_date': '2026-11-15',
    'preferred_window': 'morning',
    'urgency': 'urgent',
    'photos': ['$_uid/t-0.jpg'],
    'created_at': '2026-11-12T08:10:00Z',
    'cancellable': true,
    'events': [
      {'at': '2026-11-12T08:10:00Z', 'kind': 'created', 'status': 'pending', 'note': null, 'by': 'customer'},
      {
        'at': '2026-11-12T10:00:00Z',
        'kind': 'status',
        'status': 'accepted',
        'note': 'A plumber will call you.',
        'by': 'admin',
      },
    ],
  },
];

void main() {
  test('the categories, in the order the admin set', () async {
    final (repo, seen) = await _repo(
      (req) => _json([
        {
          'id': 'plumbing',
          'name_en': 'Plumbing',
          'name_ar': 'السباكة',
          'examples_en': 'Leaks',
          'examples_ar': 'تسريب',
          'icon': 'plumbing',
          'custom': false,
        },
        {
          'id': 'custom',
          'name_en': 'Custom service',
          'name_ar': 'خدمة أخرى',
          'examples_en': '',
          'examples_ar': '',
          'icon': 'custom',
          'custom': true,
        },
      ], req),
      signIn: false,
    );
    final cats = await repo.categories();
    expect([for (final c in cats) c.id], ['plumbing', 'custom']);
    expect(cats.first.name('ar'), 'السباكة');
    expect(cats.last.custom, isTrue);
    expect(seen.single.url.path, '/rest/v1/service_categories');
    expect(seen.single.url.queryParameters['order'], contains('sort'));
  });

  test('sending a request: one call to create_service_request(p), and the reference back', () async {
    final (repo, seen) = await _repo(
      (req) => _json({'id': 'r9', 'ref': 'SR-000043', 'status': 'pending', 'duplicate': false}, req),
    );
    final out = await repo.create({'client_token': 't', 'category_id': 'plumbing'});
    expect(out.ref, 'SR-000043');
    expect(out.duplicate, isFalse);
    final call = seen.single;
    expect(call.method, 'POST');
    expect(call.url.path, '/rest/v1/rpc/create_service_request');
    expect(call.body, {
      'p': {'client_token': 't', 'category_id': 'plumbing'},
    });
  });

  test('a retry is the first request again, not a second one', () async {
    final (repo, _) = await _repo(
      (req) => _json({'id': 'r9', 'ref': 'SR-000043', 'status': 'pending', 'duplicate': true}, req),
    );
    expect((await repo.create({'client_token': 't'})).duplicate, isTrue);
  });

  test('a refusal names the field it is about, or what went wrong', () async {
    Future<ServiceRefusal> refused(int status, Map<String, Object?> body) async {
      final (repo, _) = await _repo((req) => _json(body, req, status: status));
      try {
        await repo.create({'client_token': 't'});
      } on ServiceRefusal catch (e) {
        return e;
      }
      fail('not refused');
    }

    final phone = await refused(400, {'code': 'P0001', 'message': 'invalid:contact_phone'});
    expect(phone.field, 'contact_phone');
    expect((await refused(400, {'code': 'P0001', 'message': 'too_many'})).code, 'too_many');
    expect((await refused(401, {'code': 'P0001', 'message': 'sign_in'})).code, 'sign_in');
    final missing = await refused(404, {
      'code': 'PGRST202',
      'message': 'Could not find the function public.create_service_request',
    });
    expect(missing.code, 'not_set_up');
  });

  test("my requests: status, progress, the team's note, and whether it can still be cancelled", () async {
    final (repo, seen) = await _repo((req) => _json(_mine, req));
    final rows = await repo.mine();
    expect(seen.single.url.path, '/rest/v1/rpc/my_service_requests');
    final r = rows.single;
    expect(r.ref, 'SR-000042');
    expect(r.title('ar'), 'السباكة');
    expect(r.step, serviceFlow.indexOf('accepted'));
    expect(r.open, isTrue);
    expect(r.cancellable, isTrue);
    expect(r.teamNote, 'A plumber will call you.');
    expect(r.events.first.byCustomer, isTrue);
    expect(r.photos, ['$_uid/t-0.jpg']);
  });

  test('signed out, there is nothing to ask for', () async {
    final (repo, seen) = await _repo((req) => _json([], req), signIn: false);
    expect(await repo.mine(), isEmpty);
    expect(seen, isEmpty);
  });

  test('cancelling sends the id, and no reason when none was written', () async {
    final (repo, seen) = await _repo((req) => _json({'id': 'r1', 'ref': 'SR-000042', 'status': 'cancelled'}, req));
    await repo.cancel('r1', reason: '   ');
    expect(seen.single.url.path, '/rest/v1/rpc/cancel_service_request');
    expect(seen.single.body, {'p_id': 'r1', 'p_reason': null});
  });

  test('a token per submission, in the uuid shape the database casts it to', () {
    final a = ServicesRepository.newToken();
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(ServicesRepository.newToken(), isNot(a));
  });

  test('the app, the website and the migration agree on every field of a request', () {
    final fn = _sql.substring(
      _sql.indexOf('create or replace function public.create_service_request'),
      _sql.indexOf('create or replace function public.my_service_requests'),
    );
    final sqlKeys = RegExp(r"p\s*(?:->>|->|\?)\s*'([a-z_]+)'").allMatches(fn).map((m) => m[1]!).toSet();
    final app = File('lib/features/services/service_request_screen.dart').readAsStringSync();
    final appCall = app.substring(app.indexOf('repo.create({'), app.indexOf('});', app.indexOf('repo.create({')));
    final appKeys = RegExp(r"'([a-z_]+)':").allMatches(appCall).map((m) => m[1]!).toSet();
    final web = File('../Akarat.dc.html').readAsStringSync();
    final webCall = web.substring(
      web.indexOf('db.createServiceRequest({'),
      web.indexOf('});', web.indexOf('db.createServiceRequest({')),
    );
    final webKeys = RegExp(r'\b([a-z_]+):').allMatches(webCall).map((m) => m[1]!).toSet();
    expect(appKeys, sqlKeys, reason: 'the app sends what create_service_request() reads');
    expect(webKeys, sqlKeys, reason: 'the website sends what create_service_request() reads');
  });
}
