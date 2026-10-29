import 'dart:io';

import '../../../shared/models/listing.dart';

/// One file in the form: already in Storage (editing), or picked on this
/// device and not yet uploaded. A picked file that uploads during a publish
/// that then fails keeps its [uploaded] result, so a retry does not send it
/// twice.
class DraftMedia {
  const DraftMedia({this.existing, this.localPath, required this.kind, this.uploaded});

  final MediaItem? existing;
  final String? localPath;
  final MediaKind kind;
  final MediaItem? uploaded;

  bool get isVideo => kind == MediaKind.video;
  bool get isLocal => existing == null;

  /// What ends up in the payload once everything has uploaded.
  MediaItem? get stored => existing ?? uploaded;

  DraftMedia withUploaded(MediaItem m) => DraftMedia(existing: existing, localPath: localPath, kind: kind, uploaded: m);

  Map<String, Object?> toJson() => {
    if (existing != null) 'existing': existing!.toJson(),
    'localPath': localPath,
    'kind': kind.name,
    if (uploaded != null) 'uploaded': uploaded!.toJson(),
  };

  static DraftMedia? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'] == 'video' ? MediaKind.video : MediaKind.image;
    final existing = MediaItem.fromJson(json['existing']);
    final uploaded = MediaItem.fromJson(json['uploaded']);
    final path = json['localPath'] as String?;
    if (existing == null && uploaded == null && (path == null || !File(path).existsSync())) return null;
    return DraftMedia(existing: existing, localPath: path, kind: kind, uploaded: uploaded);
  }
}

/// Everything the listing form holds. Field for field, the website's
/// blankListing(): indexed columns, the payload, and the pin.
class ListingDraft {
  const ListingDraft({
    this.deal = DealType.sale,
    this.propertyType = 'apartment',
    this.cityId = 'amman',
    this.neighborhoodId,
    this.price = '',
    this.bedrooms = '',
    this.bathrooms = '',
    this.areaSqm = '',
    this.landSqm = '',
    this.yearBuilt = '',
    this.titleEn = '',
    this.titleAr = '',
    this.descriptionEn = '',
    this.descriptionAr = '',
    this.amenities = const [],
    this.contactPhone = '',
    this.maxGuests = '',
    this.minNights = '1',
    this.media = const [],
    this.lat,
    this.lng,
    this.address = '',
    this.precision = LocationPrecision.approximate,
  });

  final DealType deal;
  final String propertyType;
  final String? cityId;
  final String? neighborhoodId;

  // Numbers stay text while editing, as on the website, and are parsed once.
  final String price;
  final String bedrooms;
  final String bathrooms;
  final String areaSqm;
  final String landSqm;
  final String yearBuilt;
  final String titleEn;
  final String titleAr;
  final String descriptionEn;
  final String descriptionAr;
  final List<String> amenities;
  final String contactPhone;

  /// Daily rentals only: how many it sleeps, and the shortest stay.
  final String maxGuests;
  final String minNights;
  final List<DraftMedia> media;

  /// The EXACT pin the owner placed. What gets published is decided by
  /// [precision] at save time; approximate is the default, because an owner
  /// who never opened the map should not have their address published.
  final double? lat;
  final double? lng;
  final String address;
  final LocationPrecision precision;

  bool get hasPin => lat != null && lng != null;

