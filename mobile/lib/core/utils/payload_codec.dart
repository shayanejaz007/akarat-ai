import 'dart:convert';
import 'dart:io' show gzip;

/// The `payload_gz` column format shared with the website.
///
/// A listing's indexed facts (price, beds, city, status) are real columns.
/// Everything bulky and free-form — both descriptions, amenities, media and
/// contact preferences — is JSON, gzipped, base64'd and stored in one text
/// column with a prefix naming the encoding:
///
/// * `gz:<base64 of gzip(json)>` — what every current client writes;
/// * `raw:<base64 of json>` — written by browsers without CompressionStream;
/// * bare JSON — tolerated on read, as lib/listing-server.ts does.
///
/// Mirrors packPayload / unpackPayload in lib/supabase.js, so a listing saved
/// from the app reads on the website and the other way round.
class PayloadCodec {
  const PayloadCodec._();

  static PackedPayload pack(Map<String, Object?> payload) {
    final raw = utf8.encode(jsonEncode(payload));
    final gz = gzip.encode(raw);
    return PackedPayload(
      payloadGz: 'gz:${base64.encode(gz)}',
      // Byte counts, matching the website: payload_bytes is the compressed
      // size, raw_bytes the JSON before compression.
      payloadBytes: gz.length,
      rawBytes: raw.length,
    );
  }

  /// Never throws. A listing whose payload cannot be read still renders its
  /// columns rather than taking a whole list down with it.
  static Map<String, Object?> unpack(String? stored) {
    if (stored == null || stored.isEmpty) return const {};
    try {
      final String json;
      if (stored.startsWith('gz:')) {
        json = utf8.decode(gzip.decode(base64.decode(stored.substring(3))));
      } else if (stored.startsWith('raw:')) {
        json = utf8.decode(base64.decode(stored.substring(4)));
      } else if (stored.trimLeft().startsWith('{')) {
        json = stored;
      } else {
        // Legacy rows stored base64 gzip with no prefix.
        json = utf8.decode(gzip.decode(base64.decode(stored)));
      }
      final decoded = jsonDecode(json);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on Object {
      return const {};
    }
  }
}

class PackedPayload {
  const PackedPayload({required this.payloadGz, required this.payloadBytes, required this.rawBytes});

  final String payloadGz;
  final int payloadBytes;
  final int rawBytes;

  /// The three columns as PostgREST expects them. There is deliberately no
  /// `ratio`: the table has no such column and naming one fails the write.
  Map<String, Object?> toColumns() => {'payload_gz': payloadGz, 'payload_bytes': payloadBytes, 'raw_bytes': rawBytes};
}
