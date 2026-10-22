import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session in the platform keystore (iOS Keychain, Android
/// Keystore-backed encryption) instead of plain SharedPreferences.
///
/// The session holds a refresh token, which is as good as a password until it
/// is revoked. Supabase's default storage writes it to an unencrypted XML file
/// on Android and a plist on iOS; this does not.
///
/// `first_unlock` on iOS so a token refresh still works when the app wakes in
/// the background after the device has been unlocked once.
const _secure = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock));

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _key = 'akarat.supabase.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _read()) != null;

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<void> removePersistedSession() async {
    try {
      await _secure.delete(key: _key);
    } on Object {
      // A keystore that cannot delete cannot read either; nothing to leak.
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) => _secure.write(key: _key, value: persistSessionString);

  /// A keystore that fails to decrypt (restored backup, changed lock screen)
  /// is treated as signed out rather than crashing the app on launch.
  Future<String?> _read() async {
    try {
      return await _secure.read(key: _key);
    } on Object {
      return null;
    }
  }
}

/// Holds the PKCE code verifier between starting a sign-in in the browser
/// and the deep link that finishes it.
class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage();

  static const _prefix = 'akarat.pkce.';

  @override
  Future<String?> getItem({required String key}) async {
    try {
      return await _secure.read(key: '$_prefix$key');
    } on Object {
      return null;
    }
  }

  @override
  Future<void> setItem({required String key, required String value}) =>
      _secure.write(key: '$_prefix$key', value: value);

  @override
  Future<void> removeItem({required String key}) async {
    try {
      await _secure.delete(key: '$_prefix$key');
    } on Object {
      // Already gone.
    }
  }
}
