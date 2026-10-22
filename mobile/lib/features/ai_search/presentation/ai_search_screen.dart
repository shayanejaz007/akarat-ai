import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoDialogAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/layout.dart';
import '../../../core/widgets/listing_image.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/user_text.dart';
import '../../../shared/models/search_constraints.dart';
import '../../../shared/reference/market_data.dart';
import '../../../shared/repositories/account_repositories.dart';
import '../../../shared/services/supabase_providers.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/property_card.dart';
import '../../property_details/property_details_screen.dart';
import '../../saved_searches/saved_searches_providers.dart';
import '../data/search_repository.dart';
import '../domain/portal_links.dart';
import '../domain/query_parser.dart';
import '../domain/ranker.dart';
import '../domain/search_item.dart';
import '../voice/voice_search_sheet.dart';
import 'ai_search_controller.dart';
import 'constraint_chips.dart';

class AiSearchScreen extends ConsumerStatefulWidget {
  const AiSearchScreen({super.key, this.initialQuery, this.focusToken, this.voiceToken});

  /// From a saved search, "search for similar", or a deep link.
  final String? initialQuery;

  /// Changes each time Home's search field sends the reader here, so the
  /// keyboard comes up as if they had tapped this field directly.
  final String? focusToken;

  /// Changes each time Home's microphone sends the reader here: voice search
  /// opens straight away.
  final String? voiceToken;

  @override
  ConsumerState<AiSearchScreen> createState() => _AiSearchScreenState();
}

