import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/app/router.dart';
import 'package:august/data/providers.dart';
import 'package:august/mock/mock_repositories.dart';

class _Counting extends MockStorageRepository {
  var cleared = 0;

  @override
  Future<void> clearCache() async => cleared++;
}

/// Settings › Clear cache asks first.
void main() {
  testWidgets('Clear cache asks, and only Clear clears', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final storage = _Counting();
    final c = ProviderContainer(
      overrides: [storageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const AugustApp(initialRoute: Routes.settings),
      ),
    );
    Future<void> frames() async {
      for (var i = 0; i < 14; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    await t.scrollUntilVisible(
      find.text('Clear cache'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Clear cache'));
    await frames();
    expect(find.text('Clear the cache?'), findsOneWidget);
    await t.tap(find.text('Keep'));
    await frames();
    expect(storage.cleared, 0);

    await t.tap(find.text('Clear cache'));
    await frames();
    await t.tap(find.text('Clear'));
    await frames();
    expect(storage.cleared, 1);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
