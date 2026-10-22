import 'package:akarat/app/router/routes.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:akarat/features/authentication/presentation/phone_auth_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_up_screen.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/harness.dart';

/// Stands in for Supabase's phone codes: records what was asked, answers
/// with [sendError] / [verifyError] when given one, and signs in a user
/// created at [createdAt] (now, unless told otherwise).
class _FakePhoneAuth extends Fake implements AuthService {
  _FakePhoneAuth({this.sendError, this.verifyError, this.createdAt, this.via = OtpChannel.sms});
  Object? sendError;
  Object? verifyError;
  final String? createdAt;
  final OtpChannel via;
  final sent = <({String phone, bool create, Map<String, Object> data})>[];
  final verified = <(String, String)>[];
  final linked = <String>[];
  final confirmed = <(String, String)>[];

  @override
  OtpChannel get channel => via;

  @override
  Future<void> sendPhoneCode(String phone, {bool create = false, Map<String, Object> data = const {}}) async {
    sent.add((phone: phone, create: create, data: data));
    if (sendError != null) throw sendError!;
  }

  @override
  Future<User?> verifyPhoneCode(String phone, String code) async {
    verified.add((phone, code));
    if (verifyError != null) throw verifyError!;
    return User(
      id: '33333333-3333-4333-8333-333333333333',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      phone: phone.substring(1),
      createdAt: createdAt ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> startPhoneLink(String phone) async {
    linked.add(phone);
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> confirmPhoneLink(String phone, String code) async {
    confirmed.add((phone, code));
    if (verifyError != null) throw verifyError!;
  }
}

const _noAccount = AuthApiException('Signups not allowed for otp', statusCode: '422', code: 'otp_disabled');
const _badCode = AuthApiException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired');
const _switchedOff = AuthApiException('Unsupported phone provider', statusCode: '400', code: 'phone_provider_disabled');
const _taken = AuthApiException(
  'A user with this phone number has already been registered',
  statusCode: '422',
  code: 'phone_exists',
);

/// Where the reader was, the phone page pushed on top as the app opens it,
/// and the places it can lead.
List<RouteBase> _routes(Widget page) => [
  GoRoute(
    path: '/',
    builder: (context, _) => Scaffold(
      body: Center(
        child: TextButton(onPressed: () => context.push('/phone'), child: const Text('Where I was')),
      ),
    ),
  ),
  GoRoute(path: '/phone', builder: (_, _) => page),
  GoRoute(
    path: Routes.home,
    builder: (_, _) => const Scaffold(body: Text('Home')),
  ),
  GoRoute(
    path: Routes.signIn,
    builder: (_, _) => const Scaffold(body: Text('Email sign-in')),
  ),
  GoRoute(
    path: Routes.signUp,
    builder: (_, _) => const Scaffold(body: Text('Email sign-up')),
  ),
];

Future<_FakePhoneAuth> _open(WidgetTester tester, PhoneAuthKind kind, [_FakePhoneAuth? auth]) async {
  final fake = auth ?? _FakePhoneAuth();
  await pumpRouted(
    tester,
    _routes(PhoneAuthScreen(kind: kind)),
    overrides: [
      ...await TestDeps().overrides(user: kind == PhoneAuthKind.link ? fakeUser() : null),
      authServiceProvider.overrideWithValue(fake),
    ],
  );
  await tester.tap(find.text('Where I was'));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _enterNumber(WidgetTester tester, String number) =>
    tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), number);

Future<void> _sendCode(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Send code'));
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

/// Types the code; the page checks it at the sixth digit. The confirmation
/// shows for a moment over the screen, so look while it does, then settle.
Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.widgetWithText(TextField, 'Verification code'), code);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Signing in by phone', () {
    testWidgets('a number of the wrong length is refused before anything is sent', (tester) async {
      final auth = await _open(tester, PhoneAuthKind.signIn);
      await _enterNumber(tester, '7912');
      await _sendCode(tester);
      expect(auth.sent, isEmpty, reason: 'nothing is billed for a typo');
      expect(find.textContaining('9-digit number after +962'), findsWidgets);
    });

    testWidgets('the code goes to the number as typed locally, and signing in returns where the reader was', (
      tester,
    ) async {
      final auth = await _open(tester, PhoneAuthKind.signIn);
      await _enterNumber(tester, '079 123 4567');
      await _sendCode(tester);
      expect(auth.sent.single.phone, '+962791234567');
      expect(auth.sent.single.create, isFalse, reason: 'signing in never makes a second account');
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.textContaining('+962 79 123 4567'), findsOneWidget, reason: 'the number it went to');
      expect(find.textContaining('by text message'), findsOneWidget);

      await _enterCode(tester, '123456');
      expect(auth.verified, [('+962791234567', '123456')], reason: 'checked the moment the sixth digit is in');
      expect(find.text('Signed in'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Where I was'), findsOneWidget);
    });

    testWidgets('Arabic numerals and another country', (tester) async {
      final auth = await _open(tester, PhoneAuthKind.signIn);
      await tester.tap(find.text('+962'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saudi Arabia'));
      await tester.pumpAndSettle();
      await _enterNumber(tester, '٥١٢٣٤٥٦٧٨');
      await _sendCode(tester);
      expect(auth.sent.single.phone, '+966512345678');
    });

    testWidgets('another code waits a minute, then goes to the same number', (tester) async {
      final auth = await _open(tester, PhoneAuthKind.signIn);
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      final resend = find.widgetWithText(TextButton, 'Resend code in 60s');
      expect(resend, findsOneWidget);
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.widgetWithText(TextButton, 'Resend code'));
      await tester.pumpAndSettle();
      expect(auth.sent.map((s) => s.phone), ['+962791234567', '+962791234567']);
      expect(find.text('A new code is on its way.'), findsOneWidget);
    });

    testWidgets('a wrong code says so and keeps the page; Change number goes back to it', (tester) async {
      final auth = await _open(tester, PhoneAuthKind.signIn, _FakePhoneAuth(verifyError: _badCode));
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      await _enterCode(tester, '000000');
      await tester.pumpAndSettle();
      expect(find.textContaining('wrong or has expired'), findsOneWidget);
      expect(find.text('Enter your code'), findsOneWidget);
      expect(auth.verified, hasLength(1));

      await tester.tap(find.text('Change number'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with your phone'), findsOneWidget);
      expect(find.text('791234567'), findsOneWidget, reason: 'the number stays, ready to correct');
    });

    testWidgets('no account with this number: says how to link it, and offers a new account with it', (tester) async {
      final auth = await _open(tester, PhoneAuthKind.signIn, _FakePhoneAuth(sendError: _noAccount));
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      expect(find.textContaining('No account uses this number yet'), findsOneWidget);

      auth.sendError = null;
      await tester.tap(find.text('Create an account with this number'));
      await tester.pumpAndSettle();
      expect(find.text('Create an account with your phone'), findsOneWidget);
      expect(find.text('791234567'), findsOneWidget, reason: 'the number carries over');
      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Lina Haddad');
      await _sendCode(tester);
      final last = auth.sent.last;
      expect(last.create, isTrue);
      expect(last.data['full_name'], 'Lina Haddad');
      expect(last.data['locale'], 'en');
      expect(last.data['tour_pending'], isTrue, reason: 'the new account is owed its welcome tour');
    });

    testWidgets('phone sign-in switched off in the project: said plainly', (tester) async {
      await _open(tester, PhoneAuthKind.signIn, _FakePhoneAuth(sendError: _switchedOff));
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      expect(find.textContaining('isn’t available right now'), findsOneWidget);
    });

    testWidgets('Use email instead goes to the email form', (tester) async {
      await _open(tester, PhoneAuthKind.signIn);
      await tester.ensureVisible(find.text('Use email instead'));
      await tester.tap(find.text('Use email instead'));
      await tester.pumpAndSettle();
      expect(find.text('Email sign-in'), findsOneWidget);
    });

    testWidgets('codes sent on WhatsApp say so', (tester) async {
      await _open(tester, PhoneAuthKind.signIn, _FakePhoneAuth(via: OtpChannel.whatsapp));
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      expect(find.textContaining('on WhatsApp'), findsOneWidget);
    });
  });

  group('Signing up by phone', () {
    testWidgets('needs a name, then lands the new account on Home', (tester) async {
      final auth = await _open(tester, PhoneAuthKind.signUp);
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      expect(auth.sent, isEmpty);
      expect(find.text('Required'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Lina Haddad');
      await _sendCode(tester);
      expect(auth.sent.single.create, isTrue);
      await _enterCode(tester, '123456');
      expect(find.text('Welcome, Lina Haddad. Your account is ready.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget, reason: 'where its welcome tour begins');
    });

    testWidgets('a number that already has an account simply signs in', (tester) async {
      await _open(tester, PhoneAuthKind.signUp, _FakePhoneAuth(createdAt: '2026-03-01T10:00:00Z'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Lina Haddad');
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      await _enterCode(tester, '123456');
      expect(find.text('Signed in'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Where I was'), findsOneWidget);
    });
  });

  group('Linking a number to the account', () {
    testWidgets('confirms the number with a code, then returns to Profile', (tester) async {
      final auth = await _open(tester, PhoneAuthKind.link);
      expect(find.text('Add a phone number'), findsOneWidget);
      expect(find.text('Use email instead'), findsNothing);
      await _enterNumber(tester, '0791234567');
      await _sendCode(tester);
      expect(auth.linked, ['+962791234567']);
      expect(auth.sent, isEmpty, reason: 'a change of number, not a sign-in');
      await _enterCode(tester, '654321');
      expect(auth.confirmed, [('+962791234567', '654321')]);
      expect(find.text('Number added. You can sign in with it now.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Where I was'), findsOneWidget);
    });

    testWidgets('a number already on another account is refused', (tester) async {
      await _open(tester, PhoneAuthKind.link, _FakePhoneAuth(sendError: _taken));
      await _enterNumber(tester, '791234567');
      await _sendCode(tester);
      expect(find.text('That number is already used by another account.'), findsOneWidget);
    });
  });

  group('Where phone sign-in is offered', () {
    testWidgets('not while it is switched off', (tester) async {
      await pumpScreen(tester, const SignInScreen(), overrides: await TestDeps().overrides());
      await tester.pumpAndSettle();
      expect(find.text('Continue with a phone number'), findsNothing);
    });

    testWidgets('on sign-in once it is switched on', (tester) async {
      await pumpScreen(tester, const SignInScreen(), overrides: await TestDeps().overrides(phoneSignIn: true));
      await tester.pumpAndSettle();
      expect(find.text('Continue with a phone number'), findsOneWidget);
    });

    testWidgets('on sign-up once it is switched on', (tester) async {
      await pumpScreen(tester, const SignUpScreen(), overrides: await TestDeps().overrides(phoneSignIn: true));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Sign up with a phone number'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sign up with a phone number'), findsOneWidget);
    });

    testWidgets('Profile shows the sign-in number', (tester) async {
      const withPhone = User(
        id: '22222222-2222-4222-8222-222222222222',
        appMetadata: {},
        userMetadata: {'full_name': 'Lina Haddad'},
        aud: 'authenticated',
        email: 'lina@example.com',
        phone: '962791234567',
        createdAt: '2026-09-01T00:00:00Z',
      );
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: await TestDeps().overrides(user: withPhone, phoneSignIn: true),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sign-in phone number'), 300);
      expect(find.textContaining('+962 79 123 4567'), findsWidgets);
    });

    testWidgets('Profile offers to add a number to an account without one', (tester) async {
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: await TestDeps().overrides(user: fakeUser(), phoneSignIn: true),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Add one to sign in with a code'), 300);
      expect(find.text('Sign-in phone number'), findsOneWidget);
    });

    testWidgets('an account made by phone, with no email, shows its number', (tester) async {
      const phoneOnly = User(
        id: '33333333-3333-4333-8333-333333333333',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        phone: '962791234567',
        createdAt: '2026-09-01T00:00:00Z',
      );
      await pumpScreen(tester, const ProfileScreen(), overrides: await TestDeps().overrides(user: phoneOnly));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('+962 79 123 4567'), findsOneWidget, reason: 'the account card, in place of an email');
      expect(find.byIcon(Icons.person_rounded), findsOneWidget, reason: 'no initials to show');
    });
  });

  group('Layout', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('both steps fit a phone with large text [$lang]', (tester) async {
        await pumpScreen(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: const PhoneAuthScreen(kind: PhoneAuthKind.signUp),
            ),
          ),
          overrides: [...await TestDeps().overrides(), authServiceProvider.overrideWithValue(_FakePhoneAuth())],
          lang: lang,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
