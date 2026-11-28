import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/data/chat_theme.dart';
import 'package:august/features/common/wallpaper.dart';

/// Dragging Blur (or Dim) back and forth: a setting comes back while its
/// earlier copy is still fading out. That used to crash ("Duplicate keys").
void main() {
  testWidgets('a setting can come back mid-fade', (t) async {
    Widget at(double blur) => Directionality(
      textDirection: TextDirection.ltr,
      child: WallpaperView(
        wallpaper: const WallpaperRef.photo('mock:3'),
        blur: blur,
      ),
    );
    for (final b in [0.4, 0.5, 0.4, 0.5, 0.4]) {
      await t.pumpWidget(at(b));
      await t.pump(const Duration(milliseconds: 40));
    }
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('dim and blur redraw in place, without a fade', (t) async {
    Widget at(double blur, double dim) => Directionality(
      textDirection: TextDirection.ltr,
      child: WallpaperView(
        wallpaper: const WallpaperRef.photo('mock:3'),
        blur: blur,
        dim: dim,
      ),
    );
    await t.pumpWidget(at(0, 0));
    await t.pump(const Duration(seconds: 1));
    for (var i = 1; i <= 20; i++) {
      await t.pumpWidget(at(i / 40, i / 40));
      await t.pump(const Duration(milliseconds: 16));
      // One picture the whole drag: no copies fading over each other.
      expect(find.byType(ImageFiltered), findsOneWidget);
    }
    await t.pump(const Duration(seconds: 1));
  });
}
