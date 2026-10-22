import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/core/widgets/listing_image.dart';
import 'package:akarat/core/widgets/skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _url = 'https://example.invalid/photo.jpg';

/// A photo still on its way.
class _Arriving extends ImageStreamCompleter {}

/// Puts [completer] in the memory cache as this photo decoded [width] wide,
/// keyed as CachedNetworkImage keys it.
Future<void> _cache(int width, ImageStreamCompleter completer) async {
  final key = await ResizeImage(
    const CachedNetworkImageProvider(_url),
    width: width,
  ).obtainKey(ImageConfiguration.empty);
  PaintingBinding.instance.imageCache.putIfAbsent(key, () => completer);
}

/// The photo drawn 360 wide at 3x: decoded 1080 wide.
Future<void> _show(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness: Brightness.dark, lang: 'en'),
      home: const Center(
        child: SizedBox(width: 360, height: 240, child: ListingImage(url: _url, decodeWidth: 360)),
      ),
    ),
  );
  await tester.pump();
}

Finder _imageAt(int width) =>
    find.byWidgetPredicate((w) => w is Image && w.image is ResizeImage && (w.image as ResizeImage).width == width);

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  group('While a listing photo loads', () {
    testWidgets('a smaller copy already decoded (a card\'s) stands in for it', (tester) async {
      final small = await tester.runAsync(() => createTestImage(width: 256, height: 170));
      await _cache(256, OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: small!))));
      await _cache(1080, _Arriving());
      await _show(tester);
      expect(_imageAt(256), findsOneWidget, reason: 'the decoded copy, not the one still arriving');
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('with no copy decoded yet, the skeleton shows rather than nothing', (tester) async {
      await _cache(1080, _Arriving());
      await _show(tester);
      expect(find.byType(Skeleton), findsOneWidget);
    });
  });
}
