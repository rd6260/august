import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/chat/chat_hooks.dart';
import '../features/common/overlay.dart';
import '../features/media/media_pages.dart';
import 'router.dart';

/// Photos and videos shared to August from another app (Android's share
/// sheet, ShareIntake.kt): once August is paired and unlocked, it opens the
/// chat with the usual preview (caption, HD), and Send sends them as the
/// gallery's would.
class ShareIntake {
  ShareIntake(this.ref, this.router);

  final WidgetRef ref;
  final GoRouter router;
  static const _channel = MethodChannel('august/share');

  /// Shared and not shown yet (waiting for the lock, say).
  List<Media>? _waiting;
  ProviderSubscription<Object?>? _session;

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await _take();
    });
    _session = ref.listenManual(sessionProvider, (_, _) => _show());
    await _take();
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _session?.close();
  }

  Future<void> _take() async {
    final List<Map<Object?, Object?>>? raw;
    try {
      raw = await _channel.invokeListMethod<Map<Object?, Object?>>('take');
    } on Object {
      return; // Not on Android.
    }
    if (raw == null || raw.isEmpty) return;
    final keep = ref.read(sharedMediaProvider);
    if (keep == null) return;
    final media = await keep([
      for (final r in raw)
        (path: r['path']! as String, mime: r['mime']! as String),
    ]);
    if (media.isEmpty) return;
    _waiting = [...?_waiting, ...media];
    _show();
  }

  /// Shows the preview once August can: paired, and not behind the lock.
  void _show() {
    final media = _waiting;
    if (media == null) return;
    final session = ref.read(sessionProvider);
    final locked = session.locked && session.pin.isNotEmpty;
    if (!session.paired || locked) return;
    _waiting = null;
    router.go(Routes.chat);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final picked = await pushPage<PickedMedia>(
        context,
        (_) => MediaPreview(
          media: media,
          partner: ref.read(pairingProvider).partner.name,
        ),
      );
      if (picked == null) return;
      await sendPicked(
        ref.read(messagesProvider.notifier),
        picked,
        ref.read(mediaSourceProvider),
      );
    });
  }
}
