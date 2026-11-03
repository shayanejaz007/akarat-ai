import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/config/env.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/listing_image.dart';
import '../../core/widgets/motion.dart';
import '../../shared/reference/market_data.dart';
import '../../shared/services/supabase_providers.dart';
import '../ai_search/presentation/ai_search_screen.dart' show AiMark, VoiceOrbMini;
import '../ai_search/voice/voice_search_sheet.dart';
import '../assistant/composer.dart';
import '../assistant/reply_view.dart';
import '../favorites/favorites_controller.dart';
import 'advisor_controller.dart';
import 'advisor_models.dart';

/// Property AI: the website's AI advisor, in the app. A conversation about
/// finding, comparing and investing in property in Jordan, answered with the
/// listings it found, its sources, and what to ask next.
class AdvisorView extends ConsumerStatefulWidget {
  const AdvisorView({super.key, this.initialQuery, this.focusToken, this.voiceToken});

  /// Asked straight away (a deep link, or Home's search field).
  final String? initialQuery;

  /// Changes each time Home's search field sends the reader here.
  final String? focusToken;

  /// Changes each time Home's microphone sends the reader here.
  final String? voiceToken;

  @override
  ConsumerState<AdvisorView> createState() => _AdvisorViewState();
}

class _AdvisorViewState extends ConsumerState<AdvisorView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String? _lastInitial;
  String? _lastFocus;
  String? _lastVoice;

  @override
  void initState() {
    super.initState();
    _react();
  }

  @override
  void didUpdateWidget(AdvisorView old) {
    super.didUpdateWidget(old);
    _react();
  }

  void _react() {
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty && q != _lastInitial) {
      _lastInitial = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_send(q));
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
        if (mounted) unawaited(_voice());
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Dictation: the whole text lands in the box, to be checked and sent.
  Future<void> _voice() async {
    _focus.unfocus();
    final text = await showVoiceSearch(context, dictation: true);
    if (!mounted || text == null) return;
    if (text.isNotEmpty) {
      final current = _input.text.trimRight();
      _input.text = current.isEmpty ? text : '$current $text';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    _focus.requestFocus();
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || ref.read(advisorProvider).busy) return;
    unawaited(HapticFeedback.lightImpact());
    if (text == null) _input.clear();
    _focus.unfocus();
    _toBottom(force: true);
    await ref.read(advisorProvider.notifier).send(q, lang: context.lang);
  }

  /// Follows the answer while the reader is at the bottom; once they scroll
  /// up to read, they are left where they are.
  void _toBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.position;
      if (force || p.maxScrollExtent - p.pixels < 240) _scroll.jumpTo(p.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = ref.watch(advisorProvider);
    ref.listen(advisorProvider.select((s) => s.version), (_, _) => _toBottom());
    return Column(
      children: [
        Expanded(
          child: s.isEmpty
              ? _Idle(onPrompt: _send, onVoice: () => unawaited(_voice()))
              : ListView.builder(
                  controller: _scroll,
                  padding: Layout.inset(context, top: Space.md, bottom: Space.xl),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: s.turns.length,
                  itemBuilder: (context, i) {
                    final t = s.turns[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Space.lg),
                      child: t.user
                          ? UserBubble(text: t.text)
                          : _AnswerView(
                              turn: t,
                              last: i == s.turns.length - 1,
                              onFollowup: _send,
                              onRetry: () => unawaited(ref.read(advisorProvider.notifier).retry(lang: context.lang)),
                              question: i > 0 ? s.turns[i - 1].text : '',
                            ),
                    );
                  },
                ),
        ),
        AssistantComposer(
          controller: _input,
          focus: _focus,
          hint: s.isEmpty ? l.advPlaceholder : l.advPlaceholderMore,
          label: l.advInputLabel,
          busy: s.busy,
          maxLength: AdvisorController.maxChars,
          onSend: () => unawaited(_send()),
          onStop: () => ref.read(advisorProvider.notifier).stop(),
          onVoice: () => unawaited(_voice()),
          above: s.criteria == null || s.busy ? null : _CriteriaChips(criteria: s.criteria!),
        ),
      ],
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.onPrompt, required this.onVoice});
  final ValueChanged<String> onPrompt;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final prompts = [
      (l.advPrompt1, Icons.search_rounded),
      (l.advPrompt2, Icons.calculate_outlined),
      (l.advPrompt3, Icons.compare_arrows_rounded),
      (l.advPrompt4, Icons.place_outlined),
    ];
    return ListView(
      padding: Layout.inset(context, top: Space.lg, bottom: Space.xl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Reveal(child: AiMark()),
        const SizedBox(height: Space.md),
        Text(l.advKicker, style: context.text.labelMedium?.copyWith(color: c.emerald, letterSpacing: 0.3)),
        const SizedBox(height: Space.xs),
        Reveal(
          index: 1,
          child: Semantics(header: true, child: Text(l.advIdleTitle, style: context.text.headlineMedium)),
        ),
        const SizedBox(height: Space.sm),
        Reveal(
          index: 2,
          child: Text(l.advIdleBody, style: context.text.bodyLarge?.copyWith(color: c.inkMuted)),
        ),
        const SizedBox(height: Space.lg),
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
                          Text(l.voiceDictationHint, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Reveal(
          index: 4,
          child: GroupedSection(
            children: [
              for (final (text, icon) in prompts)
                InkWell(
                  onTap: () => onPrompt(text),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: c.emerald),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            text,
                            textDirection: isArabicText(text) ? TextDirection.rtl : TextDirection.ltr,
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

/// The advisor's answer: its steps, its text with numbered citations, the
/// listings and comparisons it showed, notices, sources and follow-ups.
class _AnswerView extends ConsumerWidget {
  const _AnswerView({
    required this.turn,
    required this.last,
    required this.onFollowup,
    required this.onRetry,
    required this.question,
  });
  final AdvisorTurn turn;
  final bool last;
  final ValueChanged<String> onFollowup;
  final VoidCallback onRetry;
  final String question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final working = turn.status == TurnStatus.working;
    final hosts = {
      Uri.parse(Env.siteUrl).host.replaceFirst(RegExp(r'^www\.'), ''),
      for (final s in turn.sources) s.host.replaceFirst(RegExp(r'^www\.'), ''),
    };
    final children = <Widget>[];
    void gap([double h = Space.sm]) => children.add(SizedBox(height: h));

    children.add(
      Row(
        children: [
          const AiMark(size: 26),
          const SizedBox(width: Space.xs),
          Text('Akarat AI', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    gap();
    if (working && !turn.hasText) {
      children.add(WorkingLine(text: advisorDoing(l, turn.current)));
      gap();
    } else if (turn.steps.isNotEmpty) {
      children.add(
        StepsSummary(label: advisorSummary(l, turn.steps), steps: [for (final st in turn.steps) advisorDid(l, st)]),
      );
      gap();
    }
    for (final n in turn.notices.where((n) => n.kind == 'memory_reset')) {
      children.add(AssistantNotice(text: advisorNotice(l, n.kind)));
      gap();
    }
    if (turn.redacted != null) {
      children.add(
        AssistantNotice(
          text: turn.redacted == 'leak' ? l.advLeak : l.advRefused,
          icon: Icons.block_rounded,
          tone: NoticeTone.warning,
        ),
      );
      gap();
    }
    for (final p in turn.parts) {
      switch (p) {
        case TextPart():
          children.add(ReplyView(text: p.text, linkHosts: hosts, onCite: (n) => _openSource(context, n)));
        case CardsPart():
          children.add(
            Column(
              children: [
                for (final card in p.cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: switch (card) {
                      AkaratAdvisorCard() => _AkaratCardView(card: card),
                      ExternalAdvisorCard() => _ExternalCardView(card: card),
                    },
                  ),
              ],
            ),
          );
        case ComparePart():
          children.add(_CompareView(table: p.table));
      }
      gap();
    }
    if (working && turn.hasText) {
      children.add(WorkingLine(text: advisorDoing(l, turn.current)));
      gap();
    }
    for (final n in turn.notices.where((n) => n.kind != 'memory_reset')) {
      final disclaimer = n.kind == 'disclaimer';
      children.add(
        AssistantNotice(
          text: disclaimer ? advisorDisclaimer(n.lang ?? lang, l) : advisorNotice(l, n.kind),
          icon: disclaimer ? Icons.shield_outlined : Icons.info_outline_rounded,
          tone: disclaimer || n.kind == 'unbacked_claim' ? NoticeTone.warning : NoticeTone.info,
        ),
      );
      gap();
    }
    if (turn.status == TurnStatus.error) {
      children.add(_ErrorBox(code: turn.error ?? 'unavailable', onRetry: onRetry, question: question));
      gap();
    }
    if (turn.sources.isNotEmpty) {
      children.add(_SourcesList(sources: turn.sources));
      gap();
    }
    if (!working && turn.hasText) {
      children.add(
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                unawaited(Clipboard.setData(ClipboardData(text: turn.plainText)));
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(l.aiHubCopied), duration: const Duration(seconds: 2)));
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(l.aiHubCopy),
            ),
          ],
        ),
      );
    }
    if (last && !working && turn.followups.isNotEmpty) {
      gap(Space.xs);
      children.add(
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final f in turn.followups)
              ActionChip(
                label: Text(f, textDirection: isArabicText(f) ? TextDirection.rtl : TextDirection.ltr),
                avatar: Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: c.emerald),
                onPressed: () => onFollowup(f),
              ),
          ],
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  void _openSource(BuildContext context, int n) {
    final s = turn.sources.where((x) => x.n == n).firstOrNull;
    if (s == null) return;
    final uri = Uri.tryParse(s.url);
    if (uri != null && uri.scheme == 'https') unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }
}

/// What the advisor is doing right now, in the reader's words.
String advisorDoing(AppLocalizations l, AdvisorStep? st) {
  if (st == null || st.s == 'thinking') return l.advThinking;
  return switch (st.s) {
    'writing' => l.advWriting,
    'akarat_search' => l.advDoingSearch,
    'akarat_listing' => l.advDoingListing,
    'akarat_stats' => l.advDoingStats,
    'web_search' => st.q == null || st.q!.isEmpty ? l.advDoingWebSearch : l.advDoingWebSearchFor(st.q!),
    'web_fetch' => st.host == null || st.host!.isEmpty ? l.advDoingWebFetchPage : l.advDoingWebFetch(st.host!),
    'calc' => l.advDoingCalc,
    'compare' => l.advDoingCompare,
    _ => l.advDoingOther,
  };
}

/// What the advisor did, for the expandable list of its steps.
String advisorDid(AppLocalizations l, AdvisorStep st) => switch (st.s) {
  'akarat_search' => l.advDidSearch,
  'akarat_listing' => l.advDidListing,
  'akarat_stats' => l.advDidStats,
  'web_search' => st.q == null || st.q!.isEmpty ? l.advDidWebSearch : l.advDidWebSearchFor(st.q!),
  'web_fetch' => st.host == null || st.host!.isEmpty ? l.advDidWebFetchPage : l.advDidWebFetch(st.host!),
  'calc' => l.advDidCalc,
  'compare' => l.advDidCompare,
  _ => st.s,
};

String advisorNotice(AppLocalizations l, String kind) => switch (kind) {
  'partial' => l.advNoticePartial,
  'memory_reset' => l.advNoticeMemoryReset,
  'unbacked_claim' => l.advNoticeUnbacked,
  'stopped' => l.advNoticeStopped,
  _ => '',
};

/// The risk note in the language the answer was written in.
String advisorDisclaimer(String lang, AppLocalizations l) => lang == 'ar'
    ? 'الاستثمار بالعقار فيه مخاطر. تأكّد من المعلومات واعمل بحثك الخاص قبل ما تاخد أي قرار استثماري.'
    : (l.localeName == 'en'
          ? l.advDisclaimer
          : 'Property markets involve risk. Please conduct your own research and verify all information before making an investment decision.');

/// The work behind an answer, in one line: "Akarat.ai listings · 2 searches".
String advisorSummary(AppLocalizations l, List<AdvisorStep> steps) {
  int count(String k) => steps.where((x) => x.s == k).length;
  final bits = <String>[
    if (count('akarat_search') + count('akarat_listing') + count('akarat_stats') > 0) l.advSummaryAkarat,
    if (count('web_search') > 0) l.advSummarySearches(count('web_search')),
    if (count('web_fetch') > 0) l.advSummaryPages(count('web_fetch')),
    if (count('calc') > 0) l.advSummaryCalc,
    if (count('compare') > 0) l.advSummaryCompare,
  ];
  return bits.isEmpty ? l.advSummarySteps : bits.join(' · ');
}

class _ErrorBox extends ConsumerWidget {
  const _ErrorBox({required this.code, required this.onRetry, required this.question});
  final String code;
  final VoidCallback onRetry;
  final String question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final signedIn = ref.watch(isSignedInProvider);
    final text = switch (code) {
      'rate_limited' => l.advErrRateLimited,
      'quota' => signedIn ? l.advErrQuotaSignedIn : l.advErrQuotaGuest,
      'quota_total' => l.advErrQuotaTotal,
      'busy' => l.advErrBusy,
      'not_configured' => l.advErrNotConfigured,
      'too_long' => l.advErrTooLong,
      'offline' => l.advErrOffline,
      'interrupted' => l.advErrInterrupted,
      _ => l.advErrOther,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AssistantNotice(text: text, icon: Icons.error_outline_rounded, tone: NoticeTone.danger),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            if (advisorRetryCodes.contains(code))
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l.actionRetry),
              ),
            // As on the website: when the advisor cannot answer, the plain
            // search over the listings still can.
            if (advisorFallbackCodes.contains(code) && question.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => context.go('${Routes.plainSearch}?q=${Uri.encodeQueryComponent(question)}'),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(l.advPlainSearch),
              ),
          ],
        ),
      ],
    );
  }
}

