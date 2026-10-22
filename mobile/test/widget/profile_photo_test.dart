import 'dart:convert';
import 'dart:io';

import 'package:akarat/app/localization/gen/app_localizations.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:akarat/shared/services/profile_photos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// A real one-pixel PNG, so the avatar can draw it.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

const _me = '22222222-2222-4222-8222-222222222222';

late Directory _folder;

/// Profile, signed in, with the picture kept in a scratch folder and a
/// picker that answers with [pick] (or throws [error]).
Future<List<ImageSource>> _pump(
  WidgetTester tester, {
  XFile? pick,
  Object? error,
  Map<String, Object> prefs = TestDeps.seen,
}) async {
  final asked = <ImageSource>[];
  await pumpScreen(
    tester,
    const ProfileScreen(),
    overrides: [
      ...await TestDeps().overrides(user: fakeUser(), prefs: prefs),
      profilePhotosProvider.overrideWith((ref) => ProfilePhotos(ref.watch(preferencesProvider), () async => _folder)),
      profilePhotoPickerProvider.overrideWithValue((source) async {
        asked.add(source);
        if (error != null) throw error;
        return pick;
      }),
    ],
  );
  await tester.pumpAndSettle();
  return asked;
}

Future<void> _openSheet(WidgetTester tester) async {
  // The camera badge on the picture: the picture is the button.
  await tester.tap(find.byIcon(Icons.photo_camera_rounded));
  await tester.pumpAndSettle();
}

List<FileSystemEntity> _files() {
  final dir = Directory('${_folder.path}/profile_photos');
  return dir.existsSync() ? dir.listSync() : const [];
}

ImageProvider? _shown(WidgetTester tester) =>
    tester.widget<CircleAvatar>(find.byType(CircleAvatar).first).foregroundImage;

void main() {
  setUp(() => _folder = Directory.systemTemp.createTempSync('akarat_photo_test'));
  tearDown(() => _folder.deleteSync(recursive: true));

  testWidgets('a tap on the picture offers photos or the camera, and says it stays on the phone', (tester) async {
    await _pump(tester);
    await _openSheet(tester);
    expect(find.text(_en.profilePhotoChoose), findsOneWidget);
    expect(find.text(_en.profilePhotoTake), findsOneWidget);
    expect(find.text(_en.profilePhotoNote), findsOneWidget);
    expect(find.text(_en.profilePhotoRemove), findsNothing, reason: 'nothing to remove yet');
  });

  testWidgets('a chosen photo is kept on the phone, shown, and said so', (tester) async {
    final asked = await _pump(
      tester,
      pick: XFile.fromData(_png, name: 'me.png', mimeType: 'image/png'),
    );
    expect(_shown(tester), isNull, reason: 'initials before');
    await _openSheet(tester);
    await tester.tap(find.text(_en.profilePhotoChoose));
    await tester.pumpAndSettle();
    expect(asked, [ImageSource.gallery]);
    expect(_files(), hasLength(1));
    expect(find.text(_en.profilePhotoUpdated), findsOneWidget);
    expect(_shown(tester), isA<MemoryImage>());
  });

  testWidgets('the camera, when chosen, is asked for', (tester) async {
    final asked = await _pump(tester, pick: XFile.fromData(_png, name: 'me.png'));
    await _openSheet(tester);
    await tester.tap(find.text(_en.profilePhotoTake));
    await tester.pumpAndSettle();
    expect(asked, [ImageSource.camera]);
    expect(_files(), hasLength(1));
  });

  testWidgets('no camera: said plainly, and nothing changes', (tester) async {
    await _pump(tester, error: PlatformException(code: 'no_available_camera'));
    await _openSheet(tester);
    await tester.tap(find.text(_en.profilePhotoTake));
    await tester.pumpAndSettle();
    expect(find.text(_en.profilePhotoNoCamera), findsOneWidget);
    expect(_files(), isEmpty);
  });

  testWidgets('backing out of the picker changes nothing and says nothing', (tester) async {
    await _pump(tester);
    await _openSheet(tester);
    await tester.tap(find.text(_en.profilePhotoChoose));
    await tester.pumpAndSettle();
    expect(_files(), isEmpty);
    expect(find.text(_en.profilePhotoUpdated), findsNothing);
  });

  testWidgets('remove takes it off the phone', (tester) async {
    await _pump(tester, pick: XFile.fromData(_png, name: 'me.png'));
    await _openSheet(tester);
    await tester.tap(find.text(_en.profilePhotoChoose));
    await tester.pumpAndSettle();
    expect(_files(), hasLength(1));
    await _openSheet(tester);
    await tester.tap(find.text(_en.profilePhotoRemove));
    await tester.pumpAndSettle();
    expect(_files(), isEmpty);
    expect(find.text(_en.profilePhotoRemoved), findsOneWidget);
    expect(_shown(tester), isNull);
  });

  test('a new picture replaces the old file, and each account keeps its own', () async {
    SharedPreferences.setMockInitialValues({});
    final photos = ProfilePhotos(Preferences(await SharedPreferences.getInstance()), () async => _folder);
    await photos.save(_me, XFile.fromData(_png, name: 'a.png'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await photos.save(_me, XFile.fromData(_png, name: 'b.png'));
    expect(_files(), hasLength(1), reason: 'the first one is gone');
    expect(await photos.load(_me), _png);
    expect(await photos.load('33333333-3333-4333-8333-333333333333'), isNull, reason: 'another account has none');
    await photos.remove(_me);
    expect(await photos.load(_me), isNull);
    expect(_files(), isEmpty);
  });

  test('an empty picture is refused', () async {
    SharedPreferences.setMockInitialValues({});
    final photos = ProfilePhotos(Preferences(await SharedPreferences.getInstance()), () async => _folder);
    await expectLater(photos.save(_me, XFile.fromData(Uint8List(0), name: 'empty.png')), throwsFormatException);
    expect(_files(), isEmpty);
  });
}
