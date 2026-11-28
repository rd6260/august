import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/app/router.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/common/overlay.dart';
import 'package:august/features/doodles/board_page.dart';

/// The board is a card clear of the top bar and the dock: a stroke can't
/// start next to the buttons.
void main() {
  testWidgets('only the card takes strokes', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const AugustApp(initialRoute: Routes.doodles),
      ),
    );
    Future<void> frames([int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    final id = c.read(doodlesProvider).first.id;
    unawaited(
      pushPage<void>(
        t.element(find.byType(Scrollable).first),
        (_) => BoardPage(id: id),
      ),
    );
    await frames(30);
    int strokes() =>
        c.read(doodlesProvider).firstWhere((d) => d.id == id).strokes.length;
    Future<void> drag(Offset from) async {
      await t.dragFrom(from, const Offset(60, 0));
      await frames(6);
    }

    final before = strokes();
    // Beside the top bar's title, and just above the dock: nothing.
    await drag(const Offset(200, 50));
    await drag(const Offset(100, 750));
    expect(strokes(), before);
    // In the card: a stroke.
    await drag(const Offset(100, 400));
    expect(strokes(), before + 1);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
