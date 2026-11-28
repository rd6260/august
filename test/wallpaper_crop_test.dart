import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/chat/theme_sheet.dart';
import 'package:august/features/common/overlay.dart';

/// Fitting a photo as the wallpaper: it can't be dragged off the screen.
void main() {
  testWidgets('a drag never leaves an edge uncovered', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const AugustApp()),
    );
    await t.pump(const Duration(milliseconds: 600));
    unawaited(
      pushPage<void>(
        t.element(find.byType(Scrollable).first),
        (_) => const WallpaperCrop(photo: 'mock:3'),
      ),
    );
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    // The photo's move: the first Transform in the crop page.
    Offset moved() {
      final tr = t.widget<Transform>(
        find
            .descendant(
              of: find.byType(WallpaperCrop),
              matching: find.byType(Transform),
            )
            .first,
      );
      final v = tr.transform.getTranslation();
      return Offset(v.x, v.y);
    }

    // At 1× the photo just covers the screen: it can't move at all.
    await t.dragFrom(const Offset(200, 400), const Offset(250, 300));
    await t.pump(const Duration(milliseconds: 100));
    expect(moved(), Offset.zero);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
