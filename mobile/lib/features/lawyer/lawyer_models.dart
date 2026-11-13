import '../assistant/assistant_stream.dart';

/// What `/api/legal/status` says about this reader before anyone types:
/// whether the service is running, whether they may use it, and the upload
/// limits to say out loud.
class LawyerStatus {
  const LawyerStatus({
    required this.ready,
    required this.phase,
    required this.signedIn,
    required this.allowed,
    required this.reviewer,
    this.maxBytes = 4000000,
    this.maxPages = 30,
    this.maxDocs = 4,
  });

  factory LawyerStatus.fromJson(Map<String, Object?> j) {
    final limits = j['limits'] is Map ? (j['limits']! as Map).cast<String, Object?>() : const <String, Object?>{};
    return LawyerStatus(
      ready: j['ready'] == true,
      phase: str(j['phase'], 'review'),
      signedIn: j['signedIn'] == true,
      allowed: j['allowed'] == true,
      reviewer: j['reviewer'] == true,
      maxBytes: numOrNull(limits['maxBytes'])?.toInt() ?? 4000000,
      maxPages: numOrNull(limits['maxPages'])?.toInt() ?? 30,
      maxDocs: numOrNull(limits['maxDocs'])?.toInt() ?? 4,
    );
  }

  /// The service could not be reached or is not running.
  static const down = LawyerStatus(ready: false, phase: 'review', signedIn: false, allowed: false, reviewer: false);

  final bool ready;

  /// 'open': anyone signed in may ask. 'review': only the reviewing lawyers,
  /// until launch.
  final String phase;
  final bool signedIn;
  final bool allowed;
  final bool reviewer;
  final int maxBytes;
  final int maxPages;
  final int maxDocs;
}

/// A source an answer cites, numbered as its citation chips are: the legal
/// library (a verified provision, judgment or commentary), an official
/// website, secondary reporting, or the reader's own document.
class LegalSource {
  const LegalSource({
    required this.n,
    required this.kind,
    required this.url,
    required this.title,
    required this.host,
    this.status,
    this.judgment = false,
    this.commentary = false,
    this.verified,
    this.licensed = false,
    this.date,
    this.doc,
    this.page,
    this.quote = '',
  });

  factory LegalSource.fromJson(Map<String, Object?> j) => LegalSource(
    n: numOrNull(j['n'])?.toInt() ?? 0,
    kind: str(j['kind'], 'secondary'),
    url: str(j['url']),
    title: str(j['title']),
    host: str(j['host']),
    status: j['status'] is String ? j['status'] as String : null,
    judgment: j['judgment'] == true,
    commentary: j['commentary'] == true,
    verified: j['verified'] is String ? j['verified'] as String : null,
    licensed: j['licensed'] == true,
    date: j['date'] is String ? j['date'] as String : null,
    doc: numOrNull(j['doc'])?.toInt(),
    page: numOrNull(j['page'])?.toInt(),
    quote: str(j['quote']),
  );

  final int n;

  /// 'library', 'official', 'secondary' or 'document'.
  final String kind;
  final String url;
  final String title;
  final String host;

  /// A library provision's status: 'in_force', 'amended', 'repealed' or
  /// 'unknown'.
  final String? status;
  final bool judgment;
  final bool commentary;

  /// When a library entry was last checked against its source.
  final String? verified;
  final bool licensed;

  /// A web page's age, or when it was read.
  final String? date;

  /// A document citation: which document, and the page.
  final int? doc;
  final int? page;

  /// The text cited, for the reader to check.
  final String quote;
}

/// One step of the research: reading the documents, a library search, a
/// citation check, an official search, a page read.
class LegalStep {
  const LegalStep(this.s, {this.q = '', this.host = ''});
  final String s;
  final String q;
  final String host;

  bool same(LegalStep o) => o.s == s && o.q == q && o.host == host;
}

enum DocState { uploading, ready, failed }

/// A document in the conversation: one being uploaded, one waiting to go
/// with the next question, or one sent with an earlier question.
class LegalDoc {
  const LegalDoc({
    required this.key,
    this.id,
    required this.name,
    required this.kind,
    this.pages,
    this.scanned = false,
    this.state = DocState.ready,
    this.error,
  });

  factory LegalDoc.fromJson(Map<String, Object?> j) {
    final id = str(j['id']);
    return LegalDoc(
      key: 'd$id',
      id: id,
      name: str(j['name'], 'document'),
      kind: str(j['kind'], 'pdf'),
      pages: numOrNull(j['pages'])?.toInt(),
      scanned: j['scanned'] == true,
    );
  }

  final String key;
  final String? id;
  final String name;

