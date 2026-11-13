import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/config/env.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/motion.dart';
import '../../shared/services/supabase_providers.dart';
import '../ai_search/voice/voice_search_sheet.dart';
import '../assistant/assistant_stream.dart';
import '../assistant/composer.dart';
import '../assistant/reply_view.dart';
import 'lawyer_controller.dart';
import 'lawyer_models.dart';

/// Ask a Lawyer: the website's legal assistant, in the app. Questions about
/// Jordanian law, answered from a verified legal library and official
/// sources, with the documents the reader shares, each answer cited and
/// carrying its notice. Signed-in accounts only; conversations stay on the
/// server, private to the account.
class LawyerView extends ConsumerStatefulWidget {
  const LawyerView({super.key});

  @override
  ConsumerState<LawyerView> createState() => _LawyerViewState();
}

enum _Attach { photo, camera, file }

class _LawyerViewState extends ConsumerState<LawyerView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(lawyerProvider).status == null) unawaited(ref.read(lawyerProvider.notifier).enter());
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _notify(String text) {
    if (text.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5)));
  }

  void _signIn() => unawaited(context.push(Routes.withNext(Routes.signIn, Routes.askLawyer)));

  Future<void> _send([String? text]) async {
    final l = context.l10n;
    final s = ref.read(lawyerProvider);
    if (s.busy) return;
    final raw = text ?? _input.text;
    if (raw.trim().isEmpty && !s.hasReadyDocs) return;
    unawaited(HapticFeedback.lightImpact());
    _focus.unfocus();
    // The question joins the conversation before send() first waits, so the
    // box is cleared only when it went; it keeps the text when it did not.
    final sending = ref.read(lawyerProvider.notifier).send(raw, lang: context.lang, docQuestion: l.lawDocQuestion);
    if (ref.read(lawyerProvider).busy && text == null) _input.clear();
    _toBottom(force: true);
    final why = await sending;
    if (!mounted) return;
    if (why == 'sign_in') _signIn();
    if (why == 'doc_busy') _notify(l.lawDocErrBusy);
  }

  void _toBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.position;
      if (force || p.maxScrollExtent - p.pixels < 240) _scroll.jumpTo(p.maxScrollExtent);
    });
  }

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

  /// A photo of a page, a new photo, or a PDF, Word or text file.
  Future<void> _attach({_Attach? only}) async {
    final l = context.l10n;
    if (!ref.read(isSignedInProvider)) {
      _signIn();
      return;
    }
    final s = ref.read(lawyerProvider);
    if (!s.allowed || s.busy) return;
    // One at a time: the first may be what creates the conversation.
    if (s.uploading) {
      _notify(l.lawDocErrBusy);
      return;
    }
    final choice =
        only ??
        await showActionSheet<_Attach>(
          context,
          title: l.lawAttach,
          cancelLabel: l.actionCancel,
          actions: [
            SheetAction(value: _Attach.file, label: l.lawAttachFile, icon: Icons.description_outlined),
            SheetAction(value: _Attach.photo, label: l.lawAttachPhotos, icon: Icons.photo_library_outlined),
            SheetAction(value: _Attach.camera, label: l.lawAttachCamera, icon: Icons.photo_camera_outlined),
          ],
        );
    if (choice == null || !mounted) return;
    final controller = ref.read(lawyerProvider.notifier);
    String? error;
    try {
      switch (choice) {
        case _Attach.photo:
        case _Attach.camera:
          // Large enough to read small print, small enough to stay well
          // under the 4 MB limit; re-encoded as JPEG, which the server reads.
          final x = await ImagePicker().pickImage(
            source: choice == _Attach.camera ? ImageSource.camera : ImageSource.gallery,
            maxWidth: 2400,
            maxHeight: 2400,
            imageQuality: 85,
          );
          if (x == null) return;
          final dot = x.name.lastIndexOf('.');
          final ext = dot < 0 ? 'jpg' : x.name.substring(dot + 1).toLowerCase();
          final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(RegExp('[^0-9]'), '');
          error = await controller.upload(name: 'photo-$stamp.$ext', size: await x.length(), read: x.readAsBytes);
        case _Attach.file:
          final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'docx', 'txt']);
          if (f == null) return;
          error = await controller.upload(
            name: f.name,
            size: f.lengthSync() ?? await f.length() ?? 0,
            read: f.readAsBytes,
          );
      }
    } on PlatformException {
      error = 'other';
    }
    if (error != null && mounted) _notify(docErrorText(context.l10n, error));
  }

  /// A suggested question that needs a document opens the picker first; the
  /// question waits in the box.
  void _prompt(String text, {bool needsDoc = false}) {
    final s = ref.read(lawyerProvider);
    if (needsDoc && !s.hasReadyDocs && ref.read(isSignedInProvider) && s.allowed) {
      _input.text = text;
      _notify(context.l10n.lawPickDoc);
      unawaited(_attach(only: _Attach.file));
      return;
    }
    unawaited(_send(text));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = ref.watch(lawyerProvider);
    final signedIn = ref.watch(isSignedInProvider);
    ref.listen(lawyerProvider.select((s) => s.version), (_, _) => _toBottom());
    return Column(
      children: [
        Expanded(
          child: s.turns.isEmpty
              ? _Idle(state: s, signedIn: signedIn, onPrompt: _prompt, onSignIn: _signIn)
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
                          ? UserBubble(
                              text: t.text,
                              footer: t.docs.isEmpty
                                  ? null
                                  : Padding(
                                      padding: const EdgeInsets.only(top: Space.xs),
                                      child: Wrap(
                                        spacing: Space.xxs,
                                        runSpacing: Space.xxs,
                                        children: [for (final d in t.docs) _SentDoc(doc: d)],
                                      ),
                                    ),
                            )
                          : _Answer(
                              turn: t,
                              last: i == s.turns.length - 1,
                              question: i > 0 && s.turns[i - 1].user ? s.turns[i - 1].text : '',
                              onFollowup: (q) => unawaited(_send(q)),
                              onRetry: () => unawaited(
                                ref
                                    .read(lawyerProvider.notifier)
                                    .retry(lang: context.lang, docQuestion: l.lawDocQuestion),
                              ),
                              onSignIn: _signIn,
                            ),
                    );
                  },
                ),
        ),
        AssistantComposer(
          controller: _input,
          focus: _focus,
          hint: s.turns.isEmpty ? l.lawPlaceholder : l.lawPlaceholderMore,
          label: l.lawInputLabel,
          busy: s.busy,
          maxLength: LawyerController.maxChars,
          enabled: !s.locked,
          canSendEmpty: s.hasReadyDocs && !s.uploading,
          onSend: () => unawaited(_send()),
          onStop: () => ref.read(lawyerProvider.notifier).stop(),
          onVoice: () => unawaited(_voice()),
          onAttach: () => unawaited(_attach()),
          attachLabel: l.lawAttach,
          above: s.docs.isEmpty ? null : _DocChips(docs: s.docs, busy: s.busy, onFailedTap: _notify),
        ),
      ],
    );
  }
}

