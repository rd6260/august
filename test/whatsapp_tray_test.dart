import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/app/app.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/features/stickers/tray.dart';
import 'package:august/platform/whatsapp_stickers.dart';

/// The tray's WhatsApp tab: pick the folder once, then its stickers show.
void main() {
  testWidgets('choosing the folder shows what is in it, without errors', (
    t,
  ) async {
    WhatsAppStickers.debugSupported = true;
    addTearDown(() => WhatsAppStickers.debugSupported = null);
    var picked = false;
    final dir = Directory.systemTemp.createTempSync('wa');
    addTearDown(() => dir.deleteSync(recursive: true));
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('august/whatsapp'),
      (call) async => switch (call.method) {
        'hasFolder' => picked,
        'pickFolder' => picked = true,
        'list' => <Map<String, Object>>[],
        _ => null,
      },
    );
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
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
    Future<void> frames([int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    unawaited(showTray(t.element(find.byType(Scrollable).first)));
    await frames(30);
    await t.tap(find.text('WhatsApp'));
    await frames();
    expect(find.text('Choose folder'), findsOneWidget);
    await t.tap(find.text('Choose folder'));
    await frames();
    expect(t.takeException(), isNull);
    expect(find.text('No WhatsApp stickers yet'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('a sticker sent from WhatsApp comes first in Recent', (t) async {
    WhatsAppStickers.debugSupported = true;
    addTearDown(() => WhatsAppStickers.debugSupported = null);
    final dir = Directory.systemTemp.createTempSync('wa');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/cat.webp')..writeAsBytesSync([0, 1, 2]);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('august/whatsapp'),
      (call) async => switch (call.method) {
        'hasFolder' => true,
        'list' => [
          {'path': file.path, 'modified': 1},
        ],
        _ => null,
      },
    );
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
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
    Future<void> frames([int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    Body? sent;
    unawaited(
      showTray(t.element(find.byType(Scrollable).first)).then((b) => sent = b),
    );
    await frames(30);
    await t.tap(find.text('WhatsApp'));
    await frames();
    await t.runAsync(() async {
      await t.tap(find.bySemanticsLabel('WhatsApp sticker'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await frames();
    expect(sent, isA<StickerBody>());
    final recent = c.read(recentStickersProvider);
    expect(recent.first.id, 'cut-wa-cat.webp');
    expect(File(recent.first.path!).existsSync(), isTrue);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
