import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, non-sensitive device settings. Nothing here is a secret: the session
/// lives in the keystore (SecureSessionStorage), never in preferences.
///
/// Overridden in main() with the instance loaded before the first frame, so
/// reads are synchronous everywhere else.
final preferencesProvider = Provider<Preferences>((ref) => throw UnimplementedError('override in bootstrap'));

class Preferences {
  Preferences(this._prefs);
  final SharedPreferences _prefs;

  static const _onboarded = 'akarat.onboarded';
  static const _pendingLink = 'akarat.pendingLink';
  static const _lang = 'akarat.lang';
  static const _theme = 'akarat.theme';
  static const _homeCity = 'akarat.homeCity';
  static const _homeDeal = 'akarat.homeDeal';
  static const _mapLayer = 'akarat.mapLayer';
  static const _localFavorites = 'akarat.favorites.local';
  static const _listingDraft = 'akarat.listingDraft';
  static const _hiddenOwners = 'akarat.hiddenOwners';

  bool get onboarded => _prefs.getBool(_onboarded) ?? false;

  /// A random id for this install, made on first use. Counts the app in the
  /// admin panel's "on Akarat.ai right now" and de-duplicates listing views;
  /// it identifies the install, not the person (see Activity).
  String get sessionId {
    final existing = _prefs.getString('akarat.sid');
    if (existing != null && existing.length >= 8) return existing;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    unawaited(_prefs.setString('akarat.sid', id));
    return id;
  }

  /// The file name of the profile picture account [userId] chose on this
  /// phone (ProfilePhotos), or null.
  String? profilePhoto(String userId) => _prefs.getString('akarat.profilePhoto.$userId');
  Future<void> setProfilePhoto(String userId, String? fileName) => fileName == null
      ? _prefs.remove('akarat.profilePhoto.$userId')
      : _prefs.setString('akarat.profilePhoto.$userId', fileName);

  /// Advertisers this reader chose to hide (Hide this advertiser, on a
  /// listing): their account ids. Their listings are left out everywhere.
  List<String> get hiddenOwners => _prefs.getStringList(_hiddenOwners) ?? const [];
  Future<void> setHiddenOwners(List<String> ids) =>
      ids.isEmpty ? _prefs.remove(_hiddenOwners) : _prefs.setStringList(_hiddenOwners, ids);
  Future<void> setOnboarded() => _prefs.setBool(_onboarded, true);

  /// An account being connected in the browser (`facebook`, `apple`), so the app can
  /// say so when Supabase sends the reader back. Kept on the device in case
  /// the system closes the app while the browser is open.
  String? get pendingLink => _prefs.getString(_pendingLink);
  Future<void> setPendingLink(String? provider) =>
      provider == null ? _prefs.remove(_pendingLink) : _prefs.setString(_pendingLink, provider);

  /// Whether a guided tour ('explore', 'map', 'listing', 'property') has
  /// been finished or skipped on this device.
  bool tourSeen(String id) => _prefs.getBool('akarat.tour.$id') ?? false;
  Future<void> setTourSeen(String id) => _prefs.setBool('akarat.tour.$id', true);

  /// The step a tour was on when the app closed, to pick up from there.
  int tourStep(String id) => _prefs.getInt('akarat.tour.$id.step') ?? 0;
  Future<void> setTourStep(String id, int step) => _prefs.setInt('akarat.tour.$id.step', step);
  Future<void> clearTourStep(String id) => _prefs.remove('akarat.tour.$id.step');

  /// Whether this device has given the account [userId] its welcome tour.
  /// Per account, so a second person signing up on the phone is welcomed too.
  bool welcomed(String userId) => _prefs.getBool('akarat.tour.welcome.$userId') ?? false;
  Future<void> setWelcomed(String userId) => _prefs.setBool('akarat.tour.welcome.$userId', true);

  /// 'en' | 'ar' | null when the reader never chose.
  String? get lang => _prefs.getString(_lang);
  Future<void> setLang(String lang) => _prefs.setString(_lang, lang);

  /// 'system' | 'light' | 'dark'
  String get theme => _prefs.getString(_theme) ?? 'system';
  Future<void> setTheme(String mode) => _prefs.setString(_theme, mode);

  String? get homeCity => _prefs.getString(_homeCity);
  Future<void> setHomeCity(String? id) => id == null ? _prefs.remove(_homeCity) : _prefs.setString(_homeCity, id);

  String get homeDeal => _prefs.getString(_homeDeal) ?? 'sale';
  Future<void> setHomeDeal(String deal) => _prefs.setString(_homeDeal, deal);

  /// The map or satellite view, remembered across maps and launches.
  String get mapLayer => _prefs.getString(_mapLayer) ?? 'map';
  Future<void> setMapLayer(String layer) => _prefs.setString(_mapLayer, layer);

  /// Listing ids saved on this device: for guests, and as the fallback when
  /// the account cannot store favourites yet (migration 0014 not applied).
  List<String> get localFavorites => _prefs.getStringList(_localFavorites) ?? const [];
  Future<void> setLocalFavorites(List<String> ids) => _prefs.setStringList(_localFavorites, ids);

  /// An unfinished new listing, so leaving the form never loses it.
  Map<String, Object?>? get listingDraft {
    final raw = _prefs.getString(_listingDraft);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> setListingDraft(Map<String, Object?>? draft) =>
      draft == null ? _prefs.remove(_listingDraft) : _prefs.setString(_listingDraft, jsonEncode(draft));
}
