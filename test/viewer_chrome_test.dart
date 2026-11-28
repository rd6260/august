import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/common/overlay.dart';
import 'package:august/features/media/media_viewer.dart';

/// The media viewer: full screen, a tap hides the header and actions and
/// another brings them back.
void main() {
  testWidgets('a tap hides and shows the controls', (t) async {
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
        (_) => MediaViewer(
          items: viewerItems(c.read(messagesProvider), partner: 'Shruti'),
          start: 1,
        ),
      ),
    );
    Future<void> frames() async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    // Every fade around the Save action, multiplied.
    double shown() => t
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.text('Save'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .fold(1.0, (v, o) => v * o.opacity);
    expect(shown(), 1);
    await t.tap(find.byType(InteractiveViewer).at(0), warnIfMissed: true);
    await frames();
    expect(shown(), 0);
    await t.tap(find.byType(InteractiveViewer).at(0), warnIfMissed: true);
    await frames();
    expect(shown(), 1);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
