import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../models/listing.dart';
import '../services/supabase_providers.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) => MediaRepository(ref.watch(supabaseClientProvider)));

/// Limits shared with the website (lib/supabase.js) and the bucket itself
/// (migrations 0006 and 0007). The bucket enforces its own copy server-side;
/// these exist so an owner hears about a problem while picking, not after
/// filling in the whole form.
class MediaLimits {
  const MediaLimits._();
  static const bucket = 'listing-photos';
  static const maxFiles = 8;
  static const maxVideos = 2;
  static const maxImageBytes = 6 * 1024 * 1024;
  static const maxVideoBytes = 50 * 1024 * 1024;

  /// The website downscales to a 1600 px long edge at JPEG quality 0.85;
  /// image_picker does the same natively before the file reaches the app.
  static const maxEdge = 1600.0;
  static const jpegQuality = 85;

  static const imageTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'avif': 'image/avif',
  };
  static const videoTypes = {'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime', 'm4v': 'video/mp4'};

  static String extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  /// The MIME type the bucket will accept for [path], or null if none.
  static String? contentTypeFor(String path, {required bool video}) =>
      (video ? videoTypes : imageTypes)[extensionOf(path)];
}

class MediaRepository {
  MediaRepository(this._db);
  final SupabaseClient _db;
  final _random = Random.secure();

  /// Uploads one file under `<owner_id>/`, the only prefix the storage policy
  /// lets this user write, and returns what the listing payload stores.
  Future<MediaItem> upload(File file, {required bool video}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AppFailure(FailureKind.unauthorized, detail: 'Not signed in');
    final contentType = MediaLimits.contentTypeFor(file.path, video: video);
    if (contentType == null) throw AppFailure(FailureKind.validation, detail: 'type ${file.path}');
    final size = await file.length();
    if (size > (video ? MediaLimits.maxVideoBytes : MediaLimits.maxImageBytes)) {
      throw AppFailure(FailureKind.validation, detail: 'size $size');
    }

    var ext = MediaLimits.extensionOf(file.path);
    if (ext == 'jpeg') ext = 'jpg';
    final suffix = List.generate(6, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)]).join();
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}-$suffix.$ext';
    try {
      await _db.storage
          .from(MediaLimits.bucket)
          .upload(
            path,
            file,
            fileOptions: FileOptions(cacheControl: '31536000', upsert: false, contentType: contentType),
            retryAttempts: 2,
          );
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
    final url = _db.storage.from(MediaLimits.bucket).getPublicUrl(path);
    return MediaItem(url: url, path: path, kind: video ? MediaKind.video : MediaKind.image);
  }

  /// Best effort: an object that is already gone is not an error worth
  /// showing. Only paths under the caller's own folder are ever attempted.
  Future<void> remove(List<String> paths) async {
    final uid = _db.auth.currentUser?.id;
    final own = paths.where((p) => uid != null && p.startsWith('$uid/')).toList();
    if (own.isEmpty) return;
    try {
      await _db.storage.from(MediaLimits.bucket).remove(own);
    } on Object {
      // Orphaned files cost storage, not correctness.
    }
  }
}