class _AiSearchScreenState extends ConsumerState<AiSearchScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  ParsedQuery? _preview;
  String? _lastInitial;
  String? _lastFocus;
  String? _lastVoice;

  @override
  void initState() {
    super.initState();
    _react();
  }

  @override
  void didUpdateWidget(AiSearchScreen old) {
    super.didUpdateWidget(old);
    _react();
  }

  void _react() {
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty && q != _lastInitial) {
      _lastInitial = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(aiSearchProvider.notifier).submit(q, fresh: true));
      });
    }
    final f = widget.focusToken;
    if (f != null && f != _lastFocus) {
      _lastFocus = f;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    final v = widget.voiceToken;
    if (v != null && v != _lastVoice) {
      _lastVoice = v;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_voice(fresh: true));
      });
    }
  }

  /// Voice: the request comes back as text, reviewed, and is searched like
  /// a typed one. "Type instead" puts the keyboard up.
  Future<void> _voice({bool? fresh}) async {
    _focus.unfocus();
    final text = await showVoiceSearch(context);
    if (!mounted || text == null) return;
    if (text.isEmpty) {
      _focus.requestFocus();
      return;
    }
    await _submit(text, fresh);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A live reading of what is being typed, debounced so parsing never runs
  /// on every keystroke. Parsing is local; nothing is sent until "Search".
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final t = text.trim();
      final current = ref.read(aiSearchProvider).constraints;
      setState(() => _preview = t.length < 3 ? null : QueryParser.parse(t, current));
    });
  }

  Future<void> _submit([String? text, bool? fresh]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty) return;
    unawaited(HapticFeedback.lightImpact());
    _input.clear();
    _debounce?.cancel();
    setState(() => _preview = null);
    _focus.unfocus();
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: Motion.of(context, Motion.normal), curve: Motion.standard));
    }
    await ref.read(aiSearchProvider.notifier).submit(q, fresh: fresh);
  }

  Future<void> _saveSearch(AiSearchState s) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (!ref.read(isSignedInProvider)) {
      await context.push(Routes.withNext(Routes.signIn, Routes.aiSearch));
      return;
    }
    final c = s.constraints!;
    final suggested = s.turns.isNotEmpty ? s.turns.first : PortalLinks.describe(c, context.lang);
    final label = await showAdaptiveDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: suggested),
    );
    if (label == null || label.trim().isEmpty || !mounted) return;
    final failText = context.failureMessage;
    try {
      await ref.read(savedSearchesRepositoryProvider).create(label, c);
      ref.invalidate(savedSearchesProvider);
      unawaited(HapticFeedback.lightImpact());
      if (mounted) showSuccess(context, l.aiSearchSaved);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = ref.watch(aiSearchProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.aiTitle),
        actions: [
          if (s.hasSearch && s.phase == SearchPhase.done)
            IconButton(
              tooltip: l.aiSaveSearch,
              onPressed: () => _saveSearch(s),
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          if (s.hasSearch)
            IconButton(
              tooltip: l.aiStartOver,
              onPressed: () {
                ref.read(aiSearchProvider.notifier).reset();
                setState(() => _preview = null);
              },
              icon: const Icon(Icons.edit_square),
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: s.hasSearch
                ? _Results(state: s, scroll: _scroll)
                : _Idle(onExample: (q) => _submit(q, true), onVoice: () => unawaited(_voice(fresh: true))),
          ),
          _Composer(
            onVoice: () => unawaited(_voice()),
            controller: _input,
            focus: _focus,
            hint: s.hasSearch ? l.aiRefineHintShort : l.aiInputHint,
            preview: _preview,
            busy: s.phase == SearchPhase.running,
            onChanged: _onChanged,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.onExample, required this.onVoice});
  final ValueChanged<String> onExample;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final examples = [l.aiExample1, l.aiExample2, l.aiExample3];
    return ListView(
      padding: Layout.inset(context, top: Space.lg, bottom: Space.xl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Reveal(child: AiMark()),
        const SizedBox(height: Space.lg),
        Reveal(
          index: 1,
          child: Semantics(header: true, child: Text(l.aiIdleTitle, style: context.text.headlineMedium)),
        ),
        const SizedBox(height: Space.sm),
        Reveal(
          index: 2,
          child: Text(l.aiIdleBodyShort, style: context.text.bodyLarge?.copyWith(color: c.inkMuted)),
        ),
        const SizedBox(height: Space.lg),
        // Speaking is as first-class as typing.
        Reveal(
          index: 3,
          child: Material(
            color: Color.alphaBlend(c.emerald.withValues(alpha: 0.08), c.surface),
            shape: RoundedRectangleBorder(
              borderRadius: Radii.card,
              side: BorderSide(color: c.emerald.withValues(alpha: 0.25)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onVoice,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    const VoiceOrbMini(),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.aiSpeakTitle, style: context.text.titleSmall),
                          const SizedBox(height: Space.hair),
                          Text(l.aiSpeakBody, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        Text(l.aiTry, style: context.text.labelMedium?.copyWith(color: c.inkMuted)),
        const SizedBox(height: Space.sm),
        Reveal(
          index: 4,
          child: GroupedSection(
            children: [
              for (final e in examples)
                InkWell(
                  onTap: () => onExample(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.north_east_rounded, size: 18, color: c.emerald),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            e,
                            // An Arabic example reads right-to-left even in the
                            // English interface, and vice versa.
                            textDirection: QueryParser.detectLang(e) == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                            style: context.text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The AI's mark: a sparkle on the brand gradient, softly lit.
class AiMark extends StatelessWidget {
  const AiMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3DB394), Color(0xFF123C34)],
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF3DB394).withValues(alpha: 0.35), blurRadius: size * 0.45),
          BoxShadow(
            color: const Color(0xFFD9B25E).withValues(alpha: 0.2),
            blurRadius: size * 0.6,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: size * 0.45),
    );
  }
}

/// A small microphone on the same gradient, for "say it" prompts.
class VoiceOrbMini extends StatelessWidget {
  const VoiceOrbMini({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.35),
          colors: [Color(0xFF3DB394), Color(0xFF16836D), Color(0xFF123C34)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
    );
  }
}

/// What the parser picked up from the text being typed, shown right above
/// the field — where the reader is looking, and above the keyboard.
class _Preview extends StatelessWidget {
  const _Preview({required this.parsed});
  final ParsedQuery parsed;

  @override
  Widget build(BuildContext context) {
    final chips = constraintChips(context, parsed.constraints);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: context.l10n.aiReadingLive,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: Space.iconGap),
              TagChip(label: chips[i].label, icon: chips[i].icon),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.onVoice,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.busy,
    required this.onChanged,
    required this.onSubmit,
    this.preview,
  });

  final VoidCallback onVoice;
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final bool busy;
  final ParsedQuery? preview;
  final ValueChanged<String> onChanged;
  final Future<void> Function([String?, bool?]) onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final hasPreview = preview != null && constraintChips(context, preview!.constraints).isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: Layout.inset(
            context,
            top: Space.sm,
            bottom: Space.sm,
          ).copyWith(left: Layout.inset(context).left - 4, right: Layout.inset(context).right - 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: Motion.of(context, Motion.fast),
                alignment: Alignment.topCenter,
                child: hasPreview
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: _Preview(parsed: preview!),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 400,
                      // Wraps over lines, but is one request: Enter (on any
                      // keyboard, hardware included) searches, never a new line.
                      keyboardType: TextInputType.text,
                      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))],
                      textInputAction: TextInputAction.search,
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmit(),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintMaxLines: 1,
                        counterText: '',
                        // A soft grey fill like every other field; the edge
                        // appears only while typing.
                        filled: true,
                        fillColor: c.surfaceMuted,
                        border: const OutlineInputBorder(borderRadius: Radii.chip, borderSide: BorderSide.none),
                        enabledBorder: const OutlineInputBorder(borderRadius: Radii.chip, borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: Radii.chip,
                          borderSide: BorderSide(color: c.emerald, width: 1.4),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, v, _) {
                      final hasText = v.text.trim().isNotEmpty;
                      final ready = hasText && !busy;
                      // Nothing typed: the same button listens instead.
                      final voice = !hasText && !busy;
                      return Semantics(
                        button: true,
                        enabled: ready || voice,
                        label: voice ? l.a11yVoice : l.aiTitle,
                        child: Tooltip(
                          message: voice ? l.a11yVoice : l.aiTitle,
                          child: GestureDetector(
                            onTap: ready ? () => onSubmit() : (voice ? onVoice : null),
                            child: AnimatedContainer(
                              duration: Motion.of(context, Motion.fast),
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: ready || voice ? c.forest : c.surfaceMuted,
                                shape: BoxShape.circle,
                              ),
                              child: busy
                                  ? Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: CircularProgressIndicator(strokeWidth: 2.2, color: c.inkMuted),
                                    )
                                  : AnimatedSwitcher(
                                      duration: Motion.of(context, Motion.fast),
                                      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                                      child: Icon(
                                        voice ? Icons.mic_rounded : Icons.arrow_upward_rounded,
                                        key: ValueKey(voice),
                                        color: c.onForest,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.state, required this.scroll});
  final AiSearchState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final constraints = state.constraints!;
    final outcome = state.outcome;
    final running = state.phase == SearchPhase.running;
    final notifier = ref.read(aiSearchProvider.notifier);
    final inset = Layout.inset(context);

    return ListView(
      controller: scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxl),
      children: [
        // What was asked, turn by turn.
        Padding(
          padding: inset,
          child: Column(
            children: [
              for (final (i, t) in state.turns.indexed)
                Reveal(
                  id: 'turn-$i-$t',
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
                      constraints: BoxConstraints(
                        maxWidth: (MediaQuery.sizeOf(context).width - inset.horizontal) * 0.85,
                      ),
                      decoration: BoxDecoration(
                        color: c.forest,
                        borderRadius: const BorderRadiusDirectional.only(
                          topStart: Radius.circular(Radii.lg),
                          topEnd: Radius.circular(Radii.lg),
                          bottomStart: Radius.circular(Radii.lg),
                          bottomEnd: Radius.circular(6),
                        ).resolve(Directionality.of(context)),
                      ),
                      child: Text(
                        t,
                        textDirection: QueryParser.detectLang(t) == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                        style: context.text.bodyMedium?.copyWith(color: c.onForest),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        _Brief(constraints: constraints, onChange: notifier.setConstraints),
        const SizedBox(height: Space.lg),
        if (running)
          Padding(
            padding: inset,
            child: _Progress(completed: state.completed),
          ),
        if (state.phase == SearchPhase.failed)
          ErrorState(
            compact: true,
            error: state.error ?? const AppFailure(FailureKind.unknown),
            onRetry: AppFailure.from(state.error ?? '').kind == FailureKind.rateLimited ? null : notifier.retry,
          ),
        if (!running && outcome != null)
          Padding(
            padding: inset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _outcome(context, outcome, constraints, notifier.setConstraints),
            ),
          ),
      ],
    );
  }

  List<Widget> _outcome(
    BuildContext context,
    SearchOutcome o,
    SearchConstraints c,
    Future<void> Function(SearchConstraints) onChange,
  ) {
    final l = context.l10n;
    final internal = o.internal;
    final external = o.external;
    // Results animate in again for each new brief, not on every rebuild.
    final run = '${state.turns.length}-${c.hashCode}';
    final unavailable = o.coverage.unavailable.map((u) => u.split(':').first.trim()).toList();
    final partnerOnly = unavailable.isNotEmpty && unavailable.every((u) => u.toLowerCase().contains('partner'));
    return [
      if (o.servedDirect) ...[
        NoticeLine(icon: Icons.info_outline_rounded, text: l.aiServedDirect),
        const SizedBox(height: Space.md),
      ],
      // The assistant's answer, in a sentence (an empty result says it below).
      if (internal.isNotEmpty) ...[
        Reveal(
          id: 'reply-$run',
          child: _Reply(text: l.aiFoundSummary(internal.length)),
        ),
        const SizedBox(height: Space.md),
      ],
      _SectionTitle(title: l.aiResultsInternal, count: internal.length),
      const SizedBox(height: Space.sm),
      if (internal.isEmpty) ...[
        EmptyState(compact: true, icon: Icons.manage_search_rounded, title: l.aiNoMatchTitle, body: l.aiNoMatchBody),
        _Alternatives(constraints: c, onChange: onChange),
      ] else
        for (final (i, r) in internal.indexed) ...[
          Reveal(
            index: i,
            id: 'r-$run-${r.item.id}',
            child: _ResultCard(result: r, constraints: c),
          ),
          const SizedBox(height: Space.sm),
        ],
      if (external.isNotEmpty) ...[
        const SizedBox(height: Space.lg),
        _SectionTitle(title: l.aiResultsExternal, count: external.length),
        const SizedBox(height: Space.xxs),
        Text(l.aiResultsExternalNote, style: context.text.bodySmall),
        const SizedBox(height: Space.sm),
        for (final (i, r) in external.indexed) ...[
          Reveal(
            index: i,
            id: 'x-$run-${r.item.id}',
            child: _ResultCard(result: r, constraints: c),
          ),
          const SizedBox(height: Space.sm),
        ],
      ],
      if (!c.internalOnly) ...[const SizedBox(height: Space.xl), _PortalSection(constraints: c)],
      // What was not searched, said plainly but out of the way.
      if (unavailable.isNotEmpty) ...[
        const SizedBox(height: Space.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline_rounded, size: 15, color: context.colors.inkFaint),
            ),
            const SizedBox(width: Space.iconGap),
            Expanded(
              child: Text(
                partnerOnly ? l.aiCoveragePartner : l.aiCoverageMissing(unavailable.join(', ')),
                style: context.text.bodySmall,
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Semantics(header: true, child: Text(title, style: context.text.headlineSmall)),
        ),
        const SizedBox(width: Space.xs),
        Text(
          '$count',
          style: context.text.headlineSmall?.copyWith(color: c.inkFaint, fontWeight: FontWeight.w400),
        ),
      ],
    );
  }
}

/// The brief: one scrollable line of editable chips, and — only when it
/// would help — a short line offering what is missing. Removing a chip
/// searches again without it.
class _Brief extends StatelessWidget {
  const _Brief({required this.constraints, required this.onChange});
  final SearchConstraints constraints;
  final Future<void> Function(SearchConstraints) onChange;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final inset = Layout.inset(context);
    final chips = constraintChips(context, constraints);
    final needsDeal = constraints.deal == null;
    final needsPlace = constraints.city == null && constraints.hood == null;
    final needsBudget = constraints.budgetMax == null && constraints.budgetMin == null;
    final needsBeds =
        constraints.beds == null && const {null, 'apartment', 'villa', 'house'}.contains(constraints.type);
    final rent = constraints.deal == 'rent';
    final budgets = rent ? const [500, 1000] : const [100000, 200000, 350000];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isEmpty)
          Padding(
            padding: inset,
            child: Text(l.aiBriefEmpty, style: context.text.bodySmall),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: inset.left),
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: Space.iconGap),
                  TagChip(
                    label: chips[i].label,
                    icon: chips[i].icon,
                    removeLabel: l.chipRemove(chips[i].label),
                    onRemove: () => onChange(chips[i].without),
                  ),
                ],
              ],
            ),
          ),
        if (needsDeal || needsPlace || needsBudget || needsBeds) ...[
          const SizedBox(height: Space.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: inset.left),
            child: Row(
              children: [
                Text('${l.aiSharpen}:', style: context.text.labelMedium?.copyWith(color: c.inkMuted)),
                const SizedBox(width: Space.xs),
                if (needsDeal) ...[
                  _Suggest(
                    label: l.dealSale,
                    icon: Icons.sell_outlined,
                    onTap: () => onChange(constraints.copyWith(deal: 'sale')),
                  ),
                  const SizedBox(width: Space.iconGap),
                  _Suggest(
                    label: l.dealRent,
                    icon: Icons.key_outlined,
                    onTap: () => onChange(constraints.copyWith(deal: 'rent')),
                  ),
                  const SizedBox(width: Space.iconGap),
                ],
                if (needsPlace) ...[
                  _Suggest(
                    label: l.locationPickerTitle,
                    icon: Icons.place_outlined,
                    onTap: () async {
                      final id = await showChoiceSheet(
                        context: context,
                        title: l.locationPickerTitle,
                        options: Market.cities,
                      );
                      if (id != null && id.isNotEmpty) await onChange(constraints.copyWith(city: id));
                    },
                  ),
                  const SizedBox(width: Space.iconGap),
                ],
                if (needsBudget)
                  for (final b in budgets) ...[
                    _Suggest(
                      label: l.aiUnder(Fmt.compactPrice(b, lang: context.lang, currency: !rent)),
                      icon: Icons.payments_outlined,
                      onTap: () => onChange(constraints.copyWith(budgetMax: b)),
                    ),
                    const SizedBox(width: Space.iconGap),
                  ],
                if (needsBeds)
                  for (final n in const [2, 3]) ...[
                    _Suggest(
                      label: l.aiBedsPlus(n),
                      icon: Icons.bed_outlined,
                      onTap: () => onChange(constraints.copyWith(beds: n)),
                    ),
                    const SizedBox(width: Space.iconGap),
                  ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Suggest extends StatelessWidget {
  const _Suggest({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: Radii.chip,
            border: Border.all(color: c.emerald.withValues(alpha: 0.5), style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: c.emerald),
              const SizedBox(width: Space.xxs),
              Text(label, style: context.text.labelMedium?.copyWith(color: c.forest)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.completed});
  final Set<SearchStage> completed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final labels = {
      SearchStage.language: l.aiStageLang,
      SearchStage.requirements: l.aiStageParse,
      SearchStage.location: l.aiStageLoc,
      SearchStage.marketplace: l.aiStageInternal,
      SearchStage.external: l.aiStageExternal,
      SearchStage.ranking: l.aiStageRank,
    };
    // The stage in hand is the first one not finished: real progress, not a timer.
    final current = SearchStage.values.firstWhere((s) => !completed.contains(s), orElse: () => SearchStage.ranking);
    final fraction = completed.length / SearchStage.values.length;
    return Semantics(
      liveRegion: true,
      label: '${l.aiWorking} ${labels[current]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ThinkingMark(),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.aiWorking, style: context.text.titleSmall),
                    const SizedBox(height: Space.hair),
                    AnimatedSwitcher(
                      duration: Motion.of(context, Motion.fast),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      ),
                      child: Text(
                        labels[current]!,
                        key: ValueKey(current),
                        style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: Radii.chip,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: Motion.of(context, Motion.normal),
              curve: Motion.standard,
              builder: (context, v, _) =>
                  LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: c.surfaceMuted, color: c.emerald),
            ),
          ),
          const SizedBox(height: Space.md),
          const Skeleton(height: 112, radius: Radii.lg),
          const SizedBox(height: Space.sm),
          const Skeleton(height: 112, radius: Radii.lg),
        ],
      ),
    );
  }
}

/// The AI mark with a slowly turning ring around it while a search runs.
class _ThinkingMark extends StatefulWidget {
  const _ThinkingMark();

  @override
  State<_ThinkingMark> createState() => _ThinkingMarkState();
}

class _ThinkingMarkState extends State<_ThinkingMark> with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      unawaited(_turn.repeat());
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _turn,
            child: CustomPaint(
              size: const Size(48, 48),
              painter: _ArcPainter(colour: c.emerald, track: c.border),
            ),
          ),
          const AiMark(size: 36),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.colour, required this.track});
  final Color colour;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(1.5), 0, 6.283, false, p..color = track.withValues(alpha: 0.6));
    p.shader = SweepGradient(colors: [colour.withValues(alpha: 0), colour]).createShader(rect);
    canvas.drawArc(rect.deflate(1.5), 0, 4.4, false, p);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.colour != colour || old.track != track;
}

