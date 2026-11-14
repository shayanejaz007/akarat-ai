import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../advisor/advisor_controller.dart';
import '../advisor/advisor_view.dart';

/// The AI tab: Property AI, the website's property advisor. It finds,
/// compares and weighs up property, and the plain listings search is one tap
/// away in the app bar.
class AiHubScreen extends ConsumerWidget {
  const AiHubScreen({super.key, this.initialQuery, this.focusToken, this.voiceToken});

  /// Asked straight away.
  final String? initialQuery;

  /// Home's search field (the keyboard comes up).
  final String? focusToken;

  /// Home's microphone (dictation opens).
  final String? voiceToken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final started = ref.watch(advisorProvider.select((s) => !s.isEmpty));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.aiTitle),
        actions: [
          // The listings search on its own, as before the advisor.
          IconButton(
            tooltip: l.aiHubPlainSearch,
            onPressed: () => context.go(Routes.plainSearch),
            icon: const Icon(Icons.manage_search_rounded),
          ),
          if (started)
            IconButton(
              tooltip: l.aiHubNewChat,
              onPressed: () => ref.read(advisorProvider.notifier).reset(),
              icon: const Icon(Icons.edit_square),
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: AdvisorView(initialQuery: initialQuery, focusToken: focusToken, voiceToken: voiceToken),
    );
  }
}
