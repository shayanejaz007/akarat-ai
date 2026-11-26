import 'package:flutter/foundation.dart';

import 'listing.dart';

/// [best]: the most complete listings first (the quality score, 0025).
enum ListingSort { best, newest, priceAsc, priceDesc }

/// The Explore screen's filters. Every one maps to an indexed column, so the
/// database does the filtering and only one page of rows ever travels.
/// Amenities live inside the compressed payload and cannot be filtered in SQL;
/// AI Search scores them instead, exactly as on the website.
@immutable
class ListingFilters {
  const ListingFilters({
    this.deal,
    this.governorateId,
    this.cityId,
    this.neighborhoodId,
    this.type,
    this.minBeds,
    this.minBaths,
    this.minPrice,
    this.maxPrice,
    this.minArea,
    this.maxArea,
    this.availableOnly = false,
    this.sort = ListingSort.best,
  });

  final DealType? deal;

  /// A governorate on its own: every town in it (lib/shared/reference/places.dart).
  final String? governorateId;
  final String? cityId;
  final String? neighborhoodId;
  final String? type;
  final int? minBeds;
  final int? minBaths;
  final int? minPrice;
  final int? maxPrice;
  final int? minArea;
  final int? maxArea;

  /// Sold and rented stay on the marketplace, greyed (migration 0011). This
  /// hides them for someone who only wants what they can still act on.
  final bool availableOnly;
  final ListingSort sort;

  /// How many refinements beyond buy/rent and sort are active, for the badge
  /// on the Filters button.
  int get activeCount => [
    governorateId != null || cityId != null,
    neighborhoodId != null,
    type != null,
    minBeds != null,
    minBaths != null,
    minPrice != null || maxPrice != null,
    minArea != null || maxArea != null,
    availableOnly,
  ].where((x) => x).length;

  ListingFilters copyWith({
    DealType? deal,
    String? governorateId,
    String? cityId,
    String? neighborhoodId,
    String? type,
    int? minBeds,
    int? minBaths,
    int? minPrice,
    int? maxPrice,
    int? minArea,
    int? maxArea,
    bool? availableOnly,
    ListingSort? sort,
    bool clearDeal = false,
    bool clearCity = false,
    bool clearNeighborhood = false,
    bool clearType = false,
    bool clearBeds = false,
    bool clearBaths = false,
    bool clearPrice = false,
    bool clearArea = false,
  }) {
    final cityChanged = !clearCity && cityId != null && cityId != this.cityId;
    return ListingFilters(
      deal: clearDeal ? null : (deal ?? this.deal),
      // A town chosen replaces a governorate on its own; clearing the city clears both.
      governorateId: clearCity ? governorateId : (governorateId ?? (cityId != null ? null : this.governorateId)),
      cityId: clearCity ? null : (cityId ?? this.cityId),
      // An area belongs to one city; changing the city drops it.
      neighborhoodId: (clearNeighborhood || clearCity || cityChanged)
          ? neighborhoodId
          : (neighborhoodId ?? this.neighborhoodId),
      type: clearType ? null : (type ?? this.type),
      minBeds: clearBeds ? null : (minBeds ?? this.minBeds),
      minBaths: clearBaths ? null : (minBaths ?? this.minBaths),
      minPrice: clearPrice ? minPrice : (minPrice ?? this.minPrice),
      maxPrice: clearPrice ? maxPrice : (maxPrice ?? this.maxPrice),
      minArea: clearArea ? minArea : (minArea ?? this.minArea),
      maxArea: clearArea ? maxArea : (maxArea ?? this.maxArea),
      availableOnly: availableOnly ?? this.availableOnly,
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ListingFilters &&
      other.deal == deal &&
      other.governorateId == governorateId &&
      other.cityId == cityId &&
      other.neighborhoodId == neighborhoodId &&
      other.type == type &&
      other.minBeds == minBeds &&
      other.minBaths == minBaths &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.minArea == minArea &&
      other.maxArea == maxArea &&
      other.availableOnly == availableOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    deal,
    governorateId,
    cityId,
    neighborhoodId,
    type,
    minBeds,
    minBaths,
    minPrice,
    maxPrice,
    minArea,
    maxArea,
    availableOnly,
    sort,
  );
}
