import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/stickers/tray.dart';
import 'package:august/mock/mock_data.dart';

/// Searching GIFs or memes: the "Send this?" bar sits above the keyboard.
void main() {
  testWidgets('the meme send bar rides above the keyboard', (t) async {
    final semantics = t.ensureSemantics();
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
    Future<void> frames([int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    unawaited(
      showTray(t.element(find.byType(Scrollable).first), start: TrayTab.gifs),
    );
    await frames(30);
    // Pick a GIF, then the keyboard comes up to search.
    final gif = MockData.memes().firstWhere((m) => m.kind == MemeKind.gif);
    await t.tap(find.bySemanticsLabel(RegExp(gif.title)).first);
    await frames();
    final screen = t.view.physicalSize.height / t.view.devicePixelRatio;
    const keyboard = 300.0;
    t.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(t.view.resetViewInsets);
    await frames();
    final send = find.bySemanticsLabel('Send');
    expect(send, findsOneWidget);
    expect(t.getRect(send).bottom, lessThan(screen - keyboard));
    expect(t.takeException(), isNull);
    semantics.dispose();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
