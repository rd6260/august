import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/chat/message_actions.dart';
import 'package:august/mock/mock_data.dart';

/// The long-press menu offers only what fits the message.
void main() {
  Future<void> actionsFor(WidgetTester t, Message m) async {
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
      showMessageActions(
        t.element(find.byType(Scrollable).first),
        m: m,
        partner: 'Shruti',
      ),
    );
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  }

  testWidgets('a sticker has no Save media', (t) async {
    await actionsFor(
      t,
      MockData.messages().firstWhere((m) => m.body is StickerBody),
    );
    expect(find.text('Save media'), findsNothing);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
    await close(t);
  });

  testWidgets('a photo can be saved; text can be copied', (t) async {
    await actionsFor(
      t,
      MockData.messages().firstWhere((m) => m.body is PhotoBody),
    );
    expect(find.text('Save media'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    await close(t);
    await actionsFor(
      t,
      MockData.messages().firstWhere((m) => m.body is TextBody),
    );
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Save media'), findsNothing);
    await close(t);
  });
}
