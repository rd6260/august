import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/chat/theme_sheet.dart';
import 'package:august/features/common/overlay.dart';

/// Dragging Dim, Blur or Glass: the rest of the theme sheet steps aside so
/// the chat shows the change, and comes back on release.
void main() {
  testWidgets('the sheet clears while a slider is dragged', (t) async {
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
      showOverlayPage<bool>(
        t.element(find.byType(Scrollable).first),
        (_) => const ThemeSheet(),
      ),
    );
    Future<void> frames() async {
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    // How visible [text] is: every fade around it, multiplied.
    double shown(String text) => t
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.text(text),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .fold(1.0, (v, o) => v * o.opacity);

    expect(shown('PALETTES'), 1);
    final glass = t.getCenter(find.text('Glass')) + const Offset(0, 22);
    final g = await t.startGesture(glass);
    await g.moveBy(const Offset(40, 0));
    await frames();
    expect(shown('PALETTES'), 0);
    expect(shown('Apply for both'), 0);
    expect(shown('Glass'), 1, reason: 'the one being dragged stays');
    expect(shown('Dim'), 0);
    await g.up();
    await frames();
    expect(shown('PALETTES'), 1);
    expect(shown('Dim'), 1);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