  static int? number(String v) {
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  ListingDraft copyWith({
    DealType? deal,
    String? propertyType,
    String? cityId,
    String? neighborhoodId,
    bool clearNeighborhood = false,
    String? price,
    String? bedrooms,
    String? bathrooms,
    String? areaSqm,
    String? landSqm,
    String? yearBuilt,
    String? titleEn,
    String? titleAr,
    String? descriptionEn,
    String? descriptionAr,
    List<String>? amenities,
    String? contactPhone,
    String? maxGuests,
    String? minNights,
    List<DraftMedia>? media,
    double? lat,
    double? lng,
    bool clearPin = false,
    String? address,
    LocationPrecision? precision,
  }) => ListingDraft(
    deal: deal ?? this.deal,
    propertyType: propertyType ?? this.propertyType,
    cityId: cityId ?? this.cityId,
    neighborhoodId: clearNeighborhood ? null : (neighborhoodId ?? this.neighborhoodId),
    price: price ?? this.price,
    bedrooms: bedrooms ?? this.bedrooms,
    bathrooms: bathrooms ?? this.bathrooms,
    areaSqm: areaSqm ?? this.areaSqm,
    landSqm: landSqm ?? this.landSqm,
    yearBuilt: yearBuilt ?? this.yearBuilt,
    titleEn: titleEn ?? this.titleEn,
    titleAr: titleAr ?? this.titleAr,
    descriptionEn: descriptionEn ?? this.descriptionEn,
    descriptionAr: descriptionAr ?? this.descriptionAr,
    amenities: amenities ?? this.amenities,
    contactPhone: contactPhone ?? this.contactPhone,
    maxGuests: maxGuests ?? this.maxGuests,
    minNights: minNights ?? this.minNights,
    media: media ?? this.media,
    lat: clearPin ? null : (lat ?? this.lat),
    lng: clearPin ? null : (lng ?? this.lng),
    address: address ?? this.address,
    precision: precision ?? this.precision,
  );

  /// Fills the form from a stored listing, for editing.
  factory ListingDraft.fromListing(Listing l) => ListingDraft(
    deal: l.deal,
    propertyType: l.propertyType,
    cityId: l.cityId ?? 'amman',
    neighborhoodId: l.neighborhoodId,
    price: '${l.priceJod}',
    bedrooms: l.bedrooms?.toString() ?? '',
    bathrooms: l.bathrooms?.toString() ?? '',
    areaSqm: l.areaSqm?.toString() ?? '',
    landSqm: l.landSqm?.toString() ?? '',
    yearBuilt: l.yearBuilt?.toString() ?? '',
    titleEn: l.titleEn,
    titleAr: l.titleAr ?? '',
    descriptionEn: l.payload.descriptionEn,
    descriptionAr: l.payload.descriptionAr,
    amenities: [...l.payload.amenities],
    contactPhone: l.payload.contact.phone,
    maxGuests: l.maxGuests?.toString() ?? '',
    minNights: '${l.minNights ?? 1}',
    media: [for (final m in l.media) DraftMedia(existing: m, kind: m.kind)],
    lat: l.lat,
    lng: l.lng,
    address: l.address ?? '',
    precision: l.locationPrecision ?? LocationPrecision.approximate,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'deal': deal.name,
    'propertyType': propertyType,
    'cityId': cityId,
    'neighborhoodId': neighborhoodId,
    'price': price,
    'bedrooms': bedrooms,
    'bathrooms': bathrooms,
    'areaSqm': areaSqm,
    'landSqm': landSqm,
    'yearBuilt': yearBuilt,
    'titleEn': titleEn,
    'titleAr': titleAr,
    'descriptionEn': descriptionEn,
    'descriptionAr': descriptionAr,
    'amenities': amenities,
    'contactPhone': contactPhone,
    'maxGuests': maxGuests,
    'minNights': minNights,
    'media': [for (final m in media) m.toJson()],
    'lat': lat,
    'lng': lng,
    'address': address,
    'precision': precision.name,
  };

  static ListingDraft? fromJson(Map<String, Object?>? j) {
    if (j == null || j['v'] != 1) return null;
    String s(String k) => (j[k] as String?) ?? '';
    final media = j['media'];
    final amenities = j['amenities'];
    return ListingDraft(
      deal: DealType.parse(j['deal']),
      propertyType: s('propertyType').isEmpty ? 'apartment' : s('propertyType'),
      cityId: j['cityId'] as String?,
      neighborhoodId: j['neighborhoodId'] as String?,
      price: s('price'),
      bedrooms: s('bedrooms'),
      bathrooms: s('bathrooms'),
      areaSqm: s('areaSqm'),
      landSqm: s('landSqm'),
      yearBuilt: s('yearBuilt'),
      titleEn: s('titleEn'),
      titleAr: s('titleAr'),
      descriptionEn: s('descriptionEn'),
      descriptionAr: s('descriptionAr'),
      amenities: amenities is List ? amenities.whereType<String>().toList() : const [],
      contactPhone: s('contactPhone'),
      maxGuests: s('maxGuests'),
      minNights: s('minNights').isEmpty ? '1' : s('minNights'),
      media: media is List ? media.map(DraftMedia.fromJson).whereType<DraftMedia>().toList() : const [],
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      address: s('address'),
      precision: LocationPrecision.parse(j['precision']) ?? LocationPrecision.approximate,
    );
  }

  /// Anything typed at all — decides whether leaving needs a confirmation.
  bool get isDirty => toJson().toString() != const ListingDraft().toJson().toString();
}
