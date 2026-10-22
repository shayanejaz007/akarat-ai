import '../../core/utils/payload_codec.dart';
import '../reference/market_data.dart';

/// Text from a row or a payload, or null when the value is anything else.
/// Rows are written by more than one client over time; a stray `false` where
/// text belongs must not take a whole page of results down with it.
String? _str(Object? v) => v is String ? v : null;

/// `deal_type` in Postgres.
enum DealType {
  sale,
  rent;

  static DealType parse(Object? v) => v == 'rent' ? DealType.rent : DealType.sale;
}

/// `listing_status` in Postgres. Must match the enum exactly: an unknown value
/// is rejected by the database with "invalid input value for enum".
enum ListingStatus {
  draft,
  pending,
  active,
  rejected,
  paused,
  sold,
  rented,
  archived;

  static ListingStatus parse(Object? v) =>
      ListingStatus.values.firstWhere((s) => s.name == v, orElse: () => ListingStatus.draft);

  /// What the public read policy (0011_sold_visible.sql) returns.
  static const public = [active, sold, rented];

  /// No longer available, but still shown, greyed and marked.
  bool get isClosed => this == sold || this == rented;
}

/// Added by migration 0010. Null on a row means the column is absent, i.e.
/// that migration has not run on the database the row came from.
enum LocationPrecision {
  exact,
  approximate;

  static LocationPrecision? parse(Object? v) => switch (v) {
    'exact' => exact,
    'approximate' => approximate,
    _ => null,
  };
}

enum MediaKind { image, video }

/// One photo or clip in Storage. Entries written before video existed have no
/// `type` and are images; a URL ending in a video extension is a video
/// whatever it claims, as on the website.
class MediaItem {
  const MediaItem({required this.url, this.path, this.kind = MediaKind.image});

  final String url;

  /// Storage path under the `listing-photos` bucket, `<owner_id>/<file>`.
  final String? path;
  final MediaKind kind;

  bool get isVideo => kind == MediaKind.video;

  static final _videoExt = RegExp(r'\.(mp4|webm|mov|m4v)(\?|#|$)', caseSensitive: false);

  static MediaItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    final isVideo = json['type'] == 'video' || _videoExt.hasMatch(url);
    return MediaItem(
      url: url,
      path: json['path'] is String ? json['path'] as String : null,
      kind: isVideo ? MediaKind.video : MediaKind.image,
    );
  }

  Map<String, Object?> toJson() => {'url': url, 'path': path, 'type': isVideo ? 'video' : 'image'};
}

class ListingContact {
  const ListingContact({this.phone = '', this.whatsapp = false, this.messaging = false});

  final String phone;
  final bool whatsapp;
  final bool messaging;

  bool get hasPhone => phone.trim().isNotEmpty;

  static ListingContact fromJson(Object? json) {
    if (json is! Map) return const ListingContact();
    return ListingContact(
      phone: _str(json['phone'])?.trim() ?? '',
      whatsapp: json['whatsapp'] == true,
      messaging: json['messaging'] == true,
    );
  }

  Map<String, Object?> toJson() => {'phone': phone.trim(), 'whatsapp': whatsapp, 'messaging': messaging};
}

/// The decompressed `payload_gz` blob.
class ListingPayload {
  const ListingPayload({
    this.descriptionEn = '',
    this.descriptionAr = '',
    this.amenities = const [],
    this.media = const [],
    this.contact = const ListingContact(),
  });

  final String descriptionEn;
  final String descriptionAr;
  final List<String> amenities;

  /// Stored under the key `images`, which predates video.
  final List<MediaItem> media;
  final ListingContact contact;

  static ListingPayload fromJson(Map<String, Object?> json) {
    final images = json['images'];
    final amenities = json['amenities'];
    return ListingPayload(
      descriptionEn: _str(json['description_en']) ?? '',
      descriptionAr: _str(json['description_ar']) ?? '',
      amenities: amenities is List ? amenities.whereType<String>().toList() : const [],
      media: images is List ? images.map(MediaItem.fromJson).whereType<MediaItem>().toList() : const [],
      contact: ListingContact.fromJson(json['contact']),
    );
  }

  /// Same keys, same shape as the website's listing form writes.
  Map<String, Object?> toJson() => {
    'amenities': amenities,
    'description_en': descriptionEn.trim(),
    'description_ar': descriptionAr.trim(),
    'images': media.map((m) => m.toJson()).toList(),
    'contact': contact.toJson(),
  };
}

