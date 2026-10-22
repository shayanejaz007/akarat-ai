import '../../../core/utils/formatters.dart';
import '../../../shared/models/listing.dart';

/// A search result in the vocabulary the ranker reads — the website's
/// `toSearchItem` shape. Akarat.ai listings and rows from the external market
/// index both become one of these, so they are scored by the same arithmetic.
class SearchItem {
  const SearchItem({
    required this.id,
    required this.titleEn,
    required this.titleAr,
    this.deal,
    this.type,
    this.city,
    this.hood,
    this.price,
    this.priceHigh,
    this.beds,
    this.baths,
    this.area,
    this.amenities = const [],
    this.days,
    this.checked,
    this.source,
    this.kind,
    this.sources = const [],
    this.sourceLinks = const [],
    this.url,
    this.imageUrl,
    this.verified = false,
    this.listing,
  });

  final String id;
  final String titleEn;
  final String titleAr;
  final String? deal;
  final String? type;
  final String? city;
  final String? hood;
  final int? price;

  /// External groups only: the dearest of the duplicate listings.
  final int? priceHigh;
  final int? beds;
  final int? baths;
  final int? area;
  final List<String> amenities;

  /// Akarat listings: days since the row last changed.
  final int? days;

  /// External rows: days since the crawler last checked the source. Never
  /// presented as availability — the source may have sold it since.
  final int? checked;

  /// Null for an Akarat.ai listing. For an external row, the source id, or
  /// "N sources" when the same property was found on several portals.
  final String? source;

  /// Source kind (`known_marketplace`, `licensed_feed`, …), for confidence.
  final String? kind;
  final List<String> sources;
  final List<ExternalSourceLink> sourceLinks;

  /// External rows: where the listing actually lives.
  final String? url;
  final String? imageUrl;
  final bool verified;

  /// Akarat listings only: the full row, so a result opens without refetching.
  final Listing? listing;

  bool get isExternal => source != null;

  String title(String lang) {
    if (lang == 'ar') return titleAr.isNotEmpty ? titleAr : titleEn;
    return titleEn.isNotEmpty ? titleEn : titleAr;
  }

  factory SearchItem.fromListing(Listing row, {DateTime? now}) => SearchItem(
    id: row.id,
    titleEn: row.titleEn.isNotEmpty ? row.titleEn : (row.titleAr ?? ''),
    titleAr: (row.titleAr?.isNotEmpty ?? false) ? row.titleAr! : row.titleEn,
    deal: row.deal.name,
    type: row.propertyType,
    city: row.cityId,
    hood: row.neighborhoodId,
    price: row.priceJod,
    beds: row.bedrooms,
    baths: row.bathrooms,
    area: row.areaSqm,
    amenities: row.payload.amenities,
    days: Fmt.daysSince(row.freshness, now: now),
    verified: row.verified,
    imageUrl: row.coverUrl,
    listing: row,
  );
}

class ExternalSourceLink {
  const ExternalSourceLink({required this.sourceId, required this.url, this.price, this.lastCheckedAt});
  final String sourceId;
  final String url;
  final int? price;
  final DateTime? lastCheckedAt;
}