/// The empty page: what Ask a Lawyer is, why this reader cannot ask yet (if
/// so), suggested questions, and the notice.
class _Idle extends StatefulWidget {
  const _Idle({required this.state, required this.signedIn, required this.onPrompt, required this.onSignIn});
  final LawyerState state;
  final bool signedIn;
  final void Function(String text, {bool needsDoc}) onPrompt;
  final VoidCallback onSignIn;

  @override
  State<_Idle> createState() => _IdleState();
}

class _IdleState extends State<_Idle> {
  bool _notice = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final s = widget.state;
    final st = s.status;
    final prompts = [
      (l.lawPrompt1, Icons.home_work_outlined, false),
      (l.lawPrompt2, Icons.public_rounded, false),
      (l.lawPrompt3, Icons.description_outlined, true),
      (l.lawPrompt4, Icons.gavel_rounded, false),
      (l.lawPrompt5, Icons.key_outlined, false),
      (l.lawPrompt6, Icons.balance_rounded, false),
    ];

    // Why this reader cannot ask yet, or that they are a reviewer.
    Widget? banner;
    if (st != null) {
      if (!st.ready) {
        banner = AssistantNotice(text: l.lawBannerNotReady, icon: Icons.cloud_off_rounded, tone: NoticeTone.warning);
      } else if (!widget.signedIn) {
        banner = _SignInBanner(text: l.lawBannerSignIn, action: l.actionSignIn, onTap: widget.onSignIn);
      } else if (!st.allowed) {
        banner = AssistantNotice(text: l.lawBannerReview, icon: Icons.hourglass_top_rounded, tone: NoticeTone.warning);
      } else if (st.reviewer && st.phase == 'review') {
        banner = AssistantNotice(text: l.lawBannerReviewer, icon: Icons.verified_user_outlined);
      }
    }
    final canAsk = st == null || (st.ready && (!widget.signedIn || st.allowed));