class _SourcesList extends StatelessWidget {
  const _SourcesList({required this.sources});
  final List<AdvisorSource> sources;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.advSources, style: context.text.labelLarge?.copyWith(color: c.inkMuted)),
        const SizedBox(height: Space.xs),
        for (final s in sources)
          InkWell(
            onTap: () {
              final uri = Uri.tryParse(s.url);
              if (uri != null && uri.scheme == 'https') unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '${s.n}',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.forest),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title.isEmpty ? s.host : s.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: isArabicText(s.title) ? TextDirection.rtl : TextDirection.ltr,
                          style: context.text.bodyMedium?.copyWith(color: c.emerald),
                        ),
                        Text(
                          [s.host, if (s.date != null) _sourceDate(s.date!, context.lang)].join(' · '),
                          style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A source's date as the site gave it: an ISO stamp is shown as a date,
/// anything else ("October 20, 2026") as written.
String _sourceDate(String raw, String lang) {
  final d = DateTime.tryParse(raw);
  return d == null ? raw : Fmt.date(d, lang: lang);
}

class _AkaratCardView extends ConsumerWidget {
  const _AkaratCardView({required this.card});
  final AkaratAdvisorCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final saved = ref.watch(favoritesProvider.select((s) => s.contains(card.id)));
    final facts = [
      if (card.beds != null) '${card.beds} ${l.advRowBeds.toLowerCase()}',
      if (card.baths != null) '${card.baths} ${l.advRowBaths.toLowerCase()}',
      if (card.size != null) Fmt.area(card.size!, lang: lang),
      if (card.land != null && card.size == null) Fmt.area(card.land!, lang: lang),
    ];
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: card.id.isEmpty ? null : () => context.push(Routes.property(card.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ListingImage(url: card.image, semanticLabel: card.title(lang)),
                  if (card.verified)
                    PositionedDirectional(
                      top: Space.xs,
                      start: Space.xs,
                      child: _Badge(text: l.advVerified, icon: Icons.verified_rounded),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.price(card.price, lang: lang, rent: card.basis == 'month', night: card.basis == 'night'),
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: Space.hair),
                  Text(card.title(lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                  const SizedBox(height: Space.hair),
                  Text(
                    [
                      card.location(lang),
                      if (facts.isNotEmpty) facts.join(' · '),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: Space.hair),
                  Text(l.advUpdated(card.listedDays), style: context.text.bodySmall?.copyWith(color: c.inkFaint)),
                  if (card.why.isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      card.why,
                      textDirection: isArabicText(card.why) ? TextDirection.rtl : TextDirection.ltr,
                      style: context.text.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: card.id.isEmpty ? null : () => context.push(Routes.property(card.id)),
                          child: Text(l.advView),
                        ),
                      ),
                      IconButton(
                        tooltip: saved ? l.a11yUnsave : l.a11ySave,
                        onPressed: card.id.isEmpty
                            ? null
                            : () async {
                                unawaited(HapticFeedback.lightImpact());
                                final messenger = ScaffoldMessenger.of(context);
                                final now = await ref.read(favoritesProvider.notifier).toggle(card.id);
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(now ? l.savedAdded : l.savedRemoved),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                              },
                        icon: Icon(
                          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: saved ? c.red : null,
                        ),
                      ),
                      Builder(
                        builder: (button) => IconButton(
                          tooltip: l.actionShare,
                          onPressed: () => SharePlus.instance.share(
                            ShareParams(
                              text: '${card.title(lang)}\n${_listingUrl(card, lang)}',
                              subject: card.title(lang),
                              sharePositionOrigin: shareOrigin(button),
                            ),
                          ),
                          icon: const Icon(Icons.ios_share_rounded),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The listing's page on the website, in the reader's language.
  static String _listingUrl(AkaratAdvisorCard card, String lang) =>
      card.id.isNotEmpty ? Env.listingWebUrl(card.id, lang).toString() : card.url;
}

class _ExternalCardView extends StatelessWidget {
  const _ExternalCardView({required this.card});
  final ExternalAdvisorCard card;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final source = card.source(lang);
    final facts = [
      if (card.checked && card.beds != null) '${card.beds} ${l.advRowBeds.toLowerCase()}',
      if (card.checked && card.baths != null) '${card.baths} ${l.advRowBaths.toLowerCase()}',
      if (card.checked && card.size != null) Fmt.area(card.size!, lang: lang),
    ];
    final uri = Uri.tryParse(card.url);
    final open = uri != null && uri.scheme == 'https'
        ? () => launchUrl(uri, mode: LaunchMode.externalApplication)
        : null;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Badge(text: '${l.advExternal} · $source', icon: Icons.open_in_new_rounded, muted: true),
              const SizedBox(height: Space.xs),
              Text(
                card.checked && card.price != null
                    ? Fmt.price(card.price, lang: lang, rent: card.basis == 'month', night: card.basis == 'night')
                    : l.advPriceOn(source),
                style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Space.hair),
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: isArabicText(card.title) ? TextDirection.rtl : TextDirection.ltr,
                style: context.text.titleSmall,
              ),
              if ((card.location ?? '').isNotEmpty || facts.isNotEmpty) ...[
                const SizedBox(height: Space.hair),
                Text(
                  [if ((card.location ?? '').isNotEmpty) card.location!, ...facts].join(' · '),
                  style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                ),
              ],
              if (card.why.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Text(
                  card.why,
                  textDirection: isArabicText(card.why) ? TextDirection.rtl : TextDirection.ltr,
                  style: context.text.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
              const SizedBox(height: Space.xs),
              Text(
                card.checked ? l.advExtChecked(source) : l.advExtUnchecked(source),
                style: context.text.bodySmall?.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Space.xs),
              OutlinedButton.icon(
                onPressed: open,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l.advViewOn(source)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.icon, this.muted = false});
  final String text;
  final IconData icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = muted ? c.inkMuted : c.forest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 4),
      decoration: BoxDecoration(
        color: muted ? c.surfaceMuted : c.surface.withValues(alpha: 0.94),
        borderRadius: Radii.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareView extends StatelessWidget {
  const _CompareView({required this.table});
  final CompareTable table;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    String rowLabel(String k) => switch (k) {
      'price' => l.advRowPrice,
      'per_sqm' => l.advRowPerSqm,
      'beds' => l.advRowBeds,
      'baths' => l.advRowBaths,
      'size' => l.advRowSize,
      'land' => l.advRowLand,
      'type' => l.advRowType,
      'location' => l.advRowLocation,
      'verified' => l.advRowVerified,
      'age' => l.advRowAge,
      _ => k,
    };
    String value(String k, Object? v) {
      if (v == null) return '—';
      if (v is bool) return v ? l.advYes : l.advNo;
      if (v is num) {
        return switch (k) {
          'price' => Fmt.price(v, lang: lang),
          'per_sqm' => '${Fmt.number(v)} ${l.advJod}',
          'size' || 'land' => Fmt.area(v, lang: lang),
          'age' => l.advDays(v.toInt()),
          _ => Fmt.number(v),
        };
      }
      return '$v';
    }

    Widget cell(String s, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          s,
          style: (head ? context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700) : context.text.bodySmall),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.advCompareCaption, style: context.text.labelLarge?.copyWith(color: c.inkMuted)),
        const SizedBox(height: Space.xs),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(horizontalInside: BorderSide(color: c.border)),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: c.surfaceMuted),
                  children: [cell(''), for (final col in table.columns) cell(col.title, head: true)],
                ),
                for (final r in table.rows)
                  TableRow(
                    children: [
                      cell(rowLabel(r.k), head: true),
                      for (var i = 0; i < table.columns.length; i++) cell(value(r.k, i < r.v.length ? r.v[i] : null)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What the advisor last searched for, as chips: removing one asks the
/// advisor to search again without it.
class _CriteriaChips extends ConsumerWidget {
  const _CriteriaChips({required this.criteria});
  final Map<String, Object?> criteria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = context.lang;
    final labels = criteriaLabels(criteria, l, lang);
    if (labels.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: l.advCriteria,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: Space.iconGap),
              TagChip(
                label: labels[i],
                removeLabel: l.advRemoveCriterion(labels[i]),
                onRemove: () => unawaited(ref.read(advisorProvider.notifier).removeCriterion(labels[i], lang: lang)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The search criteria as the website's dock shows them.
List<String> criteriaLabels(Map<String, Object?> c, AppLocalizations l, String lang) {
  String name(List<Bilingual> list, Object? id) {
    final hit = list.where((e) => _idOf(e) == id).firstOrNull;
    return hit == null ? '$id' : hit.label(lang);
  }

  List<Object?> listOf(Object? v) => v is List ? v : const [];
  final out = <String>[];
  final deal = c['deal'];
  if (deal == 'sale') out.add(l.advDealSale);
  if (deal == 'rent') out.add(l.advDealRent);
  if (deal == 'daily') out.add(l.advDealDaily);
  for (final t in listOf(c['property_types'])) {
    out.add(name(Market.types, t));
  }
  final areas = listOf(c['areas']);
  if (areas.isNotEmpty) {
    for (final a in areas) {
      out.add(name(Market.neighborhoods, a));
    }
  } else if (c['city'] != null) {
    out.add(name(Market.cities, c['city']));
  }
  final min = c['budget_min_jod'];
  final max = c['budget_max_jod'];
  if (min is num && min > 0) out.add('≥ ${Fmt.number(min)} ${l.advJod}');
  if (max is num && max > 0) out.add('≤ ${Fmt.number(max)} ${l.advJod}');
  final beds = c['bedrooms_min'];
  if (beds is num) out.add(l.advBedsMin(beds.toInt()));
  final baths = c['bathrooms_min'];
  if (baths is num) out.add(l.advBathsMin(baths.toInt()));
  final size = c['size_min_sqm'];
  if (size is num && size > 0) out.add('${Fmt.number(size)}+ m²');
  for (final a in listOf(c['amenities'])) {
    out.add(name(Market.amenities, a));
  }
  return out;
}

Object? _idOf(Bilingual b) => switch (b) {
  City(:final id) => id,
  Neighborhood(:final id) => id,
  Amenity(:final id) => id,
  PropertyType(:final id) => id,
  _ => null,
};
