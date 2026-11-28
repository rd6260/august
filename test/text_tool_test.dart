import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/app/router.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/common/overlay.dart';
import 'package:august/features/common/strokes.dart';
import 'package:august/features/doodles/board_page.dart';
import 'package:august/net/wire.dart';

/// The doodle text tool: words on the board, synced like any stroke.
void main() {
  const words = Stroke(
    tool: PenTool.text,
    argb: 0xFFFFC15E,
    size: 30,
    points: [Offset(60, 40)],
    text: 'Picnic at 4?',
  );

  test('the words travel and come back, moved or recoloured', () {
    final back = Wire.toStroke(Wire.stroke(words), flip: true);
    expect(back.text, 'Picnic at 4?');
    expect(back.tool, PenTool.text);
    expect(back.size, 30);
    expect(back.copyWith(argb: 0xFF000000).text, 'Picnic at 4?');
  });

  test('text covers the box its words fill', () {
    final b = strokeBounds(words)!;
    expect(b.topLeft, const Offset(60, 40));
    expect(b.width, greaterThan(100));
    expect(b.height, greaterThan(25));
  });

  testWidgets('pick Text, tap the board, type, Add', (t) async {
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
    Future<void> frames([int n = 16]) async {
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
    await frames(24);
    final semantics = t.ensureSemantics();
    await t.tap(find.bySemanticsLabel('Text'));
    await frames();
    await t.tapAt(const Offset(120, 300));
    await frames();
    expect(find.text('ADD TEXT'), findsOneWidget);
    await t.enterText(find.byType(EditableText).last, 'see you there');
    await t.tap(find.text('Add'));
    await frames();
    final last = c
        .read(doodlesProvider)
        .firstWhere((d) => d.id == id)
        .strokes
        .last;
    expect(last.tool, PenTool.text);
    expect(last.text, 'see you there');
    expect(t.takeException(), isNull);
    semantics.dispose();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
