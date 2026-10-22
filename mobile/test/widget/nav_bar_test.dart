import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/harness.dart';

const _names = ['Home', 'Explore', 'AI Search', 'Saved'];

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    for (final signedIn in [true, false]) {
      testWidgets('${width.toInt()} px, ${signedIn ? 'signed in' : 'signed out'}: no tab name is cut short', (
        tester,
      ) async {
        for (var index = 0; index < 4; index++) {
          await pumpScreen(
            tester,
            Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AkaratNavBar(index: index, signedIn: signedIn, onSelect: (_) {}),
              ),
            ),
            overrides: await TestDeps().overrides(),
            size: Size(width, 800),
          );
          await tester.pumpAndSettle();
          for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
            expect(p.didExceedMaxLines, isFalse, reason: '"${p.text.toPlainText()}" fits');
          }
          // Shown in full, or left to the icon; always there for screen readers.
          expect(find.bySemanticsLabel(_names[index]), findsOneWidget);
          if (!signedIn) expect(find.text('Log in'), findsOneWidget, reason: 'the green button keeps its label');
          // Test glyphs are a full em wide, so only the widest bar is sure to
          // have room here; the visual renders check real widths.
          if (width >= 430 && signedIn) expect(find.text(_names[index]), findsOneWidget, reason: 'room for the name');
        }
      });
    }
  }
}
