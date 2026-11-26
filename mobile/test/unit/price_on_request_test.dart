import 'package:akarat/features/ai_search/domain/ranker.dart';
import 'package:akarat/features/ai_search/domain/search_item.dart';
import 'package:akarat/features/listings/domain/listing_draft.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:akarat/shared/models/listing_filters.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

/// Price on request and the quality score (migration 0025), as the app reads
/// them: the listing, the listing form, AI Search and the default order.
void main() {
  Map<String, Object?> row({String deal = 'sale', int price = 0, bool onRequest = true, int? score}) => {
    'id': 'a1',
    'owner_id': 'o1',
    'status': 'active',
    'deal': deal,
    'property_type': 'apartment',
    'price_jod': price,
    'price_on_request': onRequest,
    'quality_score': score,
    'title_en': 'Flat in Abdoun',
    'created_at': '2026-11-01T10:00:00Z',
  };

  test('a listing priced on request says so, in both languages', () {
    final l = Listing.fromRow(row(score: 72));
    expect(l.priceOnRequest, isTrue);
    expect(l.qualityScore, 72);
    expect(l.priceText('en'), 'Price on request');
    expect(l.priceText('ar'), 'السعر عند الطلب');
    expect(l.pinPrice('en'), 'On request');
  });

  test('a listing with a price shows it with its period', () {
    final l = Listing.fromRow(row(deal: 'rent', price: 550, onRequest: false));
    expect(l.priceOnRequest, isFalse);
    expect(l.qualityScore, isNull);
    expect(l.priceText('en'), '550 JOD/mo');
  });

  test('a daily rental always has a price, whatever the flag says', () {
    final l = Listing.fromRow(row(deal: 'daily', price: 60));
    expect(l.priceOnRequest, isFalse);
    expect(l.priceText('en'), '60 JOD/night');
  });

  test('the listing form accepts no price only when price on request applies', () {
    const blank = ListingDraft();
    expect(blank.priceOk, isFalse);
    expect(blank.copyWith(priceOnRequest: true).priceOk, isTrue);
    expect(blank.copyWith(price: '150000').priceOk, isTrue);
    // A daily rental cannot hide its nightly price.
    expect(blank.copyWith(deal: DealType.daily, priceOnRequest: true).priceOk, isFalse);
    // Kept through a saved draft.
    final again = ListingDraft.fromJson(blank.copyWith(priceOnRequest: true).toJson())!;
    expect(again.priceOnRequest, isTrue);
    // Editing a listing priced on request starts with an empty price.
    final editing = ListingDraft.fromListing(Listing.fromRow(row()));
    expect(editing.priceOnRequest, isTrue);
    expect(editing.price, '');
  });

  test('AI Search does not count a price on request as within budget', () {
    final item = SearchItem.fromListing(Listing.fromRow(row()));
    expect(item.price, isNull);
    expect(item.priceOnRequest, isTrue);
    const c = SearchConstraints(budgetMax: 150000);
    final reasons = Ranker.explain(item, c, (n, _) => '$n', 'en');
    expect(reasons.first.text, 'Price on request: ask the owner');
    final priced = SearchItem.fromListing(Listing.fromRow(row(price: 140000, onRequest: false)));
    expect(Ranker.score(priced, c), greaterThan(Ranker.score(item, c)));
  });

  test('the marketplace lists the best listings first unless asked otherwise', () {
    expect(const ListingFilters().sort, ListingSort.best);
  });
}
