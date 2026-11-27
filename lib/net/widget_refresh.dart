import 'dart:io';

import '../data/models.dart';
import '../platform/doodle_widget.dart';
import 'api.dart';
import 'crypto.dart';
import 'local_store.dart';
import 'wire.dart';

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
