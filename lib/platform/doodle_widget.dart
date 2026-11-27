import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
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
  static Future<void> show({
    required Doodle? doodle,
    required ChatTheme theme,
    required Directory dir,
    DateTime? now,
  }) async {
    if (!supported) return;
    String? path;
    if (doodle != null) {
      final png = await render(doodle, theme);
      // A new name each time: the launcher may cache a bitmap by its path.
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final file = File('${dir.path}/widget-doodle-$stamp.png');
      await file.writeAsBytes(png, flush: true);
      path = file.path;
      for (final old in dir.listSync().whereType<File>()) {
        final name = old.uri.pathSegments.last;
        if (name.startsWith('widget-doodle-') && old.path != path) {
          try {
            old.deleteSync();
          } on Object {
            // In use or gone: next time.
          }
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

  /// "Aatika · 14:32" today, "Aatika · 12 Mar" before. A clock time, not
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
  static Future<Uint8List> render(
    Doodle d,
    ChatTheme theme, {
    int size = 720,
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
    for (final pt in s.points) {
      final r = Rect.fromCircle(center: pt, radius: s.size / 2);
      bounds = first ? r : bounds.expandToInclude(r);
      first = false;
    }
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
