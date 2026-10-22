// The opening's coded logo animation, frame by frame, for review.
//
//   flutter test test/visual/splash_test.dart --update-goldens --run-skipped
@Tags(['visual'])
library;

import 'package:akarat/app/launch_splash.dart';
import 'package:akarat/core/widgets/akarat_logo_animated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final ms in [300, 900, 1500, 2200, 2900, 3750]) {
    testWidgets('logo build at $ms ms', (tester) async {
      tester.view.physicalSize = const Size(400, 400) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      await tester.pumpWidget(
        const RepaintBoundary(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: LaunchSplash.ground,
              child: Center(child: AkaratLogoAnimated(size: 380)),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration(milliseconds: ms));
      await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/splash/logo_$ms.png'));
      debugDisableShadows = true;
    });
  }
}
