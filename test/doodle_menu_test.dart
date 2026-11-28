import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/app/router.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/mock/mock_repositories.dart';

/// A doodle's long-press menu: Send as sticker first, the home screen just
/// before Delete; Copy makes a copy for both of you.
void main() {
  testWidgets('the doodle menu is in order', (t) async {
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
    Future<void> frames() async {
      for (var i = 0; i < 16; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    final d = c.read(doodlesProvider).first;
    await t.longPress(find.text(d.name).first);
    await frames();
    double y(String label) => t.getRect(find.text(label).last).top;
    final order = [
      'Send as sticker',
      'Rename',
      'Copy',
      'Show on home screen',
      'Delete for both',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i - 1]), lessThan(y(order[i])), reason: order[i]);
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('Copy copies the board, for both', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final sent = <DoodleOp>[];
    final c = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(_Recording(sent))],
    );
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
    Future<void> frames() async {
      for (var i = 0; i < 16; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    final d = c.read(doodlesProvider).firstWhere((d) => d.strokes.isNotEmpty);
    final before = c.read(doodlesProvider).length;
    await t.longPress(find.text(d.name).first);
    await frames();
    await t.tap(find.text('Copy').last);
    await frames();
    final all = c.read(doodlesProvider);
    expect(all.length, before + 1);
    final copy = all.first;
    expect(copy.name, '${d.name} copy');
    expect(copy.id, isNot(d.id));
    expect(copy.paper, d.paper);
    expect(copy.strokes, d.strokes);
    // The partner gets the new board, then its drawing.
    expect(sent.whereType<DoodleCreated>().single.doodle.id, copy.id);
    expect(sent.whereType<StrokesSet>().single.strokes, d.strokes);
    expect(find.text('Copied'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}

class _Recording extends MockChatRepository {
  _Recording(this.sent);
  final List<DoodleOp> sent;

  @override
  void shareDoodle(DoodleOp op) => sent.add(op);
}
