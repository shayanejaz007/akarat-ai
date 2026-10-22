import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'preferences.dart';
import 'supabase_providers.dart';

/// A profile picture kept on this phone only: never uploaded, never seen by
/// anyone else, not on the website. One per account, by its id, so another
/// account signed in on the same phone keeps its own.
///
/// The file lives in the app's own folder and its name in preferences. Each
/// new picture gets a new name, so nothing shows a cached older one.
class ProfilePhotos {
  ProfilePhotos(this._prefs, this._folder);
  final Preferences _prefs;

  /// The app's own folder (getApplicationSupportDirectory in the app).
  final Future<Directory> Function() _folder;

  Future<Directory> _dir() async {
    final dir = Directory('${(await _folder()).path}/profile_photos');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// The picture's bytes for [userId], or null.
  Future<Uint8List?> load(String userId) async {
    final name = _prefs.profilePhoto(userId);
    if (name == null) return null;
    final file = File('${(await _dir()).path}/$name');
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  /// Keeps [picked] as [userId]'s picture, in place of any earlier one.
  Future<void> save(String userId, XFile picked) async {
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('Empty picture');
    final dir = await _dir();
    final name = '$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
    File('${dir.path}/$name').writeAsBytesSync(bytes, flush: true);
    final previous = _prefs.profilePhoto(userId);
    await _prefs.setProfilePhoto(userId, name);
    if (previous != null && previous != name) _delete(dir, previous);
  }

  /// Removes [userId]'s picture, from preferences and from the phone.
  Future<void> remove(String userId) async {
    final name = _prefs.profilePhoto(userId);
    await _prefs.setProfilePhoto(userId, null);
    if (name != null) _delete(await _dir(), name);
  }

  static void _delete(Directory dir, String name) {
    final file = File('${dir.path}/$name');
    if (file.existsSync()) file.deleteSync();
  }
}

final profilePhotosProvider = Provider<ProfilePhotos>(
  (ref) => ProfilePhotos(ref.watch(preferencesProvider), getApplicationSupportDirectory),
);

/// The signed-in account's picture on this phone, or null. Invalidate it
/// after a change.
final profilePhotoProvider = FutureProvider.autoDispose<Uint8List?>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return null;
  return ref.watch(profilePhotosProvider).load(userId);
});

/// Picks one picture, small enough for an avatar (720 px, JPEG): the photo
/// library or the camera. Null when the person backs out. Replaced in tests.
final profilePhotoPickerProvider = Provider<Future<XFile?> Function(ImageSource source)>((ref) {
  final picker = ImagePicker();
  return (source) => picker.pickImage(
    source: source,
    maxWidth: 720,
    maxHeight: 720,
    imageQuality: 85,
    preferredCameraDevice: CameraDevice.front,
  );
});
