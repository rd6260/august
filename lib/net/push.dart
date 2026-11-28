import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message, Person;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as notify
    show Message, Person;

import '../core/theme/v_colors.dart';
import '../data/models.dart';
import '../features/moments/moment_burst.dart' show MomentCopy;
import 'config.dart';
import 'crypto.dart';
import 'local_store.dart';
import 'neon_backend.dart';
import 'vault.dart';
import 'widget_refresh.dart';
import '../platform/data_home.dart';
import '../platform/on_screen.dart';
import 'wire.dart';

/// What a notification says: who, what, whether it's a moment (the loud
/// channel), and its colour ([tint], ARGB; a moment's own).
typedef Notice = ({String title, String body, bool moment, int? tint});

/// Firebase Cloud Messaging: the API sends a data-only wake-up when mail
/// lands, and this turns it into a notification. The sealed envelope rides
/// along, so the notification can say what kind of thing arrived; the mail
/// stays on the server until August opens and takes it.
abstract final class Push {
  static final _local = FlutterLocalNotificationsPlugin();

  static const messages = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'New messages from your person',
    importance: Importance.high,
  );

  static const moments = AndroidNotificationChannel(
    'moments',
    'Pokes and hugs',
    description: 'Pokes, hugs, kisses and miss-yous, as they come',
    importance: Importance.max,
  );

  /// Sets up Firebase and the notification channels. [onWake] runs when a
  /// push arrives while August is open.
  static Future<void> init({required VoidCallback onWake}) async {
    // Local notifications first: they work even where Firebase can't
    // (the Linux desktop build).
    await ready();
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_background);
    FirebaseMessaging.onMessage.listen((_) => onWake());
  }

  /// Asks for the notification permission (Android 13+).
  static Future<bool> ask() async {
    try {
      final s = await FirebaseMessaging.instance.requestPermission();
      return s.authorizationStatus == AuthorizationStatus.authorized;
    } on Object {
      // No Firebase (the Linux desktop build): local notifications need
      // no permission there.
      return true;
    }
  }

  /// Whether Android lets August show notifications. Runtime permissions
  /// go with an uninstall, so a reinstall (the dev flavor's, which skips
  /// onboarding) starts without it.
  static Future<bool> allowed() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.authorized;
    } on Object {
      return true; // No Firebase: nothing to allow.
    }
  }

  static const _window = MethodChannel('august/window');

  /// Opens August's notification settings (when Android won't ask again).
  static Future<void> openSettings() async {
    try {
      await _window.invokeMethod<void>('notificationSettings');
    } on Object {
      // Not on Android.
    }
  }

  static Future<String?> token() async {
    try {
      // The registration token still works with HTTP v1 `message.token`;
      // FID direct-send (register/onRegistered) is the newer path.
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } on Object {
      return null; // No Play services, or offline: the poll still works.
    }
  }

  static Stream<String> get tokenChanges =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;

  /// Sets up local notifications and their channels (any isolate).
  static Future<void> ready() async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open August'),
      ),
    );
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(messages);
    await android?.createNotificationChannel(moments);
    // The background check's old, louder channel (it's "checking" now).
    await android?.deleteNotificationChannel(channelId: 'background');
  }

  /// What the notification says for a push; null shows nothing.
  static Future<Notice?> describe(
    Map<String, dynamic> data, {
    required Vault vault,
    required LocalStore store,
  }) async {
    final partner = store.partner;
    if (partner == null) return null;
    final name = partner.name.isEmpty ? 'Your person' : partner.name;
    final kind = data['kind'] as String?;
    final sealed = data['body'] as String?;
    Envelope? env;
    if (sealed != null) {
      try {
        final ch = await (await Identity.load(vault)).channelTo(partner.pubkey);
        env = Envelope.fromJson(await ch.openJson(sealed));
      } on Object {
        env = null; // Not from the partner: say nothing about it.
        return null;
      }
    }
    // Receipts, typing, doodle changes, the theme and the like are mail
    // too, but nothing a person needs a notification for.
    if (env != null && env is! MessageEnvelope) return null;
    if (env case MessageEnvelope(:final message)) {
      return switch (message.body) {
        MomentBody(:final moment) => (
          title: name,
          body: '${moment.emoji} ${moment.row(fromMe: false, partner: name)}',
          moment: true,
          tint: moment.color.toARGB32(),
        ),
        CallBody(:final video) => (
          title: name,
          body: video ? 'Video call' : 'Voice call',
          moment: true,
          tint: null,
        ),
        // The text only with "Show message text" on (Settings ›
        // Notifications); otherwise just that something came.
        TextBody(:final text) when store.settings.showPreview => (
          title: name,
          body: text,
          moment: false,
          tint: null,
        ),
        _ => (title: name, body: 'New message', moment: false, tint: null),
      };
    }
    return switch (kind) {
      'moment' => (
        title: name,
        body: 'Sent you something 💗',
        moment: true,
        tint: VMoment.hug.color.toARGB32(),
      ),
      'call' => (title: name, body: 'Calling you', moment: true, tint: null),
      'msg' => (title: name, body: 'New message', moment: false, tint: null),
      _ => null,
    };
  }

  /// Shows [n] in the conversation style: the partner's picture and name
  /// over their message. Messages that arrive while August is closed stack
  /// in one notification (the last few, each once, by its mail [key]);
  /// opening August clears them ([clear]). Moments go on their own loud
  /// channel, in their colour.
  static Future<void> show(
    Notice n, {
    required int id,
    String? key,
    LocalStore? store,
  }) async {
    // August is open: the message is on screen already.
    if (await OnScreen.now()) return;
    final dir = await DataHome.dir();
    final avatar = await _avatar(n.title, store?.partnerPhoto, dir);
    final them = notify.Person(
      key: 'partner',
      name: n.title,
      important: true,
      icon: avatar == null ? null : BitmapFilePathAndroidIcon(avatar),
    );
    final StyleInformation style;
    if (n.moment) {
      style = BigTextStyleInformation(n.body);
    } else {
      final pending = await _remember(dir, key: key, text: n.body);
      // Already shown (a push and the background check both found it).
      if (pending == null) return;
      style = MessagingStyleInformation(
        const notify.Person(key: 'me', name: 'You'),
        groupConversation: false,
        messages: [for (final p in pending) notify.Message(p.text, p.at, them)],
      );
    }
    await _local.show(
      id: id,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          n.moment ? moments.id : messages.id,
          n.moment ? moments.name : messages.name,
          channelDescription: n.moment
              ? moments.description
              : messages.description,
          icon: 'ic_notification',
          importance: n.moment ? Importance.max : Importance.high,
          priority: Priority.high,
          category: n.moment
              ? AndroidNotificationCategory.social
              : AndroidNotificationCategory.message,
          color: n.tint == null ? VColors.notifyAccent : VPenColors.of(n.tint!),
          largeIcon: avatar == null ? null : FilePathAndroidBitmap(avatar),
          styleInformation: style,
          when: DateTime.now().millisecondsSinceEpoch,
          // One notification per kind: messages grow into a conversation.
          tag: n.moment ? 'moment' : 'messages',
        ),
      ),
    );
  }

  static File _pendingFile(Directory dir) => File('${dir.path}/notified.json');

  /// Adds a message to the ones shown since August was last open, and
  /// returns them (the last few, oldest first), or null when [key] was
  /// shown already.
  static Future<List<({String text, DateTime at})>?> _remember(
    Directory dir, {
    required String? key,
    required String text,
  }) async {
    final f = _pendingFile(dir);
    var list = <Map<String, Object?>>[];
    try {
      if (f.existsSync()) {
        list = [
          for (final e in jsonDecode(await f.readAsString()) as List)
            (e as Map).cast<String, Object?>(),
        ];
      }
    } on Object {
      list = [];
    }
    if (key != null && list.any((e) => e['key'] == key)) return null;
    list = [
      ...list,
      {'key': key, 'text': text, 'at': DateTime.now().toIso8601String()},
    ];
    if (list.length > 6) list = list.sublist(list.length - 6);
    try {
      await f.writeAsString(jsonEncode(list), flush: true);
    } on Object {
      // Can't write: it shows just this one.
    }
    return [
      for (final e in list)
        (
          text: e['text']! as String,
          at: DateTime.tryParse(e['at'] as String? ?? '') ?? DateTime.now(),
        ),
    ];
  }

  /// The partner's picture for the notification: their photo, or their
  /// initial drawn as August does (Doto on a dark round), as a file.
  static Future<String?> _avatar(
    String name,
    String? photo,
    Directory dir,
  ) async {
    if (photo != null && File(photo).existsSync()) return photo;
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final f = File(
      '${dir.path}/notify-avatar-${letter.codeUnits.join('-')}.png',
    );
    if (f.existsSync()) return f.path;
    try {
      const size = 192.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 2,
        Paint()..color = VColors.notifyAvatar,
      );
      final pb =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: TextAlign.center,
                fontFamily: 'Doto',
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: VColors.white,
                fontSize: 104,
                fontFamily: 'Doto',
                fontWeight: FontWeight.w900,
              ),
            )
            ..addText(letter);
      final para = pb.build()
        ..layout(const ui.ParagraphConstraints(width: size));
      canvas.drawParagraph(para, Offset(0, (size - para.height) / 2));
      final image = await recorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await f.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      return f.path;
    } on Object {
      return null; // Android's default look, then.
    }
  }

  /// Takes down August's notifications and forgets the stacked messages
  /// (August is open: they're being read).
  static Future<void> clear() async {
    try {
      await _local.cancelAll();
      final f = _pendingFile(await DataHome.dir());
      if (f.existsSync()) await f.delete();
    } on Object {
      // Nothing to clear.
    }
  }
}

/// A push while August is in the background or closed: its own isolate.
@pragma('vm:entry-point')
Future<void> _background(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final dir = await DataHome.dir();
  // The widget's doodle changed on the other phone: redraw it, quietly.
  if (message.data['kind'] == 'wake') {
    final config = NeonConfig.fromEnvironment;
    if (config == null) return;
    final b = await NeonBackend.open(
      config,
      vault: await DataHome.vault(),
      dir: dir,
    );
    try {
      await refreshWidgetInBackground(
        api: b.api,
        identity: b.identity,
        store: await LocalStore.open(dir),
        dir: dir,
      );
    } on Object {
      // Offline: the background check or the app will redraw it.
    }
    return;
  }
  await Push.ready();
  final store = await LocalStore.open(dir);
  final n = await Push.describe(
    message.data,
    vault: await DataHome.vault(),
    store: store,
  );
  if (n != null) {
    await Push.show(
      n,
      id: n.moment ? 2 : 1,
      key: message.data['id'] as String?,
      store: store,
    );
  }
}