    return ListView(
      padding: Layout.inset(context, top: Space.lg, bottom: Space.xl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Reveal(child: LawMark()),
        const SizedBox(height: Space.md),
        Text(l.lawKicker, style: context.text.labelMedium?.copyWith(color: c.emerald, letterSpacing: 0.3)),
        const SizedBox(height: Space.xs),
        Reveal(
          index: 1,
          child: Semantics(header: true, child: Text(l.lawTitle, style: context.text.headlineMedium)),
        ),
        const SizedBox(height: Space.sm),
        Reveal(
          index: 2,
          child: Text(l.lawSub, style: context.text.bodyLarge?.copyWith(color: c.inkMuted)),
        ),
        if (st == null) ...[
          const SizedBox(height: Space.lg),
          const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
        if (banner != null) ...[const SizedBox(height: Space.lg), banner],
        if (canAsk) ...[
          const SizedBox(height: Space.lg),
          Reveal(
            index: 3,
            child: GroupedSection(
              children: [
                for (final (text, icon, needsDoc) in prompts)
                  InkWell(
                    onTap: () => widget.onPrompt(text, needsDoc: needsDoc),
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
        const SizedBox(height: Space.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 18, color: c.inkMuted),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                l.lawDisclaimerShort,
                style: context.text.bodySmall?.copyWith(color: c.inkMuted, height: 1.45),
              ),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(onPressed: () => setState(() => _notice = !_notice), child: Text(l.lawFullNotice)),
        ),
        if (_notice) Text(l.lawDisclaimer, style: context.text.bodySmall?.copyWith(color: c.inkMuted, height: 1.5)),
        if (st?.allowed ?? false) ...[
          const SizedBox(height: Space.sm),
          Text(l.lawRetention, style: context.text.bodySmall?.copyWith(color: c.inkFaint, height: 1.45)),
        ],
      ],
    );
  }
}

class _SignInBanner extends StatelessWidget {
  const _SignInBanner({required this.text, required this.action, required this.onTap});
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.emerald.withValues(alpha: 0.06), c.surface),
        borderRadius: Radii.card,
        border: Border.all(color: c.emerald.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: context.text.bodyMedium?.copyWith(height: 1.45)),
          const SizedBox(height: Space.sm),
          FilledButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

/// Ask a Lawyer's mark: the advisor's gradient, with a gavel.
class LawMark extends StatelessWidget {
  const LawMark({super.key, this.size = 56});
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
          colors: [Color(0xFF2E8F6A), Color(0xFF123C34)],
        ),
        boxShadow: [BoxShadow(color: const Color(0xFFD9B25E).withValues(alpha: 0.28), blurRadius: size * 0.5)],
      ),
      child: Icon(Icons.gavel_rounded, color: Colors.white, size: size * 0.46),
    );
  }
}

/// A document sent with a question, under it.
class _SentDoc extends StatelessWidget {
  const _SentDoc({required this.doc});
  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.chip,
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(doc.kind == 'image' ? Icons.image_outlined : Icons.description_outlined, size: 14, color: c.inkMuted),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
          ),
        ],
      ),
    );
  }
}

/// The documents waiting to go with the next question, over the box.
class _DocChips extends ConsumerWidget {
  const _DocChips({required this.docs, required this.busy, required this.onFailedTap});
  final List<LegalDoc> docs;
  final bool busy;
  final ValueChanged<String> onFailedTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in docs) ...[
            Semantics(
              label: d.state == DocState.failed ? '${d.name}: ${docErrorText(l, d.error ?? 'other')}' : d.name,
              child: GestureDetector(
                onTap: d.state == DocState.failed ? () => onFailedTap(docErrorText(l, d.error ?? 'other')) : null,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsetsDirectional.fromSTEB(Space.sm, Space.xs, Space.xxs, Space.xs),
                  decoration: BoxDecoration(
                    color: d.state == DocState.failed ? c.danger.withValues(alpha: 0.06) : c.surface,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: d.state == DocState.failed ? c.danger.withValues(alpha: 0.35) : c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (d.state == DocState.uploading)
                        SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.emerald),
                        )
                      else
                        Icon(
                          d.state == DocState.failed
                              ? Icons.error_outline_rounded
                              : (d.kind == 'image' ? Icons.image_outlined : Icons.description_outlined),
                          size: 18,
                          color: d.state == DocState.failed ? c.danger : c.inkMuted,
                        ),
                      const SizedBox(width: Space.xs),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium),
                            Text(
                              docMeta(l, d),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelSmall?.copyWith(
                                color: d.state == DocState.failed ? c.danger : c.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (d.state != DocState.uploading && !busy)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '${l.lawDocRemove}: ${d.name}',
                          onPressed: () => ref.read(lawyerProvider.notifier).removeDoc(d.key),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        )
                      else
                        const SizedBox(width: Space.xs),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.xs),
          ],
        ],
      ),
    );
  }
}

