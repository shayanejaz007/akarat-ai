import 'package:akarat/features/property_details/media_viewer.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

const _photos = [
  MediaItem(url: 'https://example.invalid/1.jpg'),
  MediaItem(url: 'https://example.invalid/2.jpg'),
  MediaItem(url: 'https://example.invalid/3.jpg'),
];

/// Photos load from the network, so their placeholders shimmer: step time
/// forward instead of waiting for stillness.
Future<void> _step(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the photo fills the top, the tiles sit in a sheet at the bottom, a tile jumps to its photo', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const MediaViewer(media: _photos, title: 'Garden villa'),
      overrides: await TestDeps().overrides(),
    );
    await _step(tester);

    expect(tester.getTopLeft(find.text('Garden villa')).dy, lessThan(120), reason: 'the title is at the top');
    expect(tester.getTopLeft(find.text('Photos')).dy, greaterThan(844 * 0.7), reason: 'the sheet is at the bottom');
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('3 of 3'));
    await _step(tester);
    expect(find.text('3 of 3'), findsOneWidget, reason: 'the sheet follows the photo on screen');
  });
}
