// Renders the finished vector logo for the native launch screens, so they
// match the opening's first frame exactly.
//
//   flutter test test/visual/launch_logo_test.dart --run-skipped
//
// Writes build/launch_logo.png (a 1080-unit square at 4 px per unit, on
// transparency); tool/make_launch_images.py cuts the Android and iOS images
// from it.
@Tags(['visual'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:akarat/core/widgets/akarat_logo_animated.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the finished logo, for the launch screens', (tester) async {
    tester.view.physicalSize = const Size(1080, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(key: key, child: const AkaratLogoAnimated(size: 1080, animate: false)),
        ),
      ),
    );
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 4);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/launch_logo.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  });
}