/// "Uploading…", "Couldn't add", or what the document is: "3 pages · scan".
String docMeta(AppLocalizations l, LegalDoc d) {
  if (d.state == DocState.uploading) return l.lawDocUploading;
  if (d.state == DocState.failed) return l.lawDocFailed;
  final kindWord = d.kind == 'image' ? l.lawDocPhoto : (d.kind == 'docx' || d.kind == 'txt' ? l.lawDocText : '');
  return [
    if (d.pages != null && d.pages! > 0 && d.kind != 'image')
      l.lawDocPages(d.pages!)
    else if (kindWord.isNotEmpty)
      kindWord,
    if (d.scanned && d.kind == 'pdf') l.lawDocScan,
  ].join(' · ');
}

/// Why a document could not be added, in the reader's words.
String docErrorText(AppLocalizations l, String code) => switch (code) {
  'too_big' => l.lawDocErrTooBig,
  'unsupported' => l.lawDocErrUnsupported,
  'old_word' => l.lawDocErrOldWord,
  'encrypted' => l.lawDocErrEncrypted,
  'active_content' => l.lawDocErrActiveContent,
  'macros' => l.lawDocErrMacros,
  'damaged' => l.lawDocErrDamaged,
  'too_many_pages' => l.lawDocErrTooManyPages,
  'not_text' => l.lawDocErrNotText,
  'no_text' => l.lawDocErrNoText,
  'too_long' => l.lawDocErrTooLong,
  'empty' => l.lawDocErrEmpty,
  'too_many_documents' => l.lawDocErrTooMany,
  'conversation_full' => l.lawDocErrFull,
  'rate_limited' => l.lawDocErrRateLimited,
  'offline' => l.lawDocErrOffline,
  'busy' => l.lawDocErrBusy,
  'sign_in' => l.lawErrSignIn,
  'not_open' => l.lawErrNotOpen,
  'not_configured' => l.lawErrNotConfigured,
  _ => l.lawDocErrOther,
};

/// What an answer could not do, in the reader's words.
String lawyerErrorText(AppLocalizations l, String code) => switch (code) {
  'rate_limited' => l.lawErrRateLimited,
  'quota' => l.lawErrQuota,
  'quota_total' => l.lawErrQuotaTotal,
  'busy' => l.lawErrBusy,
  'not_configured' => l.lawErrNotConfigured,
  'too_long' => l.lawErrTooLong,
  'offline' => l.lawErrOffline,
  'interrupted' => l.lawErrInterrupted,
  'sign_in' => l.lawErrSignIn,
  'not_open' => l.lawErrNotOpen,
  'not_found' => l.lawErrNotFound,
  _ => l.lawErrOther,
};

String lawyerDoing(AppLocalizations l, LegalStep? st) {
  if (st == null) return l.lawThinking;
  return switch (st.s) {
    'writing' => l.lawWriting,
    'documents' => l.lawDoingDocuments,
    'library' => l.lawDoingLibrary,
    'lookup' => l.lawDoingLookup,
    'web_search' => l.lawDoingWebSearch,
    'web_fetch' => st.host.isEmpty ? l.lawDoingWebFetchSource : l.lawDoingWebFetch(st.host),
    _ => l.lawDoingOther,
  };
}

String lawyerDid(AppLocalizations l, LegalStep st) => switch (st.s) {
  'documents' => l.lawDidDocuments,
  'library' => st.q.isEmpty ? l.lawDidLibrary : l.lawDidLibraryFor(st.q),
  'lookup' => st.q.isEmpty ? l.lawDidLookup : l.lawDidLookupFor(st.q),
  'web_search' => st.q.isEmpty ? l.lawDidWebSearch : l.lawDidWebSearchFor(st.q),
  'web_fetch' => st.host.isEmpty ? l.lawDidWebFetchSource : l.lawDidWebFetch(st.host),
  _ => st.s,
};

/// The research behind an answer, in one line: "Legal library · 2 searches".
String lawyerSummary(AppLocalizations l, List<LegalStep> steps) {
  int count(String k) => steps.where((x) => x.s == k).length;
  final bits = [
    if (count('library') + count('lookup') > 0) l.lawSummaryLibrary,
    if (count('web_search') > 0) l.lawSummarySearches(count('web_search')),
    if (count('web_fetch') > 0) l.lawSummarySources(count('web_fetch')),
    if (count('documents') > 0) l.lawSummaryDocuments,
  ];
  return bits.isEmpty ? l.lawDoingOther : bits.join(' · ');
}

/// The notice in the language the answer was written in.
String lawyerDisclaimer(AppLocalizations l, String? lang) {
  if (lang == null || lang == l.localeName) return l.lawDisclaimer;
  return lang == 'ar' ? _disclaimerAr : _disclaimerEn;
}

