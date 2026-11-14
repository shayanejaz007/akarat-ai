import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../shared/services/supabase_providers.dart';
import 'services_models.dart';

final servicesRepositoryProvider = Provider<ServicesRepository>(
  (ref) => ServicesRepository(ref.watch(supabaseClientProvider)),
);

/// Services (supabase/migrations/0024_services.sql), with the publishable
/// key, the way the website does it. service_requests has no table access
/// at all: a request is only written or read through the functions below,
/// which check who is asking. Photos go to a private bucket, each person
/// into their own folder.
class ServicesRepository {
  ServicesRepository(this._db);
  final SupabaseClient _db;
  static const bucket = 'service-photos';
  static const maxPhotos = 6;
  static const maxPhotoBytes = 8 * 1024 * 1024;
  static const photoTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  /// The categories that are switched on, in the admin's order.
  Future<List<ServiceCategory>> categories() async {
    try {
      final rows = await _db
          .from('service_categories')
          .select('id,name_en,name_ar,examples_en,examples_ar,icon,sort,custom')
          .order('sort')
          .order('name_en');
      return [for (final r in rows) ServiceCategory.fromRow(Map<String, Object?>.from(r))];
    } on Object catch (e) {
      throw _refusal(e) ?? AppFailure.from(e);
    }
  }

  /// Uploads a request's photos and returns their paths. Each is named after
  /// the submission's [token] and its place in the list, so sending the same
  /// submission again finds the files already there instead of adding more.
  Future<List<String>> uploadPhotos(List<File> files, String token, {void Function(int i, int n)? onProgress}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const ServiceRefusal('sign_in');
    if (files.length > maxPhotos) throw const ServiceRefusal('photo_count');
    final out = <String>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final dot = file.path.lastIndexOf('.');
      var ext = dot < 0 ? '' : file.path.substring(dot + 1).toLowerCase();
      final type = photoTypes[ext];
      if (type == null) throw const ServiceRefusal('photo_type');
      if (await file.length() > maxPhotoBytes) throw const ServiceRefusal('photo_size');
      if (ext == 'jpeg') ext = 'jpg';
      onProgress?.call(i + 1, files.length);
      final path = '$uid/$token-$i.$ext';
      try {
        await _db.storage
            .from(bucket)
            .upload(
              path,
              file,
              fileOptions: FileOptions(cacheControl: '3600', upsert: false, contentType: type),
              retryAttempts: 2,
            );
      } on StorageException catch (e) {
        // Already there: this is the same submission sent again.
        if (e.statusCode != '409' && !RegExp('exists|duplicate', caseSensitive: false).hasMatch(e.message)) {
          throw _refusal(e) ?? AppFailure.from(e);
        }
      } on Object catch (e) {
        throw _refusal(e) ?? AppFailure.from(e);
      }
      out.add(path);
    }
    return out;
  }

  /// Sends a request. The same [fields]['client_token'] again returns the
  /// first request (duplicate: true) instead of making a second one.
  Future<ServiceCreated> create(Map<String, Object?> fields) async {
    try {
      final r = await _db.rpc<Map<String, dynamic>>('create_service_request', params: {'p': fields});
      return (id: '${r['id']}', ref: '${r['ref']}', duplicate: r['duplicate'] == true);
    } on Object catch (e) {
      throw _refusal(e) ?? AppFailure.from(e);
    }
  }

  /// The signed-in person's requests, newest first, with the updates meant for them.
  Future<List<ServiceRequest>> mine() async {
    if (_db.auth.currentUser == null) return const [];
    try {
      final rows = await _db.rpc<List<dynamic>>('my_service_requests');
      return [
        for (final r in rows)
          if (r is Map) ServiceRequest.fromRow(Map<String, Object?>.from(r)),
      ];
    } on Object catch (e) {
      throw _refusal(e) ?? AppFailure.from(e);
    }
  }

  /// Allowed until work begins.
  Future<void> cancel(String id, {String? reason}) async {
    try {
      await _db.rpc<Object?>(
        'cancel_service_request',
        params: {'p_id': id, 'p_reason': (reason?.trim().isEmpty ?? true) ? null : reason!.trim()},
      );
    } on Object catch (e) {
      throw _refusal(e) ?? AppFailure.from(e);
    }
  }

  /// Links to the person's own photos, good for an hour.
  Future<Map<String, String>> photoUrls(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final signed = await _db.storage.from(bucket).createSignedUrlsResult(paths, 3600);
      // A photo that is gone (removed by its owner) is simply left out.
      return {
        for (final s in signed)
          if (s is SignedUrlSuccess) s.path: s.signedUrl,
      };
    } on Object {
      return const {};
    }
  }

  /// A fresh token for one submission.
  static String newToken() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// A refusal from the database the form can explain, or null.
  static ServiceRefusal? _refusal(Object e) {
    final text = switch (e) {
      PostgrestException(:final message, :final code) => '$message ${code ?? ''}',
      StorageException(:final message, :final statusCode) => '$message ${statusCode ?? ''}',
      _ => '$e',
    };
    final m = RegExp('(invalid:[a-z_]+|too_many|sign_in|not_allowed|not_found)').firstMatch(text);
    if (m != null) return ServiceRefusal(m[1]!);
    if (RegExp('PGRST202|PGRST205|42883|42P01|Bucket not found|Could not find the function').hasMatch(text)) {
      return const ServiceRefusal('not_set_up');
    }
    if (RegExp('mime type', caseSensitive: false).hasMatch(text)) return const ServiceRefusal('photo_type');
    if (RegExp('maximum allowed size|too large', caseSensitive: false).hasMatch(text)) {
      return const ServiceRefusal('photo_size');
    }
    return null;
  }
}
