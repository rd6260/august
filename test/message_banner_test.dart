import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/app/router.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/chat/chat_page.dart';

/// A message while you're not looking at the chat slides a banner down;
/// on the chat itself, none.
void main() {
  Future<ProviderContainer> open(WidgetTester t, String route) async {
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
        child: AugustApp(initialRoute: route),
      ),
    );
    await t.pump(const Duration(milliseconds: 600));
    return c;
  }

  Future<void> wait(WidgetTester t, int ms) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 6));
  }

  Finder banner() => find.bySemanticsLabel(RegExp('Open the chat'));

  testWidgets('on Settings, a reply comes as a banner; tap for the chat', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final c = await open(t, Routes.settings);
    // The mock partner answers what you send (in a few seconds).
    c.read(messagesProvider.notifier).send(const TextBody('are you up?'));
    // The reply comes after the partner "types" (about 4 s, later on a slow
    // machine): wait for it, then for the banner to finish sliding in.
    // Tapped while still above the screen, it would miss.
    for (var ms = 0; banner().evaluate().isEmpty && ms < 10000; ms += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(banner(), findsOneWidget);
    await wait(t, 500);
    await t.tap(banner());
    await wait(t, 800);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(banner(), findsNothing);
    semantics.dispose();
    await close(t);
  });

  testWidgets('on the chat, no banner', (t) async {
    final semantics = t.ensureSemantics();
    final c = await open(t, Routes.chat);
    c.read(messagesProvider.notifier).send(const TextBody('are you up?'));
    // Long enough for the reply to have come, even on a slow machine.
    await wait(t, 8000);
    expect(c.read(messagesProvider).last.fromMe, isFalse);
    expect(banner(), findsNothing);
    semantics.dispose();
    await close(t);
  });
}