const _disclaimerEn =
    'This information is AI-generated legal guidance for general informational purposes, not a substitute for '
    'professional legal advice. Jordanian laws and their interpretation may change. Consult a licensed Jordanian '
    'lawyer to verify the information and its applicability to your situation. Conduct your own research before '
    'making any legal decision.';
const _disclaimerAr =
    'هذه المعلومات إرشادات قانونية مولّدة بالذكاء الاصطناعي ولأغراض التوعية العامة، ولا تُغني عن استشارة محامٍ أردني '
    'مرخّص. قد تتغير القوانين وتفسيراتها، لذلك يُرجى مراجعة محامٍ مختص للتحقق من دقة المعلومات ومدى انطباقها على '
    'حالتك، وإجراء بحثك الخاص قبل اتخاذ أي قرار قانوني.';

/// What kind of source it is, said plainly: verified law and its status, a
/// judgment, commentary, an official site, secondary reporting, or the
/// reader's own document.
String sourceBadgeLabel(AppLocalizations l, LegalSource x) {
  if (x.kind == 'library') {
    if (x.judgment) return l.lawBadgeJudgment;
    if (x.commentary) return l.lawBadgeCommentary;
    return switch (x.status) {
      'in_force' => l.lawBadgeInForce,
      'amended' => l.lawBadgeAmended,
      'repealed' => l.lawBadgeRepealed,
      _ => l.lawBadgeLaw,
    };
  }
  return switch (x.kind) {
    'official' => l.lawBadgeOfficial,
    'secondary' => l.lawBadgeSecondary,
    _ => l.lawBadgeDocument,
  };
}

/// The badge's colour: green for law in force and judgments, amber for
/// amended law and the reader's documents, red for repealed law.
Color sourceBadgeColor(LegalSource x, AkaratColors c) {
  if (x.kind == 'library') {
    if (x.commentary && !x.judgment) return c.inkMuted;
    return switch (x.status) {
      'amended' when !x.judgment => c.warning,
      'repealed' when !x.judgment => c.danger,
      _ => c.forest,
    };
  }
  return switch (x.kind) {
    'official' => c.ink,
    'secondary' => c.inkMuted,
    _ => c.warning,
  };
}

/// When it was checked, where it is from, or the page of the document.
String sourceMeta(AppLocalizations l, LegalSource x, String lang) {
  String date(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null || d.year < 2000 ? raw : Fmt.date(d, lang: lang);
  }

  if (x.kind == 'library') {
    return [
      if (x.verified != null) l.lawChecked(date(x.verified!)),
      x.licensed ? l.lawLicensed : x.host,
    ].where((b) => b.isNotEmpty).join(' · ');
  }
  if (x.kind == 'document') return x.page == null ? '' : l.lawPage(x.page!);
  return [x.host, if (x.date != null) date(x.date!)].where((b) => b.isNotEmpty).join(' · ');
}

/// An answer as plain text, for copying: citation numbers in brackets, its
/// sources, and the notice in the answer's language.
String plainAnswer(AppLocalizations l, LegalTurn t) {
  final body = t.text.replaceAllMapped(RegExp('$citeOpen([0-9,]+)$citeClose'), (m) => ' [${m[1]}]').trim();
  final sources = [for (final x in t.sources) '[${x.n}] ${x.title}${x.url.isEmpty ? '' : ' — ${x.url}'}'].join('\n');
  return [body, if (sources.isNotEmpty) '${l.lawSources}:\n$sources', lawyerDisclaimer(l, t.lang)].join('\n\n');
}

/// The whole conversation as a research summary, to send to a lawyer or
/// keep: each question, its answer, sources, unverified references and the
/// notice.
String researchSummary(AppLocalizations l, LawyerState s, String lang) {
  final out = StringBuffer()
    ..writeln(l.lawSummaryHeading)
    ..writeln(s.title.isEmpty ? l.lawName : s.title)
    ..writeln(Fmt.date(DateTime.now(), lang: lang));
  for (var i = 0; i < s.turns.length; i++) {
    final t = s.turns[i];
    if (t.user || t.redacted != null || !t.hasText) continue;
    final q = i > 0 && s.turns[i - 1].user ? s.turns[i - 1].text : '';
    out
      ..writeln()
      ..writeln('────────')
      ..writeln();
    if (q.isNotEmpty) {
      out
        ..writeln('${l.lawSummaryQuestion} $q')
        ..writeln();
    }
    out.writeln(t.text.replaceAllMapped(RegExp('$citeOpen([0-9,]+)$citeClose'), (m) => ' [${m[1]}]').trim());
    if (t.sources.isNotEmpty) {
      out
        ..writeln()
        ..writeln('${l.lawSources}:');
      for (final x in t.sources) {
        final meta = sourceMeta(l, x, lang);
        out.writeln(
          '[${x.n}] ${sourceBadgeLabel(l, x)}: ${x.title}'
          '${meta.isEmpty ? '' : ' ($meta)'}${x.url.isEmpty ? '' : ' — ${x.url}'}',
        );
      }
    }
    if (t.unverified.isNotEmpty) {
      out
        ..writeln()
        ..writeln('${l.lawSummaryUnverified} ${t.unverified.join('; ')}');
    }
    out
      ..writeln()
      ..writeln(lawyerDisclaimer(l, t.lang));
  }
  return out.toString().trim();
}