/// One row of `public.properties`, payload unpacked.
class Listing {
  const Listing({
    required this.id,
    required this.ownerId,
    required this.status,
    required this.deal,
    required this.propertyType,
    required this.priceJod,
    required this.titleEn,
    required this.createdAt,
    this.titleAr,
    this.cityId,
    this.neighborhoodId,
    this.lat,
    this.lng,
    this.bedrooms,
    this.bathrooms,
    this.areaSqm,
    this.landSqm,
    this.yearBuilt,
    this.verified = false,
    this.featured = false,
    this.payload = const ListingPayload(),
    this.updatedAt,
    this.publishedAt,
    this.locationPrecision,
    this.address,
  });

  final String id;
  final String ownerId;
  final ListingStatus status;
  final DealType deal;
  final String propertyType;
  final String? cityId;
  final String? neighborhoodId;

  /// The PUBLISHABLE point. Exact only when [locationPrecision] is exact;
  /// otherwise displaced by up to 300 m. Never assume it is the building.
  final double? lat;
  final double? lng;
  final int priceJod;
  final int? bedrooms;
  final int? bathrooms;
  final int? areaSqm;
  final int? landSqm;
  final int? yearBuilt;
  final String titleEn;
  final String? titleAr;
  final bool verified;
  final bool featured;
  final ListingPayload payload;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final LocationPrecision? locationPrecision;

  /// Published only alongside an exact pin.
  final String? address;

  bool get isClosed => status.isClosed;
  bool get isRent => deal == DealType.rent;
  bool get hasCoordinates => lat != null && lng != null;
  bool get isExactLocation => locationPrecision == LocationPrecision.exact;

  /// Arabic content from the database wins; with no Arabic value the English
  /// one is shown — never a machine translation of it.
  String title(String lang) {
    final ar = titleAr?.trim() ?? '';
    final en = titleEn.trim();
    if (lang == 'ar') return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  String description(String lang) {
    final en = payload.descriptionEn.trim();
    final ar = payload.descriptionAr.trim();
    if (lang == 'ar') return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  String place(String lang) => Market.placeLabel(cityId, neighborhoodId, lang);

  /// The first photograph; a card is a still frame, so a leading video clip
  /// is skipped rather than shown as a broken image.
  String? get coverUrl {
    for (final m in payload.media) {
      if (!m.isVideo) return m.url;
    }
    return null;
  }

  List<MediaItem> get media => payload.media;

  /// Days since the listing last changed, which is what "listed N days ago"
  /// means on the website's search results.
  DateTime get freshness => updatedAt ?? publishedAt ?? createdAt;

  static int? _int(Object? v) => switch (v) {
    final int i => i,
    final num n => n.round(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static double? _double(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

  factory Listing.fromRow(Map<String, Object?> row) {
    final unpacked = PayloadCodec.unpack(_str(row['payload_gz']));
    return Listing(
      id: row['id']! as String,
      ownerId: _str(row['owner_id']) ?? '',
      status: ListingStatus.parse(row['status']),
      deal: DealType.parse(row['deal']),
      propertyType: _str(row['property_type']) ?? '',
      cityId: _str(row['city_id']),
      neighborhoodId: _str(row['neighborhood_id']),
      lat: _double(row['lat']),
      lng: _double(row['lng']),
      priceJod: _int(row['price_jod']) ?? 0,
      bedrooms: _int(row['bedrooms']),
      bathrooms: _int(row['bathrooms']),
      areaSqm: _int(row['area_sqm']),
      landSqm: _int(row['land_sqm']),
      yearBuilt: _int(row['year_built']),
      titleEn: _str(row['title_en']) ?? '',
      titleAr: _str(row['title_ar']),
      verified: row['verified'] == true,
      featured: row['featured'] == true,
      payload: ListingPayload.fromJson(unpacked),
      createdAt: _date(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _date(row['updated_at']),
      publishedAt: _date(row['published_at']),
      locationPrecision: LocationPrecision.parse(row['location_precision']),
      address: _str(row['address']),
    );
  }

  Listing copyWith({ListingStatus? status}) => Listing(
    id: id,
    ownerId: ownerId,
    status: status ?? this.status,
    deal: deal,
    propertyType: propertyType,
    priceJod: priceJod,
    titleEn: titleEn,
    titleAr: titleAr,
    createdAt: createdAt,
    cityId: cityId,
    neighborhoodId: neighborhoodId,
    lat: lat,
    lng: lng,
    bedrooms: bedrooms,
    bathrooms: bathrooms,
    areaSqm: areaSqm,
    landSqm: landSqm,
    yearBuilt: yearBuilt,
    verified: verified,
    featured: featured,
    payload: payload,
    updatedAt: updatedAt,
    publishedAt: publishedAt,
    locationPrecision: locationPrecision,
    address: address,
  );
}
