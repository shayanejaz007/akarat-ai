import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/segmented_pill.dart';
import '../advisor/advisor_controller.dart';
import '../advisor/advisor_view.dart';
import '../lawyer/lawyer_controller.dart';
import '../lawyer/lawyer_view.dart';

enum AiMode { advisor, lawyer }

/// The AI tab: the website's two assistants, side by side. Property AI finds,
/// compares and weighs up property; Ask a Lawyer answers questions about
/// Jordanian law. Each keeps its conversation while the reader switches
/// between them.
class AiHubScreen extends ConsumerStatefulWidget {
  const AiHubScreen({super.key, this.mode, this.modeToken, this.initialQuery, this.focusToken, this.voiceToken});

  /// 'lawyer' opens Ask a Lawyer; anything else, Property AI.
  final String? mode;

  /// Changes each time a link asks for [mode] again, so it switches even
  /// when the reader has switched away since.
  final String? modeToken;

  /// For Property AI: asked straight away.
  final String? initialQuery;

  /// For Property AI: Home's search field (the keyboard comes up).
  final String? focusToken;

  /// For Property AI: Home's microphone (dictation opens).
  final String? voiceToken;

  @override
  ConsumerState<AiHubScreen> createState() => _AiHubScreenState();
}

class _AiHubScreenState extends ConsumerState<AiHubScreen> {
  late AiMode _mode = _asked(widget.mode);

  /// Ask a Lawyer is built the first time it is opened, so its status is
  /// only asked for by readers who go there.
  late bool _lawyerOpened = _mode == AiMode.lawyer;

  static AiMode _asked(String? mode) => mode == 'lawyer' ? AiMode.lawyer : AiMode.advisor;

  @override
  void didUpdateWidget(AiHubScreen old) {
    super.didUpdateWidget(old);
    if (widget.mode != old.mode || widget.modeToken != old.modeToken) {
      _switch(_asked(widget.mode));
    }
    // Anything meant for Property AI brings it forward.
    if ((widget.initialQuery != null && widget.initialQuery != old.initialQuery) ||
        (widget.focusToken != null && widget.focusToken != old.focusToken) ||
        (widget.voiceToken != null && widget.voiceToken != old.voiceToken)) {
      _switch(AiMode.advisor);
    }
  }

  void _switch(AiMode mode) {
    if (mode == _mode) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = mode;
      if (mode == AiMode.lawyer) _lawyerOpened = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final advisorStarted = ref.watch(advisorProvider.select((s) => !s.isEmpty));
    final lawyer = ref.watch(
      lawyerProvider.select((s) => (open: s.turns.isNotEmpty || s.docs.isNotEmpty, allowed: s.allowed)),
    );
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final pillHeight = 34 * scaler.scale(1) < 40 ? 40.0 : 34 * scaler.scale(1);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.aiTitle),
        actions: [
          if (_mode == AiMode.advisor) ...[
            // The listings search on its own, as before the advisor.
            IconButton(
              tooltip: l.aiHubPlainSearch,
              onPressed: () => context.go(Routes.plainSearch),
              icon: const Icon(Icons.manage_search_rounded),
            ),
            if (advisorStarted)
              IconButton(
                tooltip: l.aiHubNewChat,
                onPressed: () => ref.read(advisorProvider.notifier).reset(),
                icon: const Icon(Icons.edit_square),
              ),
          ] else ...[
            if (lawyer.allowed)
              IconButton(
                tooltip: l.lawHistory,
                onPressed: () => showLawyerHistory(context),
                icon: const Icon(Icons.history_rounded),
              ),
            if (lawyer.open)
              IconButton(
                tooltip: l.aiHubNewChat,
                onPressed: () => ref.read(lawyerProvider.notifier).newConversation(),
                icon: const Icon(Icons.edit_square),
              ),
          ],
          const SizedBox(width: Space.xs),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(pillHeight + Space.sm),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
            child: SegmentedPill<AiMode>(
              expand: true,
              value: _mode,
              onChanged: _switch,
              segments: [
                PillSegment(value: AiMode.advisor, label: l.aiHubAdvisor, icon: Icons.auto_awesome),
                PillSegment(value: AiMode.lawyer, label: l.aiHubLawyer, icon: Icons.gavel_rounded),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _mode.index,
        children: [
          // Only the one on screen takes part in focus and accessibility.
          _Pane(
            active: _mode == AiMode.advisor,
            child: AdvisorView(
              initialQuery: widget.initialQuery,
              focusToken: widget.focusToken,
              voiceToken: widget.voiceToken,
            ),
          ),
          _Pane(active: _mode == AiMode.lawyer, child: _lawyerOpened ? const LawyerView() : const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !active,
    child: ExcludeSemantics(
      excluding: !active,
      child: TickerMode(enabled: active, child: child),
    ),
  );
}
