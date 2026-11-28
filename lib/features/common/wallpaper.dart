import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import 'art.dart';
import '../../data/chat_theme.dart';

/// Decodes [image] (if not already) and completes when it can be drawn.
Future<void> warmImage(ImageProvider image) {
  final done = Completer<void>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish() {
    if (!done.isCompleted) done.complete();
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (_, _) => finish(),
    onError: (_, _) => finish(),
  );
  stream.addListener(listener);
  return done.future;
}

/// Draws a layout's wallpaper: a built-in palette or a photo, with its dim.
///
/// When the wallpaper changes, the new one is decoded first and then fades
/// in over the old one, so a layout switch never shows an empty or
/// half-loaded frame.
class WallpaperView extends StatefulWidget {
  const WallpaperView({
    super.key,
    required this.wallpaper,
    this.dim = 0,
    this.blur = 0,
    this.soft = false,
  });

  final WallpaperRef wallpaper;
  final double dim;

  /// Blur over a photo (0–1). Shown from the file [bakeBlur] wrote; until
  /// that exists, blurred live.
  final double blur;

  /// A blurred-looking copy: photos are decoded tiny and scaled up, which
  /// reads as a heavy blur at no per-frame cost. Built-in palettes are soft
  /// already.
  final bool soft;

  @override
  State<WallpaperView> createState() => _WallpaperViewState();
}

class _WallpaperViewState extends State<WallpaperView> {
  /// Blur is being changed (a slider dragged): drawn live, straight from
  /// the setting, until it rests.
  bool _moving = false;
  Timer? _settle;

  late _Shown _shown = _Shown.of(widget, moving: _moving);
  int _generation = 0;

  /// Counts the wallpapers shown, to key each one in the cross-fade. Not
  /// [_Shown.key]: a wallpaper can come back while its earlier copy is still
  /// fading out, and two children of the fade can't share a key.
  int _layer = 0;

  @override
  void didUpdateWidget(WallpaperView old) {
    super.didUpdateWidget(old);
    if (old.blur != widget.blur && old.wallpaper == widget.wallpaper) {
      _moving = true;
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 450), () {
        _moving = false;
        if (mounted) _update();
      });
    }
    _update();
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  /// Shows the wallpaper as the settings are now. The same picture with a
  /// new blur redraws in place, every frame of a drag; only a different
  /// picture fades in (once it's decoded, so never half-loaded).
  void _update() {
    final next = _Shown.of(widget, moving: _moving);
    if (next.key == _shown.key) {
      _generation++;
      setState(() => _shown = next);
      return;
    }
    final generation = ++_generation;
    void show() => setState(() {
      _shown = next;
      _layer++;
    });
    final image = next.image;
    if (image == null) return show();
    warmImage(image).then((_) {
      if (mounted && generation == _generation) show();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dim = widget.dim.clamp(0.0, 0.8);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: KeyedSubtree(key: ValueKey(_layer), child: _shown.build()),
        ),
        // Over whatever shows, so Dim follows its slider frame by frame.
        if (dim > 0) ColoredBox(color: VColors.black.withValues(alpha: dim)),
      ],
    );
  }
}

/// One wallpaper picture as it is drawn. Its key changes when a different
/// picture (another photo or palette, or the blurred copy) is needed; not
/// for the dim, or for the amount of a live blur, which redraw in place.
class _Shown {
  _Shown(this.key, this.image, this.build);

