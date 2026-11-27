import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/app/router.dart';
import 'package:august/data/providers.dart';

/// A doodle's long-press menu: Send to chat first, the home screen just
/// before Delete.
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
      'Send to chat',
      'Rename',
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
}