  /// 'pdf', 'docx', 'txt' or 'image'.
  final String kind;
  final int? pages;
  final bool scanned;
  final DocState state;

  /// Why it could not be added (the codes of POST /api/legal/documents).
  final String? error;

  LegalDoc copyWith({
    String? id,
    String? name,
    String? kind,
    int? pages,
    bool? scanned,
    DocState? state,
    String? error,
  }) => LegalDoc(
    key: key,
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    pages: pages ?? this.pages,
    scanned: scanned ?? this.scanned,
    state: state ?? this.state,
    error: error ?? this.error,
  );

  /// What a file's name says it is. The server reads the bytes, not this.
  static String kindOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'pdf';
    if (n.endsWith('.docx')) return 'docx';
    if (n.endsWith('.txt')) return 'txt';
    return 'image';
  }
}

enum LegalTurnState { working, done, error, stopped }

/// One message of the conversation. The reader's carry their text and the
/// documents sent with it; the answer fills in as its events arrive.
class LegalTurn {
  LegalTurn.user(this.text, {this.docs = const []}) : user = true, state = LegalTurnState.done;
  LegalTurn.assistant() : user = false, text = '', docs = const [], state = LegalTurnState.working;

  final bool user;
  String text;
  final List<LegalDoc> docs;
  LegalTurnState state;
  LegalStep? current;
  final steps = <LegalStep>[];
  final sources = <LegalSource>[];

  /// References in the answer that could not be matched to an official
  /// source: marked in the text and listed under it.
  List<String> unverified = const [];
  ({String level, String text})? urgent;
  List<String> followups = const [];

  /// 'partial', 'unbacked_claim' or 'stopped'.
  final notices = <String>[];
  String? error;

  /// 'leak' or 'refused': the answer was withdrawn and its text removed.
  String? redacted;

  /// The saved answer's id, for "Report a problem".
  int? messageId;

  /// The language the answer was written in.
  String? lang;
  bool reported = false;

  bool get hasText => text.trim().isNotEmpty;
}

/// A conversation in the history list.
class LegalConversation {
  const LegalConversation({required this.id, required this.title, this.updatedAt, this.expiresAt});

  factory LegalConversation.fromJson(Map<String, Object?> j) => LegalConversation(
    id: str(j['id']),
    title: str(j['title']),
    updatedAt: DateTime.tryParse(str(j['updatedAt'])),
    expiresAt: DateTime.tryParse(str(j['expiresAt'])),
  );

  final String id;
  final String title;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
}

class LawyerState {
  const LawyerState({
    this.status,
    this.turns = const [],
    this.conversationId,
    this.title = '',
    this.docs = const [],
    this.history,
    this.historyError = false,
    this.version = 0,
  });

  /// Null until /api/legal/status has answered.
  final LawyerStatus? status;
  final List<LegalTurn> turns;

  /// The open conversation, once the server has made one (the first
  /// question or the first upload does).
  final String? conversationId;
  final String title;

  /// Documents waiting to go with the next question, and any that failed.
  final List<LegalDoc> docs;

  /// Null until loaded.
  final List<LegalConversation>? history;
  final bool historyError;

  /// Bumped on every change: turns are updated in place as the answer streams.
  final int version;

  bool get busy => turns.isNotEmpty && !turns.last.user && turns.last.state == LegalTurnState.working;
  bool get allowed => status?.allowed ?? false;
  bool get uploading => docs.any((d) => d.state == DocState.uploading);
  bool get hasReadyDocs => docs.any((d) => d.state == DocState.ready);

  /// The service is down, or this account may not use it yet.
  bool get locked {
    final s = status;
    return s != null && (!s.ready || (s.signedIn && !s.allowed));
  }

  LawyerState copyWith({
    LawyerStatus? status,
    List<LegalTurn>? turns,
    String? conversationId,
    bool clearConversation = false,
    String? title,
    List<LegalDoc>? docs,
    List<LegalConversation>? history,
    bool clearHistory = false,
    bool? historyError,
  }) => LawyerState(
    status: status ?? this.status,
    turns: turns ?? this.turns,
    conversationId: clearConversation ? null : (conversationId ?? this.conversationId),
    title: title ?? this.title,
    docs: docs ?? this.docs,
    history: clearHistory ? null : (history ?? this.history),
    historyError: historyError ?? this.historyError,
    version: version + 1,
  );
}

/// Codes worth a "try again".
const lawyerRetryCodes = {'busy', 'unavailable', 'offline', 'interrupted', 'rate_limited'};

/// The kinds of report "Report a problem" can send (POST /api/legal/feedback).
const feedbackKinds = ['good', 'wrong_law', 'wrong_citation', 'outdated', 'fabricated', 'missing', 'unclear', 'other'];