/// One answer: the research steps, any urgent warning, the answer in
/// sections with its citations and unverified references marked, its
/// sources, the notice, and what to do with it.
class _Answer extends ConsumerWidget {
  const _Answer({
    required this.turn,
    required this.last,
    required this.question,
    required this.onFollowup,
    required this.onRetry,
    required this.onSignIn,
  });
  final LegalTurn turn;
  final bool last;
  final String question;
  final ValueChanged<String> onFollowup;
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final working = turn.state == LegalTurnState.working;
    final hosts = {
      Uri.parse(Env.siteUrl).host.replaceFirst(RegExp(r'^www\.'), ''),
      for (final s in turn.sources)
        if (s.host.isNotEmpty) s.host.replaceFirst(RegExp(r'^www\.'), ''),
    };
    final children = <Widget>[];
    void gap([double h = Space.sm]) => children.add(SizedBox(height: h));

    children.add(
      Row(
        children: [
          const LawMark(size: 26),
          const SizedBox(width: Space.xs),
          Text(l.lawName, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    gap();
    if (working && !turn.hasText) {
      children.add(WorkingLine(text: lawyerDoing(l, turn.current)));
      gap();
    } else if (turn.steps.isNotEmpty) {
      children.add(
        StepsSummary(label: lawyerSummary(l, turn.steps), steps: [for (final st in turn.steps) lawyerDid(l, st)]),
      );
      gap();
    }
    final urgent = turn.urgent;
    if (urgent != null && urgent.text.isNotEmpty) {
      children.add(
        AssistantNotice(
          text: '${urgent.level == 'urgent' ? l.lawUrgent : l.lawImportant} ${urgent.text}',
          icon: Icons.priority_high_rounded,
          tone: urgent.level == 'urgent' ? NoticeTone.danger : NoticeTone.warning,
        ),
      );
      gap();
    }
    if (turn.redacted != null) {
      children.add(
        AssistantNotice(
          text: turn.redacted == 'leak' ? l.lawLeak : l.lawRefused,
          icon: Icons.block_rounded,
          tone: NoticeTone.warning,
        ),
      );
      gap();
    }
    if (turn.hasText) {
      children.add(
        ReplyView(
          text: turn.text,
          sections: true,
          linkHosts: hosts,
          unverified: turn.unverified,
          unverifiedLabel: l.lawUnverifiedMark,
          onCite: (n) => _openSource(context, n),
        ),
      );
      gap();
    }
    if (working && turn.hasText) {
      children.add(WorkingLine(text: lawyerDoing(l, turn.current)));
      gap();
    }
    for (final kind in turn.notices) {
      final text = switch (kind) {
        'partial' => l.lawNoticePartial,
        'stopped' => l.lawNoticeStopped,
        'unbacked_claim' => l.lawNoticeUnbacked,
        _ => '',
      };
      if (text.isEmpty) continue;
      children.add(AssistantNotice(text: text, tone: kind == 'unbacked_claim' ? NoticeTone.warning : NoticeTone.info));
      gap();
    }
    if (turn.state == LegalTurnState.error) {
      final code = turn.error ?? 'unavailable';
      children.add(
        AssistantNotice(text: lawyerErrorText(l, code), icon: Icons.error_outline_rounded, tone: NoticeTone.danger),
      );
      gap(Space.xs);
      children.add(
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            if (lawyerRetryCodes.contains(code))
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l.actionRetry),
              ),
            if (code == 'sign_in') FilledButton(onPressed: onSignIn, child: Text(l.actionSignIn)),
            if (code == 'not_found')
              OutlinedButton.icon(
                onPressed: () => ref.read(lawyerProvider.notifier).newConversation(),
                icon: const Icon(Icons.edit_square, size: 18),
                label: Text(l.aiHubNewChat),
              ),
          ],
        ),
      );
      gap();
    }
    if (turn.unverified.isNotEmpty && !working) {
      children.add(_UnverifiedBox(refs: turn.unverified));
      gap();
    }
    if (turn.sources.isNotEmpty) {
      children.add(_Sources(sources: turn.sources));
      gap();
    }
    // The notice goes under every answer, in the answer's language.
    if (turn.hasText && !working) {
      children.add(
        Text(
          lawyerDisclaimer(l, turn.lang),
          textDirection: (turn.lang ?? lang) == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          style: context.text.bodySmall?.copyWith(color: c.inkMuted, height: 1.45),
        ),
      );
      gap(Space.xs);
      children.add(_Actions(turn: turn));
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
    if (uri != null && uri.scheme == 'https') {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    } else {
      // A document or a library entry without a page: say what it is.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('[${s.n}] ${s.title}')));
    }
  }
}

