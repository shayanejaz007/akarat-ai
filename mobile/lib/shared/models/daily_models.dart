import '../../core/utils/payload_codec.dart';
import 'listing.dart';

/// A night as the database stores it: a plain calendar date, no time, no
/// zone. Built from the parts so a time zone never moves a day.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? parseDay(Object? v) {
  if (v is! String || v.length < 10) return null;
  final p = v.substring(0, 10).split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  return y == null || m == null || d == null ? null : DateTime(y, m, d);
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Nights between two dates: check-in to check-out. Rounded, because across
/// a daylight-saving change two local midnights are 23 or 25 hours apart.
int nightsBetween(DateTime checkIn, DateTime checkOut) =>
    (dayOnly(checkOut).difference(dayOnly(checkIn)).inHours / 24).round();

/// `booking_requests.status` (0019_daily_rentals.sql).
enum BookingStatus {
  pending,
  approved,
  rejected,
  cancelled,
  confirmed;

  static BookingStatus parse(Object? v) =>
      BookingStatus.values.firstWhere((s) => s.name == v, orElse: () => BookingStatus.pending);
}

/// What an owner, or a renter, can do to a request (booking_respond()).
enum BookingAction { approve, reject, confirm, cancel }

/// A renter asking for dates at a daily rental. Not a reservation: the owner
/// approves (and their phone reaches this renter), then confirms once the two
/// have agreed, which closes the nights.
class BookingRequest {
  const BookingRequest({
    required this.id,
    required this.propertyId,
    required this.ownerId,
    required this.renterId,
    required this.renterName,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.guests,
    required this.nightlyPrice,
    required this.totalPrice,
    required this.status,
    required this.createdAt,
    this.message,
    this.ownerPhone,
    this.responseNote,
    this.closedReason,
    this.cancelledBy,
    this.respondedAt,
    this.titleEn,
    this.titleAr,
    this.coverUrl,
  });

  final String id;
  final String propertyId;
  final String ownerId;
  final String renterId;
  final String renterName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final int guests;
  final int nightlyPrice;
  final int totalPrice;
  final BookingStatus status;
  final DateTime createdAt;
  final String? message;

  /// Set by the database only while approved or confirmed.
  final String? ownerPhone;
  final String? responseNote;

  /// 'dates_taken' when the owner confirmed someone else over these nights.
  final String? closedReason;

  /// 'renter' or 'owner'.
  final String? cancelledBy;
  final DateTime? respondedAt;

  /// The listing, while it is still visible to whoever is reading.
  final String? titleEn;
  final String? titleAr;
  final String? coverUrl;

  bool get isOpen => status == BookingStatus.pending || status == BookingStatus.approved;
  bool get phoneShown =>
      (status == BookingStatus.approved || status == BookingStatus.confirmed) && (ownerPhone ?? '').isNotEmpty;
  bool get datesTaken => closedReason == 'dates_taken';

  /// A request nobody answered before the stay would have started.
  bool expiredOn(DateTime today) => status == BookingStatus.pending && checkIn.isBefore(dayOnly(today));

  String? title(String lang) {
    final en = titleEn?.trim() ?? '';
    final ar = titleAr?.trim() ?? '';
    if (en.isEmpty && ar.isEmpty) return null;
    if (lang == 'ar') return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  static int _int(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

  factory BookingRequest.fromRow(Map<String, Object?> r) {
    final p = r['properties'];
    final prop = p is Map ? Map<String, Object?>.from(p) : null;
    String? cover;
    if (prop?['payload_gz'] case final String gz) {
      final media = ListingPayload.fromJson(PayloadCodec.unpack(gz)).media;
      cover = media.where((m) => !m.isVideo).firstOrNull?.url;
    }
    final checkIn = parseDay(r['check_in']) ?? DateTime(1970);
    final checkOut = parseDay(r['check_out']) ?? checkIn;
    return BookingRequest(
      id: r['id']! as String,
      propertyId: (r['property_id'] as String?) ?? '',
      ownerId: (r['owner_id'] as String?) ?? '',
      renterId: (r['renter_id'] as String?) ?? '',
      renterName: (r['renter_name'] as String?) ?? '',
      checkIn: checkIn,
      checkOut: checkOut,
      nights: r['nights'] == null ? nightsBetween(checkIn, checkOut) : _int(r['nights']),
      guests: _int(r['guests']),
      nightlyPrice: _int(r['nightly_price']),
      totalPrice: _int(r['total_price']),
      status: BookingStatus.parse(r['status']),
      createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      message: r['message'] as String?,
      ownerPhone: r['owner_phone'] as String?,
      responseNote: r['response_note'] as String?,
      closedReason: r['closed_reason'] as String?,
      cancelledBy: r['cancelled_by'] as String?,
      respondedAt: DateTime.tryParse('${r['responded_at']}'),
      titleEn: prop?['title_en'] as String?,
      titleAr: prop?['title_ar'] as String?,
      coverUrl: cover,
    );
  }
}

/// One row of `public.notifications`, written by the database when a request
/// arrives or is answered, or an admin decides on a daily listing.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.data,
    required this.createdAt,
    this.propertyId,
    this.bookingId,
    this.readAt,
  });

  final String id;

  /// booking_new, booking_approved, booking_rejected, booking_confirmed,
  /// booking_cancelled, listing_approved, listing_rejected,
  /// listing_suspended, listing_unapproved.
  final String kind;
  final Map<String, Object?> data;
  final DateTime createdAt;
  final String? propertyId;
  final String? bookingId;
  final DateTime? readAt;

  bool get unread => readAt == null;

  String text(String key) => (data[key] as String?)?.trim() ?? '';

  String title(String lang) {
    final en = text('title_en'), ar = text('title_ar');
    if (lang == 'ar') return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  DateTime? get checkIn => parseDay(data['check_in']);
  DateTime? get checkOut => parseDay(data['check_out']);

  factory AppNotification.fromRow(Map<String, Object?> r) => AppNotification(
    id: r['id']! as String,
    kind: (r['kind'] as String?) ?? '',
    data: r['data'] is Map ? Map<String, Object?>.from(r['data']! as Map) : const {},
    createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    propertyId: r['property_id'] as String?,
    bookingId: r['booking_id'] as String?,
    readAt: DateTime.tryParse('${r['read_at']}'),
  );
}

/// The database said no, for a reason a person can act on. [key] is the
/// exception the migration raises (daily_unavailable, daily_min_nights, …);
/// [n] the number that goes with it, when there is one.
class DailyRefusal implements Exception {
  const DailyRefusal(this.key, {this.n});
  final String key;
  final int? n;

  @override
  String toString() => 'DailyRefusal($key${n != null ? ', $n' : ''})';
}