/// The assistant's side of the conversation: one plain sentence.
class _Reply extends StatelessWidget {
  const _Reply({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AiMark(size: 28),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(6),
                topEnd: Radius.circular(Radii.lg),
                bottomStart: Radius.circular(Radii.lg),
                bottomEnd: Radius.circular(Radii.lg),
              ).resolve(Directionality.of(context)),
            ),
            child: Semantics(liveRegion: true, child: Text(text, style: context.text.bodyMedium)),
          ),
        ),
      ],
    );
  }
}

/// When nothing matches: one step looser, each a real search when tapped.
/// Never a promise of results; only ways to widen the brief.
class _Alternatives extends StatelessWidget {
  const _Alternatives({required this.constraints, required this.onChange});
  final SearchConstraints constraints;
  final Future<void> Function(SearchConstraints) onChange;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final k = constraints;
    final rent = k.deal == 'rent';
    // A quarter more, rounded up to a figure people actually say.
    final step = rent ? 50 : 5000;
    final looser = k.budgetMax == null ? null : ((k.budgetMax! * 1.25) / step).ceil() * step;
    final options = <(String, IconData, SearchConstraints)>[
      if (k.hood != null && k.city != null)
        (l.aiAllOfCity(Market.city(k.city)?.label(lang) ?? k.city!), Icons.place_outlined, k.copyWith(clearHood: true)),
      if (looser != null)
        (
          l.aiUpTo(Fmt.compactPrice(looser, lang: lang, currency: !rent)),
          Icons.payments_outlined,
          k.copyWith(budgetMax: looser),
        ),
      if (k.beds != null && k.beds! > 1) (l.aiBedsPlus(k.beds! - 1), Icons.bed_outlined, k.copyWith(beds: k.beds! - 1)),
      if (k.type != null) (l.aiAnyType, Icons.home_work_outlined, k.copyWith(clearType: true)),
      if (k.deal != null) (l.aiBothDeals, Icons.swap_horiz_rounded, k.copyWith(clearDeal: true)),
      if (k.amenities.isNotEmpty) (l.aiFewerFeatures, Icons.tune_rounded, k.copyWith(amenities: const [])),
    ];
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.aiTryInstead, style: context.text.labelMedium?.copyWith(color: c.inkMuted)),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, icon, next) in options) _Suggest(label: label, icon: icon, onTap: () => onChange(next)),
          ],
        ),
      ],
    );
  }
}

