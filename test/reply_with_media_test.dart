import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/core/icons/v_icons.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/chat/composer.dart';

/// Replying with something other than text: a sticker (a doodle from the
/// attach sheet) and photos from the gallery both answer the message, and
/// the sticker shows the quote over it.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('reply with a sticker, then with photos', (t) async {
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
    await frames(t);

    final target = c
        .read(messagesProvider)
        .lastWhere((m) => !m.fromMe && m.body is TextBody);
    final said = (target.body as TextBody).text;
    Future<void> replyToTarget() async {
      await t.dragUntilVisible(
        find.byKey(ValueKey(target.id)),
        find.byType(Scrollable).first,
        const Offset(0, 300),
      );
      await t.longPress(
        find
            .descendant(
              of: find.byKey(ValueKey(target.id)),
              matching: find.text(said),
            )
            .first,
      );
      await frames(t);
      await t.tap(find.text('Reply').last);
      await frames(t);
      expect(t.widget<Composer>(find.byType(Composer)).replyTo?.id, target.id);
    }

    Future<void> attach(String tile) async {
      await t.tap(
        find
            .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.plus)
            .first,
      );
      await frames(t);
      await t.tap(find.text(tile));
      await frames(t);
    }

    // A doodle, as a sticker.
    await replyToTarget();
    await attach('Doodle');
    await t.tap(find.text(c.read(doodlesProvider).first.name).last);
    await frames(t);
    final sticker = c.read(messagesProvider).last;
    expect(sticker.body, isA<StickerBody>());
    expect(sticker.reply?.text, said);
    expect(t.widget<Composer>(find.byType(Composer)).replyTo, isNull);
    // The quote shows over the sticker.
    expect(
      find.descendant(
        of: find.byKey(ValueKey(sticker.id)),
        matching: find.text(said),
      ),
      findsOneWidget,
    );

    // Photos from the gallery.
    await replyToTarget();
    await attach('Gallery');
    await t.tap(find.bySemanticsLabel('Photo').at(0));
    await frames(t, 200);
    await t.tap(find.text('Send 1'));
    await frames(t);
    await t.tap(find.bySemanticsLabel('Send to Shruti'));
    await frames(t);
    final photo = c.read(messagesProvider).last;
    expect(photo.body, isA<PhotoBody>());
    expect(photo.reply?.text, said);
    expect(t.takeException(), isNull);

    semantics.dispose();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