class _UnverifiedBox extends StatelessWidget {
  const _UnverifiedBox({required this.refs});
  final List<String> refs;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.danger.withValues(alpha: 0.05), c.surface),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_gmailerrorred_rounded, size: 18, color: c.danger),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(l.lawUnverifiedTitle, style: context.text.titleSmall)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(l.lawUnverifiedBody, style: context.text.bodySmall?.copyWith(height: 1.45)),
          const SizedBox(height: Space.xxs),
          for (final r in refs)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $r',
                textDirection: isArabicText(r) ? TextDirection.rtl : TextDirection.ltr,
                style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources({required this.sources});
  final List<LegalSource> sources;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.lawSources, style: context.text.labelLarge?.copyWith(color: c.inkMuted)),
        const SizedBox(height: Space.xs),
        for (final s in sources)
          _SourceRow(
            source: s,
            badge: (label: sourceBadgeLabel(l, s), color: sourceBadgeColor(s, c)),
            meta: sourceMeta(l, s, lang),
          ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.badge, required this.meta});
  final LegalSource source;
  final ({String label, Color color}) badge;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = source;
    final uri = Uri.tryParse(s.url);
    final link = uri != null && uri.scheme == 'https';
    final quote = s.quote.isNotEmpty && (s.kind == 'library' || s.kind == 'document') ? s.quote : '';
    return InkWell(
      onTap: link ? () => unawaited(launchUrl(uri, mode: LaunchMode.externalApplication)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badge.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Text(
                      badge.label,
                      style: context.text.labelSmall?.copyWith(color: badge.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.title.isEmpty ? s.host : s.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textDirection: isArabicText(s.title) ? TextDirection.rtl : TextDirection.ltr,
                    style: context.text.bodyMedium?.copyWith(color: link ? c.emerald : c.ink),
                  ),
                  if (meta.isNotEmpty) Text(meta, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
                  if (quote.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: Space.xxs),
                      padding: const EdgeInsetsDirectional.only(start: Space.xs),
                      decoration: BoxDecoration(
                        border: BorderDirectional(start: BorderSide(color: c.border, width: 2)),
                      ),
                      child: Text(
                        '“$quote”',
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        textDirection: isArabicText(quote) ? TextDirection.rtl : TextDirection.ltr,
                        style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic, height: 1.45),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy, share the research summary, report a problem.
class _Actions extends ConsumerWidget {
  const _Actions({required this.turn});
  final LegalTurn turn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Wrap(
      spacing: Space.xxs,
      children: [
        TextButton.icon(
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: plainAnswer(l, turn))));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(l.aiHubCopied), duration: const Duration(seconds: 2)));
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(l.aiHubCopy),
        ),
        Builder(
          builder: (button) => TextButton.icon(
            onPressed: () {
              final s = ref.read(lawyerProvider);
              final text = researchSummary(l, s, context.lang);
              unawaited(
                SharePlus.instance.share(
                  ShareParams(text: text, subject: l.lawSummaryHeading, sharePositionOrigin: shareOrigin(button)),
                ),
              );
            },
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: Text(l.lawShareSummary),
          ),
        ),
        if (turn.messageId != null)
          TextButton.icon(
            onPressed: turn.reported ? null : () => unawaited(showReportSheet(context, turn)),
            icon: Icon(turn.reported ? Icons.check_rounded : Icons.flag_outlined, size: 18),
            label: Text(turn.reported ? l.lawReported : l.lawReport),
          ),
      ],
    );
  }
}