  factory _Shown.of(WallpaperView w, {required bool moving}) {
    final photo = w.wallpaper.photo;
    Widget blurred(double b, Widget child) => b <= 0.01
        ? child
        : ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: b * 30,
              sigmaY: b * 30,
              tileMode: TileMode.clamp,
            ),
            child: child,
          );

    if (photo == null) {
      final palette = VWallpapers.all[w.wallpaper.builtin] ?? VWallpapers.night;
      return _Shown('b:${w.wallpaper.builtin}', null, () => _Palette(palette));
    }
    // A photo stand-in from the mock data ('mock:<art>').
    if (photo.startsWith('mock:')) {
      final art = int.tryParse(photo.substring(5)) ?? 0;
      final b = w.soft ? 0.0 : w.blur;
      return _Shown(
        'm:$photo',
        null,
        () => blurred(
          b,
          ArtBox(
            art: art,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      );
    }
    final blur = w.soft ? 0.0 : w.blur;
    final ImageProvider image;
    final String key;
    var live = 0.0;
    if (w.soft) {
      image = ResizeImage(FileImage(File(photo)), width: 40);
      key = 'p:$photo:soft';
    } else if (blur <= 0.01) {
      image = ResizeImage(FileImage(File(photo)), width: 1440);
      key = 'p:$photo:sharp';
    } else if (!moving && blurReady(photo, blur)) {
      // At rest, the copy blurred once into a file: no cost per frame.
      image = FileImage(File(bakedPath(photo, blur)));
      key = 'p:$photo:baked:${(blur * 100).round()}';
    } else {
      // Being adjusted (or not baked yet): blurred live, one picture for
      // every amount, so it follows the slider without a fade.
      image = ResizeImage(FileImage(File(photo)), width: 720);
      key = 'p:$photo:live';
      live = blur;
    }
    return _Shown(
      key,
      image,
      () => blurred(
        live,
        Image(
          image: image,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: w.soft ? FilterQuality.high : FilterQuality.medium,
          errorBuilder: (_, _, _) => const _Palette(VWallpapers.night),
        ),
      ),
    );
  }

  final String key;
  final ImageProvider? image;
  final Widget Function() build;
}

/// Whether the blurred copy of [photo] at [blur] already exists.
bool blurReady(String photo, double blur) =>
    File(bakedPath(photo, blur)).existsSync();

/// Where the blurred copy of [photo] at [blur] is kept.
String bakedPath(String photo, double blur) =>
    '$photo.b${(blur * 100).round()}.png';

/// Renders [photo] blurred once and saves it beside the photo, so Home shows
/// a plain image instead of blurring a full-screen photo on every frame.
Future<void> bakeBlur(String photo, double blur) async {
  if (blur <= 0.01) return;
  final out = File(bakedPath(photo, blur));
  if (out.existsSync()) return;
  final codec = await ui.instantiateImageCodec(
    await File(photo).readAsBytes(),
    targetWidth: 720,
  );
  final image = (await codec.getNextFrame()).image;
  final w = image.width.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final sigma = blur * 30 * (w / 412);
  canvas.drawImage(
    image,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
  );
  final blurred = await recorder.endRecording().toImage(
    image.width,
    image.height,
  );
  final png = await blurred.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  blurred.dispose();
  if (png != null) await out.writeAsBytes(png.buffer.asUint8List());
}

/// Deletes a saved photo and every blurred copy of it.
Future<void> deletePhoto(String photo) async {
  final file = File(photo);
  final dir = file.parent;
  if (!dir.existsSync()) return;
  final name = file.uri.pathSegments.last;
  await for (final f in dir.list()) {
    if (f is File && f.uri.pathSegments.last.startsWith(name)) {
      await f.delete();
    }
  }
}

/// Whether a wallpaper suggests black ink.
bool wallpaperIsLight(WallpaperRef w) =>
    w.photo == null && (VWallpapers.all[w.builtin]?.light ?? false);

class _Palette extends StatelessWidget {
  const _Palette(this.palette);

  final VWallpaperPalette palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PalettePainter(palette),
      child: const SizedBox.expand(),
    );
  }
}

class _PalettePainter extends CustomPainter {
  _PalettePainter(this.palette);

  final VWallpaperPalette palette;

  @override
  void paint(Canvas canvas, Size size) =>
      paintWallpaperPalette(canvas, size, palette);

  @override
  bool shouldRepaint(_PalettePainter old) => old.palette != palette;
}

/// Paints a built-in wallpaper: its base, then each soft blob.
void paintWallpaperPalette(
  Canvas canvas,
  Size size,
  VWallpaperPalette palette,
) {
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
