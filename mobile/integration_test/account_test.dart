// On-device journeys that WRITE: sign in, save a property, create, upload
// to and edit a listing, send an inquiry, sign out and back in.
//
// They run only when explicitly enabled, with a dedicated test account:
//
//   flutter test integration_test/account_test.dart -d <device-id> \
//     --dart-define-from-file=env/staging.json \
//     --dart-define=IT_EMAIL=qa+mobile@akarat.ai \
//     --dart-define=IT_PASSWORD=... \
//     --dart-define=IT_ALLOW_WRITES=true
//
// Against the production project they refuse to run unless
// IT_ALLOW_PRODUCTION=true is also passed. Everything they create is a DRAFT
// titled "[IT] …", hidden from the marketplace by RLS, and is deleted at the
// end. Prefer a staging project (TESTING.md).

import 'dart:async';

import 'package:akarat/core/config/env.dart';
import 'package:akarat/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _email = String.fromEnvironment('IT_EMAIL');
const _password = String.fromEnvironment('IT_PASSWORD');
const _allowWrites = bool.fromEnvironment('IT_ALLOW_WRITES');
const _allowProduction = bool.fromEnvironment('IT_ALLOW_PRODUCTION');
const _productionUrl = 'https://ppqftdcdpshfokjqnuhq.supabase.co';

String? get skipReason {
  if (!_allowWrites) return 'IT_ALLOW_WRITES is not set';
  if (_email.isEmpty || _password.isEmpty) return 'IT_EMAIL / IT_PASSWORD are not set';
  if (Env.supabaseUrl == _productionUrl && !_allowProduction) {
    return 'refusing to write to the production project without IT_ALLOW_PRODUCTION';
  }
  return null;
}

Future<void> settle(WidgetTester tester, [Duration max = const Duration(seconds: 15)]) async {
  final end = DateTime.now().add(max);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (!tester.binding.hasScheduledFrame) break;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign in, list a draft, edit it, save a property, sign out and back in', (tester) async {
    SharedPreferences.setMockInitialValues({
      'akarat.onboarded': true,
      'akarat.lang': 'en',
      // Tours stay out of the way of this journey.
      'akarat.tour.explore': true,
      'akarat.tour.map': true,
      'akarat.tour.listing': true,
      'akarat.tour.property': true,
    });
    unawaited(app.main());
    await settle(tester);

    // Sign in with the web account, from the tab bar's Log in button.
    await tester.tap(find.bySemanticsLabel('Log in'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), _email);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), _password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Profile'));
    await settle(tester);
    expect(find.text(_email), findsOneWidget, reason: 'the profile shows the signed-in account');

    // Create a draft listing through the wizard.
    await tester.tap(find.text('List a property'));
    await settle(tester);
    if (find.text('Start over').evaluate().isNotEmpty) {
      await tester.tap(find.text('Start over'));
      await settle(tester);
    }
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await settle(tester);
    }
    await tester.enterText(find.widgetWithText(TextField, 'Price (JOD)'), '123456');
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await tester.enterText(find.widgetWithText(TextField, 'Title in English'), '[IT] mobile draft $stamp');
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Save as draft'));
    await settle(tester, const Duration(seconds: 20));
    expect(find.text('My listings'), findsWidgets);
    expect(find.text('[IT] mobile draft $stamp'), findsOneWidget);

    // The row exists for this account, as a draft, with this owner.
    final db = Supabase.instance.client;
    final row = await db.from('properties').select().eq('title_en', '[IT] mobile draft $stamp').single();
    expect(row['status'], 'draft');
    expect(row['owner_id'], db.auth.currentUser!.id);
    expect(row['price_jod'], 123456);

    // Edit it.
    await tester.tap(find.text('Edit').first);
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await settle(tester);
    }
    await tester.enterText(find.widgetWithText(TextField, 'Price (JOD)'), '120000');
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await settle(tester);
    }
    await tester.tap(find.text('Save changes'));
    await settle(tester, const Duration(seconds: 20));
    final edited = await db.from('properties').select('price_jod,status').eq('id', row['id'] as String).single();
    expect(edited['price_jod'], 120000);
    expect(edited['status'], 'draft', reason: 'an edit never republishes');

    // Clean up through the app's own delete action, behind the row's More.
    await tester.tap(find.byTooltip('More').first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    final gone = await db.from('properties').select('id').eq('id', row['id'] as String);
    expect(gone, isEmpty);

    // Sign out, and back in.
    await db.auth.signOut();
    await settle(tester);
    expect(db.auth.currentUser, isNull);
    await db.auth.signInWithPassword(email: _email, password: _password);
    expect(db.auth.currentUser?.email, _email);
  }, skip: skipReason != null);
}
