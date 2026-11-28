import 'dart:async';
import 'dart:io';

import 'data_home.dart';

/// Whether August is on screen, as every isolate can tell: the app keeps a
/// small file fresh while it's in the foreground, and the push handler and
/// the background check (their own engines, which can't see the app's
/// state) read it before notifying, so nothing pops up over the open chat.
abstract final class OnScreen {
  static const _name = 'on-screen';

  /// How often the app refreshes it while shown, and how old it may be and
  /// still count (August killed while open leaves it behind).
  static const beat = Duration(seconds: 10);
  static const fresh = Duration(seconds: 25);

  static Timer? _timer;

  static Future<File> _file() async =>
      File('${(await DataHome.dir()).path}/$_name');

  /// The app came to the front: mark it, and keep marking it.
  static void shown() {
    _timer?.cancel();
    unawaited(_touch());
    _timer = Timer.periodic(beat, (_) => unawaited(_touch()));
  }

  /// The app went to the back: unmark it.
  static Future<void> hidden() async {
    _timer?.cancel();
    _timer = null;
    try {
      final f = await _file();
      if (f.existsSync()) await f.delete();
    } on Object {
      // Gone already.
    }
  }

  static Future<void> _touch() async {
    try {
      await (await _file()).writeAsString(
        DateTime.now().toIso8601String(),
        flush: true,
      );
    } on Object {
      // Notifications may show meanwhile; nothing worse.
    }
  }

  /// From any isolate: is August on screen right now?
  static Future<bool> now() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return false;
      final at = DateTime.tryParse(await f.readAsString());
      return at != null && DateTime.now().difference(at) < fresh;
    } on Object {
      return false;
    }
  }
}
