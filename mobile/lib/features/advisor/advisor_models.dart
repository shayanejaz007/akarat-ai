import '../assistant/assistant_stream.dart';

/// A listing the advisor showed: one of Akarat.ai's, or one on another site
/// whose exact link came back from a search. Field for field what the
/// website's page receives (lib/advisor/listings.ts, lib/advisor/evidence.ts).
sealed class AdvisorCard {
  const AdvisorCard({required this.key, required this.why});
  final String key;

  /// The advisor's one-line reason it fits.
  final String why;

  static AdvisorCard? fromJson(Map<String, Object?> j) => switch (j['kind']) {
    'akarat' => AkaratAdvisorCard.fromJson(j),
    'external' => ExternalAdvisorCard.fromJson(j),
    _ => null,
  };
}

class AkaratAdvisorCard extends AdvisorCard {
  const AkaratAdvisorCard({
    required super.key,
    required super.why,
    required this.id,
    required this.url,
    required this.titleEn,
    required this.titleAr,
    required this.deal,
    required this.type,
    required this.price,
    required this.basis,
    this.beds,
    this.baths,
    this.size,
    this.land,
    required this.locationEn,
    required this.locationAr,
    required this.verified,
    this.image,
    this.photos = 0,
    this.listedDays = 0,
  });

  factory AkaratAdvisorCard.fromJson(Map<String, Object?> j) {
    Map<String, Object?> bi(Object? v) => v is Map ? v.cast<String, Object?>() : const {};
    return AkaratAdvisorCard(
      key: str(j['key']),
      why: str(j['why']),
      id: str(j['id']),
      url: str(j['url']),
      titleEn: str(bi(j['title'])['en']),
      titleAr: str(bi(j['title'])['ar']),
      deal: str(j['deal']),
      type: str(j['type']),
      price: numOrNull(j['price']) ?? 0,
      basis: str(j['basis'], 'total'),
      beds: numOrNull(j['beds']),
      baths: numOrNull(j['baths']),
      size: numOrNull(j['size']),
      land: numOrNull(j['land']),
      locationEn: str(bi(j['location'])['en']),
      locationAr: str(bi(j['location'])['ar']),
      verified: j['verified'] == true,
      image: j['image'] is String ? j['image'] as String : null,
      photos: numOrNull(j['photos'])?.toInt() ?? 0,
      listedDays: numOrNull(j['listedDays'])?.toInt() ?? 0,
    );
  }

  final String id;
  final String url;
  final String titleEn;
  final String titleAr;
  final String deal;
  final String type;
  final num price;
  final String basis;
  final num? beds;
  final num? baths;
  final num? size;
  final num? land;
  final String locationEn;
  final String locationAr;
  final bool verified;
  final String? image;
  final int photos;
  final int listedDays;

  String title(String lang) => lang == 'ar' && titleAr.isNotEmpty ? titleAr : (titleEn.isNotEmpty ? titleEn : titleAr);
  String location(String lang) =>
      lang == 'ar' && locationAr.isNotEmpty ? locationAr : (locationEn.isNotEmpty ? locationEn : locationAr);
}

class ExternalAdvisorCard extends AdvisorCard {
  const ExternalAdvisorCard({
    required super.key,
    required super.why,
    required this.url,
    required this.sourceName,
    required this.sourceNameAr,
    required this.host,
    required this.title,
    this.price,
    this.basis,
    this.beds,
    this.baths,
    this.size,
    this.location,
    required this.checked,
    this.seen,
  });

  factory ExternalAdvisorCard.fromJson(Map<String, Object?> j) {
    final source = j['source'] is Map ? (j['source']! as Map).cast<String, Object?>() : const <String, Object?>{};
    return ExternalAdvisorCard(
      key: str(j['key']),
      why: str(j['why']),
      url: str(j['url']),
      sourceName: str(source['name']),
      sourceNameAr: str(source['nameAr']),
      host: str(source['host']),
      title: str(j['title']),
      price: numOrNull(j['price']),
      basis: j['basis'] is String ? j['basis'] as String : null,
      beds: numOrNull(j['beds']),
      baths: numOrNull(j['baths']),
      size: numOrNull(j['size']),
      location: j['location'] is String ? j['location'] as String : null,
      checked: j['checked'] == true,
      seen: j['seen'] is String ? j['seen'] as String : null,
    );
  }

  final String url;
  final String sourceName;
  final String sourceNameAr;
  final String host;
  final String title;
  final num? price;
  final String? basis;
  final num? beds;
  final num? baths;
  final num? size;
  final String? location;

  /// True when the figures shown were each found on the page itself. When
  /// false the card shows no price: the advisor did not read the listing.
  final bool checked;
  final String? seen;

