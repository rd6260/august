import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../core/theme/v_colors.dart';
import '../data/chat_theme.dart';
import '../data/models.dart';
import '../features/common/strokes.dart';

/// The home screen widget (Android): the doodle you both picked, drawn on
/// its paper, with who changed it last and when.
///
/// August draws the picture here (in the app, or in a background isolate
/// when a wake push or the background check finds changes) and hands the
/// file to `DoodleWidget.kt`, which shows it.
abstract final class DoodleWidget {
  static const provider = 'com.rd6260.august.DoodleWidget';

  /// Tapping the widget opens August with this, plus `?id=<board>`.
  static const scheme = 'august';
  static const host = 'doodle';

  static bool get supported => Platform.isAndroid;

  /// Whether this phone has at least one August widget on a home screen.
  static Future<bool> placed() async {
    if (!supported) return false;
    try {
      final all = await HomeWidget.getInstalledWidgets();
      return all.any(
        (w) => w.androidClassName?.endsWith('DoodleWidget') ?? false,
      );
    } on Object {
      return false;
    }
  }

  /// Has home_widget's background engine redraw the widget from what's saved
  /// on this phone. The open app uses this rather than drawing it itself:
  /// its engine reads the picture back from the GPU in a way that comes out
  /// sheared into bands on some phones (the background engine doesn't).
  static Future<void> redrawInBackground() async {
    if (!supported) return;
    try {
      await const MethodChannel('august/window')
          .invokeMethod<void>('redrawWidget');
    } on Object {
      // No such channel here (tests): nothing to redraw.
    }
  }

  /// Asks the launcher to add the widget (Android 8+, most launchers).
  static Future<void> add() async {
    if (!supported) return;
    try {
      await HomeWidget.requestPinWidget(qualifiedAndroidName: provider);
    } on Object {
      // The launcher can't: they add it from the widget list instead.
    }
  }

  /// Redraws the widget: [doodle] (null when none is picked or the board is
  /// gone), on [theme]'s ink. [dir] is where the picture is kept.
  /// Redraws run one after another in an isolate, so one can't remove the
  /// picture another has just handed to the widget.
  static Future<void> _last = Future.value();

  static Future<void> show({
    required Doodle? doodle,
    required ChatTheme theme,
    required Directory dir,
    DateTime? now,
  }) {
    if (!supported) return Future.value();
    return _last = _last
        .catchError((Object _) {})
        .then((_) => _show(doodle: doodle, theme: theme, dir: dir, now: now));
  }

  static Future<void> _show({
    required Doodle? doodle,
    required ChatTheme theme,
    required Directory dir,
    DateTime? now,
  }) async {
    String? path;
    if (doodle != null) {
      final png = await render(doodle, theme);
      // A new name each time (the launcher may cache a bitmap by its path),
      // written whole before the widget can see it.
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final file = File('${dir.path}/widget-doodle-$stamp.png');
      final part = File('${file.path}.part');
      await part.writeAsBytes(png, flush: true);
      await part.rename(file.path);
      path = file.path;
      // Keep the newest few: another isolate (a wake-up push, the
      // background check) may be showing one of them right now.
      final kept = [
        for (final f in dir.listSync().whereType<File>())
          if (RegExp(r'widget-doodle-\d+\.png$').hasMatch(f.path)) f,
      ]..sort((a, b) => b.path.compareTo(a.path));
      for (final old in kept.skip(3)) {
        try {
          old.deleteSync();
        } on Object {
          // In use or gone: next time.
        }
      }
    }
    await HomeWidget.saveWidgetData<String>('doodle_path', path);
    await HomeWidget.saveWidgetData<String>('doodle_id', doodle?.id);
    await HomeWidget.saveWidgetData<String>(
      'doodle_caption',
      doodle == null ? null : caption(doodle, now: now),
    );
    await HomeWidget.saveWidgetData<bool>('doodle_light', theme.isLight);
    await HomeWidget.updateWidget(qualifiedAndroidName: provider);
  }

