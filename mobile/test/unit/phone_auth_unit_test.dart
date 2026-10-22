import 'dart:convert';
import 'dart:typed_data';

import 'package:akarat/app/localization/gen/app_localizations.dart';
import 'package:akarat/core/utils/phone.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException, OtpChannel;

/// Answers every request with [status] and [body], and records what was sent.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('A stored number (Supabase keeps bare digits)', () {
    test('splits into a country on the list and its national number', () {
      final jo = Phone.split('962791234567')!;
      expect(jo.country.id, 'jo');
      expect(jo.national, '791234567');
      expect(Phone.split('+966512345678')!.country.id, 'sa');
      expect(Phone.split('+447911123456')!.country.id, 'gb');
      expect(Phone.split('12025550123')!.country.dial, '1');
      expect(Phone.split('+33123456789'), isNull, reason: 'France is not on the list');
      expect(Phone.split(null), isNull);
    });

    test('reads as it is said', () {
      expect(Phone.display('962791234567'), '+962 79 123 4567');
      expect(Phone.display('+96565123456'), '+965 6512 3456');
      expect(Phone.display('12025550123'), '+1 202 555 0123');
      expect(Phone.display('33123456789'), '+33123456789', reason: 'elsewhere: the digits behind a plus');
      expect(Phone.display(null), '');
      expect(Phone.display(''), '');
    });

    test('each country has its flag', () {
      expect(Phone.country('jo').flag, '🇯🇴');
      expect(Phone.country('gb').flag, '🇬🇧');
    });
  });

  group('Phone sign-in errors, in words', () {
    final l = lookupAppLocalizations(const Locale('en'));
    String say(AuthApiException e) => phoneAuthErrorMessage(l, e, (_) => 'fallback');

    test('each failure says what happened and what to do', () {
      expect(
        say(const AuthApiException('Unsupported phone provider', code: 'phone_provider_disabled')),
        l.authPhoneUnavailable,
      );
      expect(say(const AuthApiException('Signups not allowed for otp', code: 'otp_disabled')), l.authPhoneNoAccount);
      expect(say(const AuthApiException('Token has expired or is invalid', code: 'otp_expired')), l.authCodeWrong);
      expect(
        say(const AuthApiException('A user with this phone number has already been registered', code: 'phone_exists')),
        l.authPhoneTaken,
      );
      expect(say(const AuthApiException('Error sending sms OTP', code: 'sms_send_failed')), l.authCodeSendFailed);
      expect(
        say(const AuthApiException('For security purposes...', statusCode: '429', code: 'over_sms_send_rate_limit')),
        l.authCodeTooMany,
      );
      expect(
        say(const AuthApiException('Invalid phone number format (E.164 required)', code: 'validation_failed')),
        l.authPhoneInvalid,
      );
    });

    test('only the no-account answer offers a new account', () {
      expect(isNoPhoneAccount(const AuthApiException('Signups not allowed for otp', code: 'otp_disabled')), isTrue);
      expect(isNoPhoneAccount(const AuthApiException('Token has expired or is invalid', code: 'otp_expired')), isFalse);
    });
  });

  group('A change of number over WhatsApp', () {
    test('is the change-of-number request with the channel added, carrying the session', () async {
      final adapter = _Adapter(200, {'id': 'u1'});
      final dio = Dio()..httpClientAdapter = adapter;
      await requestPhoneChange(dio, token: 'session-token', phone: '+962791234567', channel: OtpChannel.whatsapp);
      final sent = adapter.last!;
      expect(sent.method, 'PUT');
      expect(sent.uri.path, '/auth/v1/user');
      expect(sent.headers['Authorization'], 'Bearer session-token');
      expect(sent.headers['apikey'], isNotEmpty);
      expect(sent.data, {'phone': '+962791234567', 'channel': 'whatsapp'});
    });

    test("Supabase's refusals come back as its own errors", () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter(422, {
          'code': 422,
          'error_code': 'phone_exists',
          'msg': 'A user with this phone number has already been registered',
        });
      await expectLater(
        requestPhoneChange(dio, token: 't', phone: '+962791234567', channel: OtpChannel.whatsapp),
        throwsA(
          isA<AuthApiException>()
              .having((e) => e.code, 'code', 'phone_exists')
              .having((e) => e.statusCode, 'status', '422'),
        ),
      );
    });
  });
}