/// Where an external row came from, by name.
String _sourceName(SearchItem item, AppLocalizations l) {
  if (item.sources.length > 1) return l.aiSourcesCount(item.sources.length);
  return switch (item.source) {
    'opensooq' => 'OpenSooq',
    'bayut' => 'Bayut',
    final s? => s,
    null => '',
  };
}

/// One ranked result with its score and the reasons behind it.
class _ResultCard extends StatefulWidget {
  const _ResultCard({required this.result, required this.constraints});
  final RankedResult result;
  final SearchConstraints constraints;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _open = false;

  Future<void> _openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final item = widget.result.item;
    final score = widget.result.score;
    final reasons = Ranker.explain(
      item,
      widget.constraints,
      (n, deal) => Fmt.price(n, lang: lang, rent: deal == 'rent'),
      lang,
    );
    final place = Market.placeLabel(item.city, item.hood, lang);
    final scoreColor = score >= 75 ? c.emerald : (score >= 50 ? c.gold : c.inkMuted);

    // Unique per search, so the same listing in an earlier answer cannot clash.
    final hero = 'ai-${widget.constraints.hashCode}-${item.id}';

    void open() {
      if (item.listing != null) {
        openProperty(context, item.listing!, hero: hero);
      } else if (item.url != null) {
        unawaited(_openSource(item.url!));
      }
    }

