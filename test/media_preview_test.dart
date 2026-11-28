import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/data/models.dart';
import 'package:august/features/common/art.dart';
import 'package:august/features/media/media_pages.dart';
import 'package:august/mock/mock_data.dart';

/// Before sending: the caption sits above the keyboard, and each photo
/// shows in its own shape.
void main() {
  testWidgets('the caption rises above the keyboard', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    Future<double> captionBottom({required double keyboard}) async {
      await t.pumpWidget(
        CupertinoApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: MediaPreview(media: MockData.gallery().take(2).toList()),
          ),
        ),
      );
      await t.pump();
      return t.getBottomLeft(find.byType(CupertinoTextField)).dy;
    }

    final closed = await captionBottom(keyboard: 0);
    final open = await captionBottom(keyboard: 300);
    expect(open, lessThanOrEqualTo(844 - 300));
    expect(closed, greaterThan(844 - 300));
  });

  testWidgets('a photo keeps its shape', (t) async {
    for (final aspect in [0.75, 1.0, 16 / 9]) {
      await t.pumpWidget(
        CupertinoApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: MediaPreview(
              key: ValueKey(aspect),
              media: [Media(id: 'p', art: 2, aspect: aspect)],
            ),
          ),
        ),
      );
      await t.pump();
      final box = t.getSize(find.byType(ArtBox).first);
      expect(box.width / box.height, moreOrLessEquals(aspect, epsilon: 0.01));
    }
  });
}
