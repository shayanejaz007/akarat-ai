import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../shared/models/search_constraints.dart';
import '../data/search_repository.dart';
import '../domain/query_parser.dart';

enum SearchPhase { idle, running, done, failed }

/// Stages shown while a search runs. They advance on real events — parsing
/// finishes on the device at once, retrieval when the network answers —
/// never on a timer pretending to work.
enum SearchStage { language, requirements, location, marketplace, external, ranking }

class AiSearchState {
  const AiSearchState({
    this.turns = const [],
    this.parsed,
    this.constraints,
    this.phase = SearchPhase.idle,
    this.completed = const {},
    this.outcome,
    this.error,
  });

  /// What the reader typed, in order. Later turns refine earlier ones.
  final List<String> turns;
  final ParsedQuery? parsed;
  final SearchConstraints? constraints;
  final SearchPhase phase;
  final Set<SearchStage> completed;
  final SearchOutcome? outcome;
  final Object? error;

  bool get hasSearch => constraints != null;

  AiSearchState copyWith({
    List<String>? turns,
    ParsedQuery? parsed,
    SearchConstraints? constraints,
    SearchPhase? phase,
    Set<SearchStage>? completed,
    SearchOutcome? outcome,
    Object? error,
    bool clearOutcome = false,
    bool clearError = false,
  }) => AiSearchState(
    turns: turns ?? this.turns,
    parsed: parsed ?? this.parsed,
    constraints: constraints ?? this.constraints,
    phase: phase ?? this.phase,
    completed: completed ?? this.completed,
    outcome: clearOutcome ? null : (outcome ?? this.outcome),
    error: clearError ? null : (error ?? this.error),
  );
}

final aiSearchProvider = NotifierProvider<AiSearchController, AiSearchState>(AiSearchController.new);

class AiSearchController extends Notifier<AiSearchState> {
  CancelToken? _inFlight;

  @override
  AiSearchState build() {
    ref.onDispose(() => _inFlight?.cancel());
    return const AiSearchState();
  }

  /// Reads [text]. With [fresh] false and a search already on screen, the
  /// text refines it ("only Abdoun", "raise the budget") — the same rule the
  /// website applies to typing in its results box.
  Future<void> submit(String text, {bool? fresh}) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final isFresh = fresh ?? !state.hasSearch;
    final parsed = QueryParser.parse(q, isFresh ? null : state.constraints);
    state = AiSearchState(
      turns: isFresh ? [q] : [...state.turns, q],
      parsed: parsed,
      constraints: parsed.constraints,
      phase: SearchPhase.running,
      completed: const {SearchStage.language, SearchStage.requirements, SearchStage.location},
    );
    await _run(parsed.constraints);
  }

  /// A chip was edited or removed: search again with exactly that brief.
  Future<void> setConstraints(SearchConstraints c) async {
    if (c == state.constraints) return;
    state = state.copyWith(
      constraints: c,
      phase: SearchPhase.running,
      completed: const {SearchStage.language, SearchStage.requirements, SearchStage.location},
      clearError: true,
    );
    await _run(c);
  }

  /// Runs a saved search exactly as it was saved, as a new conversation.
  Future<void> setConstraintsFresh(SearchConstraints c, {required String label}) async {
    state = AiSearchState(
      turns: [label],
      constraints: c,
      phase: SearchPhase.running,
      completed: const {SearchStage.language, SearchStage.requirements, SearchStage.location},
    );
    await _run(c);
  }

  Future<void> retry() async {
    final c = state.constraints;
    if (c == null) return;
    state = state.copyWith(phase: SearchPhase.running, clearError: true);
    await _run(c);
  }

  void reset() {
    _inFlight?.cancel();
    state = const AiSearchState();
  }

  Future<void> _run(SearchConstraints c) async {
    // Only the newest request may finish; anything older is cancelled at the
    // socket and ignored if it lands anyway.
    _inFlight?.cancel();
    final token = _inFlight = CancelToken();
    try {
      final outcome = await ref.read(searchRepositoryProvider).search(c, cancelToken: token);
      if (!identical(token, _inFlight)) return;
      state = state.copyWith(
        phase: SearchPhase.done,
        completed: SearchStage.values.toSet(),
        outcome: outcome,
        clearError: true,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (identical(token, _inFlight)) state = state.copyWith(phase: SearchPhase.failed, error: AppFailure.from(e));
    } on Object catch (e) {
      if (identical(token, _inFlight)) state = state.copyWith(phase: SearchPhase.failed, error: e);
    }
  }
}