    return Container(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.all(Space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: Radii.field,
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: item.listing == null
                          ? ListingImage(url: item.imageUrl, decodeWidth: 96)
                          : Hero(
                              tag: hero,
                              child: ListingImage(url: item.imageUrl, decodeWidth: 96),
                            ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _MatchRing(score: score, colour: scoreColor),
                            const SizedBox(width: Space.iconGap),
                            Expanded(
                              child: Text(l.aiMatch(score), style: context.type.badge.copyWith(color: scoreColor)),
                            ),
                            if (item.listing != null)
                              // A full 44 pt target that does not make the line taller.
                              SizedBox(
                                width: 36,
                                height: 28,
                                child: OverflowBox(
                                  maxWidth: 44,
                                  maxHeight: 44,
                                  child: FavoriteButton(listingId: item.id, onImage: false, size: 20),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.hair),
                        UserText(
                          item.title(lang),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: Space.hair),
                        Text(
                          Fmt.price(item.price, lang: lang, rent: item.deal == 'rent'),
                          style: context.type.priceSmall,
                        ),
                        if (place.isNotEmpty)
                          Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        if (item.isExternal)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new_rounded, size: 13, color: c.inkFaint),
                                const SizedBox(width: Space.xxs),
                                Flexible(
                                  child: Text(
                                    _sourceName(item, l),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.labelSmall?.copyWith(color: c.inkMuted),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (item.verified)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.verified_rounded, size: 14, color: c.emerald),
                                const SizedBox(width: Space.xxs),
                                Text(l.badgeVerified, style: context.text.labelSmall?.copyWith(color: c.emerald)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: c.border.withValues(alpha: 0.7)),
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l.aiWhyMatches, style: context.text.labelMedium?.copyWith(color: c.inkMuted)),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: Motion.of(context, Motion.fast),
                    child: Icon(Icons.expand_more_rounded, color: c.inkFaint, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: Motion.of(context, Motion.normal),
            sizeCurve: Motion.standard,
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in reasons) _Reason(reason: r),
                  if (item.isExternal && item.url != null) ...[
                    const SizedBox(height: Space.sm),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(backgroundColor: c.surface),
                      onPressed: () => _openSource(item.url!),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(l.aiViewOnSource),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({required this.reason});
  final MatchReason reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color) = switch (reason.kind) {
      ReasonKind.good => (Icons.check_circle_rounded, c.emerald),
      ReasonKind.ok => (Icons.check_circle_outline_rounded, c.emerald),
      ReasonKind.warn => (Icons.error_outline_rounded, c.warning),
      ReasonKind.bad => (Icons.remove_circle_outline_rounded, c.inkFaint),
      ReasonKind.plain => (Icons.schedule_rounded, c.inkMuted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(reason.text, style: context.text.bodySmall?.copyWith(color: c.ink)),
          ),
        ],
      ),
    );
  }
}

