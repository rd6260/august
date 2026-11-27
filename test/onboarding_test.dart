import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/core/widgets/v_page.dart';
import 'package:august/app/app.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/chat/chat_page.dart';
import 'package:august/features/lock/lock_pages.dart';
import 'package:august/features/onboarding/onboarding_pages.dart';
import 'package:august/mock/mock_data.dart';

/// Onboarding and the lock end to end on the mock.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> open(
    WidgetTester t, {
    bool paired = false,
    bool locked = false,
  }) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(paired: paired, locked: locked));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const AugustApp()),
    );
    await frames(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 6));
  }

  testWidgets('a new phone: welcome, name, background, pair, chat', (t) async {
    final c = await open(t);
    expect(find.byType(WelcomePage), findsOneWidget);
    await t.tap(find.text('Start'));
    await frames(t);
    await t.enterText(find.byType(EditableText), 'Rohan');
    await frames(t, 100);
    await t.tap(find.text('Continue'));
    await frames(t);
    expect(find.text('Staying in touch'), findsOneWidget);
    await t.tap(find.text('Allow'));
    await frames(t, 200);
    expect(find.text('2 of 2 allowed'), findsOneWidget);
    await t.tap(find.text('Continue'));
    await frames(t);
    expect(find.text(MockData.inviteCode), findsOneWidget);
    // Shruti joins.
    await frames(t, 4500);
    expect(find.byType(PairedPage), findsOneWidget);
    expect(find.text('Rohan & Shruti'), findsOneWidget);
    await t.tap(find.text('Start chatting'));
    await frames(t);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(c.read(sessionProvider).paired, isTrue);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('a wrong code says so; the right one pairs', (t) async {
    await open(t);
    await t.tap(find.text('I have a code'));
    await frames(t);
    await t.tap(find.text('Continue'));
    await frames(t);
    await t.tap(find.text('Allow'));
    await frames(t, 200);
    await t.tap(find.text('Continue'));
    await frames(t);
    await t.enterText(find.byType(EditableText), 'ABC123');
    await frames(t, 100);
    await t.tap(find.text('Join'));
    await frames(t, 200);
    expect(
      find.text('That code has expired. Ask for a new one.'),
      findsOneWidget,
    );
    await t.enterText(find.byType(EditableText), MockData.inviteCode);
    await frames(t, 100);
    await t.tap(find.text('Join'));
    await frames(t);
    expect(find.byType(PairedPage), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('Join rides above the keyboard while typing the code', (t) async {
    await open(t);
    await t.tap(find.text('I have a code'));
    await frames(t);
    await t.tap(find.text('Continue'));
    await frames(t);
    await t.tap(find.text('Allow'));
    await frames(t, 200);
    await t.tap(find.text('Continue'));
    await frames(t);
    final ratio = t.view.devicePixelRatio;
    final screen = t.view.physicalSize.height / ratio;
    const keyboard = 300.0;
    t.view.viewInsets = FakeViewPadding(bottom: keyboard * ratio);
    addTearDown(t.view.resetViewInsets);
    await frames(t, 100);
    final join = t.getRect(find.text('Join'));
    expect(join.bottom, lessThan(screen - keyboard));
    t.view.resetViewInsets();
    await frames(t, 100);
    expect(t.getRect(find.text('Join')).bottom, greaterThan(screen - keyboard));
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('re-pair from Settings covers what opened it', (t) async {
    await open(t, paired: true);
    final context = t.element(find.byType(Navigator).last);
    unawaited(
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => const JoinPage(repair: true),
        ),
      ),
    );
    await frames(t);
    expect(
      find.descendant(of: find.byType(JoinPage), matching: find.byType(VVeil)),
      findsOneWidget,
    );
    expect(find.text('THEIR NEW PHONE'), findsOneWidget);
    expect(find.text('STEP 3 OF 3'), findsNothing);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('the decoy PIN opens the decoy chat', (t) async {
    await open(t, paired: true, locked: true);
    expect(find.byType(LockScreen), findsOneWidget);
    for (final d in MockData.decoyPin.split('')) {
      await t.tap(find.bySemanticsLabel(d));
      await t.pump(const Duration(milliseconds: 50));
    }
    await frames(t);
    expect(find.text('Say hi to ${MockData.decoyName}'), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t);
  });
}
