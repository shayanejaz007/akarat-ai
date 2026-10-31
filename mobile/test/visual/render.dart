import 'dart:io';

import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/features/tour/tour.dart';
import 'package:akarat/shared/services/supabase_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Device frames the renders are taken at.
class Device {
  const Device(this.name, this.size);
  final String name;
  final Size size;

  static const compact = Device('compact', Size(360, 740)); // small Android
  static const phone = Device('phone', Size(390, 844)); // iPhone 15/16
  static const large = Device('large', Size(430, 932)); // Pro Max
  static const tablet = Device('tablet', Size(820, 1180)); // iPad Air portrait
  static const landscape = Device('landscape', Size(844, 390));
}

Future<void> loadRealFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  await family('Inter', [for (final w in weights) 'assets/fonts/Inter-$w.ttf']);
  await family('InterDisplay', [
    for (final w in ['Medium', 'SemiBold', 'Bold']) 'assets/fonts/InterDisplay-$w.ttf',
  ]);
  await family('Poppins', ['assets/fonts/Poppins-SemiBold.ttf']);
  await family('IBMPlexSansArabic', [for (final w in weights) 'assets/fonts/IBMPlexSansArabic-$w.ttf']);
  // The SDK's icon font. Tests run in flutter_tester, which lives in
  // <sdk>/bin/cache/artifacts/engine/<platform>/, so the SDK is found from it
  // when FLUTTER_ROOT isn't set.
  final tester = File(Platform.resolvedExecutable);
  final root = Platform.environment['FLUTTER_ROOT'] ?? tester.parent.parent.parent.parent.parent.parent.path;
  await family('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf']);
}

/// Renders [screen] and writes `goldens/<folder>/<name>.png`.
Future<void> render(
  WidgetTester tester,
  String name,
  Widget screen, {
  required List<Override> overrides,
  String lang = 'en',
  Brightness brightness = Brightness.light,
  Device device = Device.phone,
  double textScale = 1,
  String folder = 'audit',
  Future<void> Function(WidgetTester)? interact,
}) async {
  tester.view.physicalSize = device.size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  // flutter_test draws elevation as a solid outline; these renders are for
  // judging the design, so draw real shadows and put the flag back after.
  debugDisableShadows = false;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(lang),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          theme: AppTheme.build(brightness: brightness, lang: lang),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  if (interact != null) {
    await interact(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  try {
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/$folder/$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}

/// [child] under the floating tab bar, laid out as the app's shell does it:
/// the bar floats over the content, which keeps clear of it.
Widget withNav(Widget child, int index) => Scaffold(
  body: Consumer(
    builder: (context, ref, _) {
      final mq = MediaQuery.of(context);
      final lift = mq.padding.bottom < 12 ? 12.0 : mq.padding.bottom;
      return Stack(
        children: [
          MediaQuery(
            data: mq.copyWith(padding: mq.padding.copyWith(bottom: ScaffoldWithNav.barHeight + lift + 8)),
            child: child,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: lift,
            child: Builder(
              builder: (context) {
                final t = ref.watch(tourTargetsProvider);
                return AkaratNavBar(
                  index: index,
                  signedIn: ref.watch(isSignedInProvider),
                  onSelect: (_) {},
                  // The tabs the main tour points at, as in the app.
                  tabKeys: t.navTabs,
                );
              },
            ),
          ),
        ],
      );
    },
  ),
);
