import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/common/reaction_bar.dart';
import 'package:august/features/common/sticker_view.dart';
import 'package:august/features/stickers/sticker_menu.dart';

/// The sticker long-press menu: keep, favourite, and the chat's actions
/// (react, reply, delete).
void main() {
  Future<ProviderContainer> open(WidgetTester t) async {
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
    return c;
  }

  Future<void> frames(WidgetTester t) async {
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  }

  testWidgets('Add to favourites keeps a new sticker, as a favourite', (
    t,
  ) async {
    final c = await open(t);
    const s = Sticker.photo(id: 'cut-wa-new.webp', art: 3);
    unawaited(
      showStickerMenu(
        t.element(find.byType(Scrollable).first),
        s,
        from: 'From WhatsApp',
      ),
    );
    await frames(t);
    expect(find.text('Not in your favourites'), findsOneWidget);
    expect(find.text('Keep in your stickers'), findsNothing);
    await t.tap(find.text('Add to favourites'));
    await frames(t);
    final kept = [for (final p in c.read(stickersProvider)) ...p.stickers]
        .where((x) => x.id == s.id);
    expect(kept.single.favourite, isTrue);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('unfavouriting lets go of one from elsewhere, not your own', (
    t,
  ) async {
    final c = await open(t);
    final n = c.read(stickersProvider.notifier);
    final packs = c.read(stickersProvider);
    // One from elsewhere, kept only as a favourite (in "Saved", or the
    // first pack on the mock, which has no "Saved").
    const away = Sticker.photo(id: 'cut-wa-away.webp', art: 2);
    final hiddenPack = packs.any((p) => p.id == 'saved') ? 'saved' : null;
    if (hiddenPack != null) n.add(hiddenPack, away.withFavourite(true));
    // One you made, starred.
    final mine = packs.firstWhere((p) => p.id == 'ours').stickers.first;
    if (!mine.favourite) n.toggleFavourite(mine.id);

    Future<void> unfavourite(Sticker s) async {
      unawaited(
        showStickerMenu(
          t.element(find.byType(Scrollable).first),
          s,
          from: 'Yours',
        ),
      );
      await frames(t);
      await t.tap(find.text('Remove from favourites'));
      await frames(t);
    }

    await unfavourite(mine);
    final still = [for (final p in c.read(stickersProvider)) ...p.stickers]
        .where((x) => x.id == mine.id);
    expect(still.single.favourite, isFalse, reason: 'kept, not starred');

    if (hiddenPack != null) {
      await unfavourite(away);
      expect(
        [for (final p in c.read(stickersProvider)) ...p.stickers]
            .any((x) => x.id == away.id),
        isFalse,
      );
    }
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('long-pressing a sticker in the chat opens it, with Reply', (
    t,
  ) async {
    final c = await open(t);
    final m = c.read(messagesProvider).lastWhere((m) => m.body is StickerBody);
    await t.dragUntilVisible(
      find.byKey(ValueKey(m.id)),
      find.byType(Scrollable).first,
      const Offset(0, 300),
    );
    await t.longPress(
      find
          .descendant(
            of: find.byKey(ValueKey(m.id)),
            matching: find.byType(StickerView),
          )
          .first,
    );
    await frames(t);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.textContaining(RegExp('(to|from) favourites')), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('react to a sticker in the chat', (t) async {
    final c = await open(t);
    final m = c.read(messagesProvider).lastWhere((m) => m.body is StickerBody);
    await t.dragUntilVisible(
      find.byKey(ValueKey(m.id)),
      find.byType(Scrollable).first,
      const Offset(0, 300),
    );
    await t.longPress(
      find
          .descendant(
            of: find.byKey(ValueKey(m.id)),
            matching: find.byType(StickerView),
          )
          .first,
    );
    await frames(t);
    await t.tap(
      find.descendant(of: find.byType(ReactionBar), matching: find.text('🔥')),
    );
    await frames(t);
    // The menu closes, and the reaction is on the sticker, under it.
    expect(find.text('Delete for me'), findsNothing);
    final now = c.read(messagesProvider).firstWhere((x) => x.id == m.id);
    expect(now.reactions.where((r) => r.mine).map((r) => r.emoji), ['🔥']);
    expect(
      find.descendant(
        of: find.byKey(ValueKey(m.id)),
        matching: find.text('🔥'),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await close(t);
  });
}