/// Real searches on the Jordanian portals, each saying what its link drops.
class _PortalSection extends StatelessWidget {
  const _PortalSection({required this.constraints});
  final SearchConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final portals = PortalLinks.build(constraints, context.lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(l.aiWiderMarket, style: context.text.headlineSmall)),
        const SizedBox(height: Space.xxs),
        Text(l.aiWiderBody, style: context.text.bodySmall),
        const SizedBox(height: Space.sm),
        GroupedSection(
          children: [
            for (final p in portals)
              GroupedTile(
                icon: p.id == 'web' ? Icons.travel_explore_rounded : Icons.storefront_outlined,
                title: p.name,
                subtitle: p.note,
                trailing: Semantics(
                  label: l.aiOpensOutside,
                  child: Icon(Icons.open_in_new_rounded, size: 18, color: c.inkFaint),
                ),
                onTap: () => launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication),
              ),
          ],
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _c = TextEditingController(
    text: widget.initial.length > 80 ? widget.initial.substring(0, 80) : widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    void save() => Navigator.pop(context, _c.text);
    return AlertDialog.adaptive(
      title: Text(l.aiSaveSearchTitle),
      content: Padding(
        padding: EdgeInsets.only(top: ios ? Space.sm : 0),
        child: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: _c,
            autofocus: true,
            maxLength: 80,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => save(),
            decoration: const InputDecoration(counterText: ''),
          ),
        ),
      ),
      actions: ios
          ? [
              CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: Text(l.actionCancel)),
              CupertinoDialogAction(isDefaultAction: true, onPressed: save, child: Text(l.actionSave)),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l.actionCancel)),
              FilledButton(onPressed: save, child: Text(l.actionSave)),
            ],
    );
  }
}

/// The match score as a small ring that fills when the card appears.
class _MatchRing extends StatelessWidget {
  const _MatchRing({required this.score, required this.colour});
  final int score;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: Motion.of(context, Motion.slow),
      curve: Motion.standard,
      builder: (context, v, _) => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          value: v,
          strokeWidth: 2.5,
          color: colour,
          backgroundColor: c.border,
          strokeCap: StrokeCap.round,
        ),
      ),
    );
  }
}