  String source(String lang) =>
      lang == 'ar' && sourceNameAr.isNotEmpty ? sourceNameAr : (sourceName.isNotEmpty ? sourceName : host);
}

/// A web source the answer cites: numbered as the text's citation chips are.
class AdvisorSource {
  const AdvisorSource({required this.n, required this.url, required this.title, required this.host, this.date});

  factory AdvisorSource.fromJson(Map<String, Object?> j) => AdvisorSource(
    n: numOrNull(j['n'])?.toInt() ?? 0,
    url: str(j['url']),
    title: str(j['title']),
    host: str(j['host']),
    date: j['date'] is String ? j['date'] as String : null,
  );

  final int n;
  final String url;
  final String title;
  final String host;
  final String? date;
}

/// A side-by-side comparison: one column per listing, one row per fact.
class CompareTable {
  const CompareTable({required this.columns, required this.rows});

  factory CompareTable.fromJson(Map<String, Object?> j) {
    final cols = <({String key, String title, String source})>[];
    for (final c in (j['columns'] is List ? j['columns']! as List : const [])) {
      if (c is Map) cols.add((key: str(c['key']), title: str(c['title']), source: str(c['source'])));
    }
    final rows = <({String k, List<Object?> v})>[];
    for (final r in (j['rows'] is List ? j['rows']! as List : const [])) {
      if (r is Map) rows.add((k: str(r['k']), v: r['v'] is List ? List<Object?>.from(r['v'] as List) : const []));
    }
    return CompareTable(columns: cols, rows: rows);
  }

  final List<({String key, String title, String source})> columns;
  final List<({String k, List<Object?> v})> rows;
}

/// One step of the advisor's work: a search, a page read, a calculation.
class AdvisorStep {
  const AdvisorStep(this.s, {this.q, this.host});
  final String s;
  final String? q;
  final String? host;
}

/// The pieces of an answer, in the order they arrived: text, listing cards
/// and comparisons interleave as the advisor works.
sealed class AdvisorPart {}

class TextPart extends AdvisorPart {
  TextPart(this.text);
  String text;
}

class CardsPart extends AdvisorPart {
  CardsPart(this.cards);
  final List<AdvisorCard> cards;
}

class ComparePart extends AdvisorPart {
  ComparePart(this.table);
  final CompareTable table;
}

enum TurnStatus { working, done, error, stopped }

/// One message of the conversation. The reader's are plain text; the
/// advisor's fill in as its answer streams.
class AdvisorTurn {
  AdvisorTurn.user(this.text) : user = true;
  AdvisorTurn.assistant() : user = false, text = '';

  final bool user;
  final String text;
  final parts = <AdvisorPart>[];
  final sources = <AdvisorSource>[];
  final steps = <AdvisorStep>[];
  final notices = <({String kind, String? lang})>[];
  List<String> followups = const [];
  AdvisorStep? current;
  TurnStatus status = TurnStatus.working;
  String? error;

  /// 'leak' or 'refused': the reply was withdrawn and its text removed.
  String? redacted;

  bool get hasText => parts.any((p) => p is TextPart && p.text.trim().isNotEmpty);

  /// The answer as plain text, citation markers removed, for copying.
  String get plainText => parts
      .whereType<TextPart>()
      .map((p) => p.text.replaceAll(RegExp('$citeOpen[\\d,]*$citeClose'), ''))
      .join('\n\n')
      .trim();
}

class AdvisorState {
  const AdvisorState({this.turns = const [], this.transcript, this.criteria, this.version = 0});

  final List<AdvisorTurn> turns;

  /// The conversation so far, signed by the server: sent back with the next
  /// message so the advisor remembers it. Held only in memory.
  final String? transcript;

  /// What the advisor last searched for: shown as chips the reader can remove.
  final Map<String, Object?>? criteria;

  /// Bumped on every change: turns are updated in place as the answer streams.
  final int version;

  bool get busy => turns.isNotEmpty && !turns.last.user && turns.last.status == TurnStatus.working;
  bool get isEmpty => turns.isEmpty;

  AdvisorState copyWith({
    List<AdvisorTurn>? turns,
    String? transcript,
    Map<String, Object?>? criteria,
    bool clearCriteria = false,
  }) => AdvisorState(
    turns: turns ?? this.turns,
    transcript: transcript ?? this.transcript,
    criteria: clearCriteria ? null : (criteria ?? this.criteria),
    version: version + 1,
  );
}

/// Codes after which the plain search stands in, as on the website.
const advisorFallbackCodes = {'not_configured', 'unavailable', 'busy', 'quota', 'quota_total', 'offline'};

/// Codes worth a "try again".
const advisorRetryCodes = {'busy', 'unavailable', 'offline', 'interrupted', 'rate_limited'};
