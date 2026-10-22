import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every error the UI can show, reduced to a kind. Screens map the kind to a
/// localized sentence; raw database or HTTP text never reaches a reader,
/// because it names tables, constraints and hosts and tells them nothing.
enum FailureKind {
  network,
  timeout,
  rateLimited,
  unauthorized,
  forbidden,
  notFound,

  /// The database answered with a schema it does not have (a migration has
  /// not run). Carries [AppFailure.detail] for logs, never for display.
  schemaMissing,

  /// A foreign key: an area the database has never heard of.
  unknownArea,
  storageMissing,
  validation,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, {this.detail, this.status});

  final FailureKind kind;

  /// Diagnostic text for debugging. Never rendered.
  final String? detail;
  final int? status;

  bool get isOffline => kind == FailureKind.network;

  @override
  String toString() => 'AppFailure($kind${status != null ? ', $status' : ''}${detail != null ? ': $detail' : ''})';

  static AppFailure from(Object error) {
    if (error is AppFailure) return error;
    if (error is SocketException || error is HandshakeException) {
      return AppFailure(FailureKind.network, detail: error.toString());
    }
    if (error is TimeoutException) return AppFailure(FailureKind.timeout, detail: error.toString());
    if (error is DioException) return _fromDio(error);
    if (error is PostgrestException) return _fromPostgrest(error);
    if (error is StorageException) {
      final msg = error.message.toLowerCase();
      final status = int.tryParse(error.statusCode ?? '');
      if (msg.contains('bucket') && msg.contains('not found')) {
        return AppFailure(FailureKind.storageMissing, detail: error.message, status: status);
      }
      if (status == 413 || msg.contains('too large') || msg.contains('size')) {
        return AppFailure(FailureKind.validation, detail: error.message, status: status);
      }
      if (status == 401 || status == 403) {
        return AppFailure(FailureKind.forbidden, detail: error.message, status: status);
      }
      return AppFailure(FailureKind.unknown, detail: error.message, status: status);
    }
    if (error is AuthException) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 429) return AppFailure(FailureKind.rateLimited, detail: error.message, status: status);
      return AppFailure(FailureKind.unauthorized, detail: error.message, status: status);
    }
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('ClientException')) {
      return AppFailure(FailureKind.network, detail: text);
    }
    // Readers only ever see "something went wrong"; developers see why.
    if (kDebugMode) debugPrint('AppFailure.unknown: $text');
    return AppFailure(FailureKind.unknown, detail: text);
  }

  static AppFailure _fromDio(DioException e) {
    final status = e.response?.statusCode;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        return AppFailure(FailureKind.timeout, detail: e.message);
      case DioExceptionType.connectionError:
        return AppFailure(FailureKind.network, detail: e.message);
      case DioExceptionType.badResponse:
        return AppFailure(_fromStatus(status), detail: e.message, status: status);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        if (e.error is SocketException) return AppFailure(FailureKind.network, detail: e.message);
        return AppFailure(FailureKind.unknown, detail: e.message, status: status);
    }
  }

  static AppFailure _fromPostgrest(PostgrestException e) {
    final code = e.code ?? '';
    final msg = e.message;
    // 23503: foreign key. The only one the listing form can hit is an area or
    // city the cities/neighborhoods tables do not have (migration 0009).
    if (code == '23503') return AppFailure(FailureKind.unknownArea, detail: msg);
    // PGRST204/205/42703: a column or table the schema cache does not have.
    if (code == 'PGRST204' || code == 'PGRST205' || code == '42P01' || code == '42703') {
      return AppFailure(FailureKind.schemaMissing, detail: '$code $msg');
    }
    if (code == '42501') return AppFailure(FailureKind.forbidden, detail: msg);
    if (code == 'PGRST301' || code == 'PGRST302') return AppFailure(FailureKind.unauthorized, detail: msg);
    if (code == 'PGRST116') return AppFailure(FailureKind.notFound, detail: msg);
    final status = int.tryParse(code);
    if (status != null) return AppFailure(_fromStatus(status), detail: msg, status: status);
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
      return AppFailure(FailureKind.network, detail: msg);
    }
    return AppFailure(FailureKind.unknown, detail: '$code $msg');
  }

  static FailureKind _fromStatus(int? status) => switch (status) {
    401 => FailureKind.unauthorized,
    403 => FailureKind.forbidden,
    404 => FailureKind.notFound,
    408 || 504 => FailureKind.timeout,
    429 => FailureKind.rateLimited,
    _ => FailureKind.unknown,
  };
}
