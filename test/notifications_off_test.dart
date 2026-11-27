import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/app/router.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/common/overlay.dart';
import 'package:august/features/settings/settings_pages.dart';

/// Settings › Notifications says so when Android won't let August notify
/// (a reinstall drops the permission), and Turn on asks again.
void main() {
  for (final allowed in [false, true]) {
    testWidgets('allowed: $allowed', (t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      var asked = 0;
      final c = ProviderContainer(
        overrides: [
          notificationsAllowedProvider.overrideWith((ref) async => allowed),
          askNotificationsProvider.overrideWithValue(() async {
            asked++;
            return true;
          }),
        ],
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
      await t.pump(const Duration(milliseconds: 600));
      unawaited(
        pushPage<void>(
          t.element(find.byType(Scrollable).first),
          (_) => const NotificationsPage(),
        ),
      );
      for (var i = 0; i < 14; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.text('Notifications are off'),
        allowed ? findsNothing : findsOneWidget,
      );
      if (!allowed) {
        await t.tap(find.text('Turn on'));
        await t.pump(const Duration(milliseconds: 100));
        expect(asked, 1);
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    });
  }
}
