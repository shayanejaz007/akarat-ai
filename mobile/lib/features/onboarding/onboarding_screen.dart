import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/brand.dart';
import '../../shared/services/preferences.dart';
import '../settings/settings_controller.dart';

/// Three short pages, once. Skippable from the first. Nobody is asked to make
/// an account to look at property.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.next});
  final String? next;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(preferencesProvider).setOnboarded();
    if (mounted) context.go(widget.next ?? Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final pages = [
      (Icons.location_city_rounded, l.onboardingTitle1, l.onboardingBody1),
      (Icons.auto_awesome, l.onboardingTitle2, l.onboardingBody2),
      (Icons.key_rounded, l.onboardingTitle3, l.onboardingBody3),
    ];
    final last = _index == pages.length - 1;
    final size = MediaQuery.sizeOf(context);

    // The photo runs under the status bar: its icons go white.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.background,
        body: Column(
          children: [
            SizedBox(
              height: size.height * (size.height < 700 ? 0.44 : 0.54),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/jordan-hero.jpg',
                    fit: BoxFit.cover,
                    cacheWidth: (size.width * 2).round(),
                    excludeFromSemantics: true,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent, c.background],
                        stops: const [0, 0.5, 1],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
                        child: Row(
                          children: [
                            // With large text on a narrow phone the two no
                            // longer fit: the wordmark gives way, not the
                            // switch.
                            const Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                // As tall as the wordmark, not the photo.
                                heightFactor: 1,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Wordmark(color: Colors.white, size: 30),
                                ),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            LanguageSwitch(
                              lang: context.lang,
                              onDark: true,
                              onChanged: (lang) => ref.read(localeProvider.notifier).set(lang),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final (icon, title, body) = pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: c.emerald, size: 26),
                        const SizedBox(height: Space.md),
                        Semantics(header: true, child: Text(title, style: context.text.headlineMedium)),
                        const SizedBox(height: Space.sm),
                        Text(body, style: context.text.bodyLarge?.copyWith(color: c.inkMuted)),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
                child: Row(
                  children: [
                    _Dots(count: pages.length, index: _index),
                    const Spacer(),
                    if (!last) TextButton(onPressed: _finish, child: Text(l.actionSkip)),
                    const SizedBox(width: Space.xs),
                    FilledButton(
                      onPressed: last
                          ? _finish
                          : () => _pages.nextPage(duration: Motion.of(context, Motion.normal), curve: Motion.standard),
                      child: Text(last ? l.actionGetStarted : l.actionNext),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: Motion.of(context, Motion.normal),
              margin: const EdgeInsetsDirectional.only(end: 6),
              width: i == index ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(color: i == index ? c.forest : c.border, borderRadius: Radii.chip),
            ),
        ],
      ),
    );
  }
}