  /// "Shruti · 14:32" today, "Shruti · 12 Mar" before. A clock time, not
  /// "2 min ago": the widget only redraws when the doodle changes.
  static String caption(Doodle d, {DateTime? now}) {
    final at = d.editedAt;
    final today = now ?? DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final sameDay =
        at.year == today.year && at.month == today.month && at.day == today.day;
    final when = sameDay
        ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
        : '${at.day} ${months[at.month - 1]}';
    return '${d.editedBy} · $when';
  }

  /// The doodle as a square PNG, [size] pixels a side: its paper filling
  /// the square, and its strokes fitted to the middle.
  /// [size] stays a multiple of 64: some phones' GPUs hand the pixels
  /// back with each row padded to 64 or 256 bytes, which the PNG encoder
  /// doesn't expect, and the picture comes out sheared into diagonal bands.
  /// 640 × 4 bytes a row needs no padding.
  static Future<Uint8List> render(
    Doodle d,
    ChatTheme theme, {
    int size = 640,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final box = Size(size.toDouble(), size.toDouble());
    paintWidgetDoodle(canvas, box, d, theme);
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}

/// Draws [d] for the widget into [box] (also used by tests and previews).
void paintWidgetDoodle(Canvas canvas, Size box, Doodle d, ChatTheme theme) {
  final ink = theme.isLight ? VColors.black : VColors.white;
  final surface = VColors.onColor(ink);
  final palette = theme.wallpaper.photo == null
      ? VWallpapers.all[theme.wallpaper.builtin]
      : null;

  // The paper fills the whole square.
  if (d.paper == Paper.wallpaper && palette != null) {
    _paintPalette(canvas, box, palette);
  } else {
    canvas.drawRect(Offset.zero & box, Paint()..color = surface);
  }
  final grid = box.width / 390 * 22 * 1.4;
  final p = Paint()..color = ink.withValues(alpha: 0.22);
  switch (d.paper) {
    case Paper.dotted:
      for (var y = grid / 2; y < box.height; y += grid) {
        for (var x = grid / 2; x < box.width; x += grid) {
          canvas.drawCircle(Offset(x, y), grid * 0.05, p);
        }
      }
    case Paper.lined:
      p.strokeWidth = math.max(1, grid * 0.045);
      for (var y = grid * 1.27; y < box.height; y += grid * 1.27) {
        canvas.drawLine(Offset(0, y), Offset(box.width, y), p);
      }
    case Paper.plain:
    case Paper.wallpaper:
      break;
  }

  // The strokes: their bounds (with each pen's width) fitted, centred, with
  // a margin, so a small drawing still fills the widget.
  final strokes = d.strokes.where((s) => s.points.isNotEmpty).toList();
  if (strokes.isEmpty) return;
  var bounds = Rect.zero;
  var first = true;
  for (final s in strokes) {
    if (s.tool == PenTool.eraser) continue;
    final r = strokeBounds(s);
    if (r == null) continue;
    bounds = first ? r : bounds.expandToInclude(r);
    first = false;
  }
  if (first) return;
  // Never zoom past 3× the board, so a dot doesn't become a blob.
  final margin = box.shortestSide * 0.1;
  final room = (Offset.zero & box).deflate(margin);
  final scale = math.min(
    3.0 * box.width / 390,
    math.min(
      room.width / math.max(bounds.width, 1),
      room.height / math.max(bounds.height, 1),
    ),
  );
  canvas.save();
  canvas.translate(box.width / 2, box.height / 2);
  canvas.scale(scale);
  canvas.translate(-bounds.center.dx, -bounds.center.dy);
  canvas.saveLayer(bounds.inflate(4), Paint());
  for (final s in strokes) {
    paintStroke(canvas, s);
  }
  canvas.restore();
  canvas.restore();
}

void _paintPalette(Canvas canvas, Size size, VWallpaperPalette palette) {
  canvas.drawRect(Offset.zero & size, Paint()..color = palette.base);
  final longer = math.max(size.width, size.height);
  for (final b in palette.blobs) {
    final c = Offset(
      size.width / 2 + b.x * size.width / 2,
      size.height / 2 + b.y * size.height / 2,
    );
    final r = b.radius * longer;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [b.color, b.color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }
}