/// "Report a problem": what was wrong with the answer, and a note.
Future<void> showReportSheet(BuildContext context, LegalTurn turn) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ReportSheet(turn: turn),
);

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.turn});
  final LegalTurn turn;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _note = TextEditingController();
  String? _kind;
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final kind = _kind;
    if (kind == null || _sending) return;
    final l = context.l10n;
    setState(() {
      _sending = true;
      _failed = false;
    });
    final error = await ref.read(lawyerProvider.notifier).report(widget.turn, kind: kind, note: _note.text.trim());
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _sending = false;
        _failed = true;
      });
      return;
    }
    // On the root overlay, so it stays while the sheet closes.
    showSuccess(context, l.lawFbSent);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final reviewer = ref.watch(lawyerProvider.select((s) => s.status?.reviewer ?? false));
    final kinds = {
      'good': l.lawFbGood,
      'wrong_law': l.lawFbWrongLaw,
      'wrong_citation': l.lawFbWrongCitation,
      'outdated': l.lawFbOutdated,
      'fabricated': l.lawFbFabricated,
      'missing': l.lawFbMissing,
      'unclear': l.lawFbUnclear,
      'other': l.lawFbOther,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.lawFbTitle, style: context.text.titleLarge),
            const SizedBox(height: Space.sm),
            RadioGroup<String>(
              groupValue: _kind,
              onChanged: (v) => setState(() => _kind = v),
              child: Column(
                children: [
                  for (final k in feedbackKinds)
                    RadioListTile<String>.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: k,
                      title: Text(kinds[k]!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: l.lawFbPlaceholder, counterText: ''),
            ),
            if (reviewer) ...[
              const SizedBox(height: Space.xs),
              Text(l.lawFbReviewerNote, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
            ],
            if (_failed) ...[
              const SizedBox(height: Space.xs),
              Text(l.lawFbFailed, style: context.text.bodySmall?.copyWith(color: c.danger)),
            ],
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: _kind == null || _sending ? null : () => unawaited(_send()),
              child: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.lawFbSend),
            ),
          ],
        ),
      ),
    );
  }
}

/// The account's legal conversations: open one, delete one, or delete all.
Future<void> showLawyerHistory(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const _HistorySheet(),
);

class _HistorySheet extends ConsumerStatefulWidget {
  const _HistorySheet();

  @override
  ConsumerState<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<_HistorySheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(lawyerProvider.notifier).loadHistory());
    });
  }

  void _notify(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(String id) async {
    final l = context.l10n;
    final error = await ref.read(lawyerProvider.notifier).open(id);
    if (!mounted) return;
    if (error != null) {
      _notify(lawyerErrorText(l, error));
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _delete(LegalConversation h) async {
    final l = context.l10n;
    final ok = await confirmAction(
      context,
      title: l.lawDeleteOne,
      body: h.title.isEmpty ? l.lawName : h.title,
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final error = await ref.read(lawyerProvider.notifier).delete(h.id);
    if (mounted) _notify(error == null ? l.lawDeleted : lawyerErrorText(l, error));
  }

  Future<void> _deleteAll() async {
    final l = context.l10n;
    final ok = await confirmAction(
      context,
      title: l.lawDeleteAll,
      body: l.lawConfirmAll,
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final error = await ref.read(lawyerProvider.notifier).delete('all');
    if (mounted) _notify(error == null ? l.lawAllDeleted : lawyerErrorText(l, error));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final s = ref.watch(lawyerProvider);
    final history = s.history;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, Space.lg),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Text(l.lawHistoryTitle, style: context.text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.sm),
            child: Text(l.lawRetention, style: context.text.bodySmall?.copyWith(color: c.inkMuted, height: 1.45)),
          ),
          if (history == null && !s.historyError)
            const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (s.historyError || history!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.lg),
              child: Text(
                s.historyError ? l.lawHistoryError : l.lawHistoryEmpty,
                style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
              ),
            )
          else ...[
            for (final h in history)
              ListTile(
                contentPadding: const EdgeInsetsDirectional.only(start: Space.gutter, end: Space.xs),
                selected: h.id == s.conversationId,
                selectedTileColor: c.emerald.withValues(alpha: 0.06),
                leading: Icon(Icons.chat_bubble_outline_rounded, color: c.inkMuted),
                title: Text(
                  h.title.isEmpty ? l.lawName : h.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: isArabicText(h.title) ? TextDirection.rtl : TextDirection.ltr,
                ),
                subtitle: h.updatedAt == null ? null : Text(Fmt.date(h.updatedAt!.toLocal(), lang: lang)),
                onTap: s.busy ? null : () => unawaited(_open(h.id)),
                trailing: IconButton(
                  tooltip: l.lawDeleteOne,
                  onPressed: () => unawaited(_delete(h)),
                  icon: Icon(Icons.delete_outline_rounded, color: c.inkMuted),
                ),
              ),
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  onPressed: () => unawaited(_deleteAll()),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(l.lawDeleteAll),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
