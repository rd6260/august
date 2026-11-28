import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../platform/data_home.dart';
import '../platform/doodle_widget.dart';
import 'api.dart';
import 'config.dart';
import 'crypto.dart';
import 'local_store.dart';
import 'neon_backend.dart';
import 'wire.dart';

/// Tapping the widget's caption ("You · 06:45"): redraws it, in the
/// background, from the server's waiting doodle changes when it can and from
/// this phone's boards otherwise. Runs in its own isolate (home_widget's).
///
/// `august://redraw` (from the open app, see [DoodleWidget.redrawInBackground])
/// draws what this phone has, without asking the server: the app has the
/// latest already.
@pragma('vm:entry-point')
Future<void> widgetTapped(Uri? uri) async {
  final host = uri?.host;
  if (host != 'refresh' && host != 'redraw') return;
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await DataHome.dir();
  final store = await LocalStore.open(dir);
  final config = NeonConfig.fromEnvironment;
  if (host == 'refresh' && config != null && store.paired) {
    try {
      final b = await NeonBackend.open(
        config,
        vault: await DataHome.vault(),
        dir: dir,
      );
      await refreshWidgetInBackground(
        api: b.api,
        identity: b.identity,
        store: store,
        dir: dir,
      );
      return;
    } on Object {
      // Offline: what this phone has.
    }
  }
  await DoodleWidget.show(
    doodle: store.doodles.where((d) => d.id == store.widgetDoodle).firstOrNull,
    theme: store.theme,
    dir: dir,
  );
}

/// Redraws the home screen widget while August is closed: the boards on
/// this phone, plus doodle changes still waiting on the server.
///
/// Like the rest of the background work it only peeks: it never applies
/// or acks the mail, so August still takes it when it opens. Called for a
/// "wake" push and by the background check (with the mail it already has).
Future<void> refreshWidgetInBackground({
  required AugustApi api,
  required Identity identity,
  required LocalStore store,
  required Directory dir,
  List<Mail>? mail,
}) async {
  if (!DoodleWidget.supported) return;
  final partner = store.partner;
  if (partner == null) return;
  final waiting = (mail ?? await api.inbox()).where((m) => m.kind == 'doodle');
  var boards = store.doodles;
  var pinned = store.widgetDoodle;
  if (waiting.isNotEmpty) {
    final ch = await identity.channelTo(partner.pubkey);
    for (final m in waiting) {
      try {
        final env = Envelope.fromJson(await ch.openJson(m.body));
        if (env is! DoodleEnvelope) continue;
        if (env.op case DoodlePinned(:final id)) {
          pinned = id;
        } else {
          boards = applyDoodleOp(
            boards,
            env.op,
            partner: partner.name,
            at: m.at.toLocal(),
          );
        }
      } on Object {
        // Not from the partner, or unreadable: skip it.
      }
    }
  }
  await DoodleWidget.show(
    doodle: boards.where((d) => d.id == pinned).firstOrNull,
    theme: store.theme,
    dir: dir,
  );
}
