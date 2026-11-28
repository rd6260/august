import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_slider.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/chat_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../mock/mock_data.dart';
import '../../platform/data_home.dart';
import '../common/art.dart';
import '../common/overlay.dart';
import '../common/wallpaper.dart';

/// Opens the shared theme sheet (C22). Changes show live behind it; Apply
/// keeps them for both of you, anything else puts the old theme back.
Future<void> showThemeSheet(BuildContext context, WidgetRef ref) async {
  final before = ref.read(chatThemeProvider);
  final applied = await showOverlayPage<bool>(
    context,
    (_) => const ThemeSheet(),
  );
  if (applied != true) {
    ref.read(chatThemeProvider.notifier).set(before);
    return;
  }
  final after = ref.read(chatThemeProvider);
  if (after == before) return;
  ref.read(chatRepositoryProvider).shareTheme(after);
  final name = after.wallpaper.builtin;
  ref
      .read(messagesProvider.notifier)
      .send(
        SystemBody(
          after.wallpaper != before.wallpaper && name == null
              ? SystemKind.wallpaper
              : SystemKind.theme,
          name == null
              ? 'You changed the wallpaper'
              : 'You changed the theme to ${name[0].toUpperCase()}${name.substring(1)}',
        ),
      );
}

class ThemeSheet extends ConsumerStatefulWidget {
  const ThemeSheet({super.key});

  @override
  ConsumerState<ThemeSheet> createState() => _ThemeSheetState();
}

class _ThemeSheetState extends ConsumerState<ThemeSheet> {
  // On Neon the slots start with this phone's current photo, if any; the
  // mock shows the canvas's stand-ins.
  late final List<String> _photos = ref.read(onNeonProvider)
      ? [?ref.read(chatThemeProvider).wallpaper.photo]
      : [...MockData.themePhotos];

  void _set(ChatTheme t) => ref.read(chatThemeProvider.notifier).set(t);

  Future<void> _addPhoto() async {
    // The phone's gallery on Neon; stand-in art on the mock.
    final source = ref.read(mediaSourceProvider);
    final String photo;
    if (source != null) {
      final picked = await source.gallery();
      if (picked.isEmpty || picked.first.path == null || !mounted) return;
      photo = picked.first.path!;
    } else {
      photo = 'mock:${(_photos.length * 3 + 1) % 10}';
    }
    final used = await pushPage<(WallpaperRef, InkChoice)>(
      context,
      (_) => WallpaperCrop(photo: photo),
    );
    if (used == null || !mounted) return;
    final (wallpaper, ink) = used;
    setState(() => _photos.add(wallpaper.photo!));
    _set(ref.read(chatThemeProvider).copyWith(wallpaper: wallpaper, ink: ink));
  }

  /// The slider being dragged (Dim, Blur or Glass), or null. Meanwhile the
  /// rest of the sheet steps aside, so the chat shows the change.
  String? _adjusting;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(chatThemeProvider);
    final ink = VInk.of(context);
    TextStyle label() =>
        VText.eyebrow.copyWith(color: ink.withValues(alpha: 0.55));
    const fade = Duration(milliseconds: 180);
    final away = _adjusting != null;

    /// Shown unless a slider (other than [keep]) is being dragged. The one
    /// being dragged gets its own small glass panel, so it reads over the
    /// chat while everything else is gone.
    Widget unless(Widget child, {String? keep}) {
      final hide = away && _adjusting != keep;
      final lifted = away && keep != null && _adjusting == keep;
      return AnimatedOpacity(
        opacity: hide ? 0 : 1,
        duration: fade,
        child: IgnorePointer(
          ignoring: hide,
          child: AnimatedContainer(
            duration: fade,
            padding: EdgeInsets.all(lifted ? 12 : 0),
            decoration: BoxDecoration(
              color: lifted
                  ? VGlass.fill(context, VPalette.of(context).glassSheet)
                  : VColors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: child,
          ),
        ),
      );
    }

    VSlider slider(
      String name, {
      required double value,
      required ValueChanged<double>? onChanged,
      String? display,
    }) => VSlider(
      label: name,
      value: value,
      onChanged: onChanged,
      display: display,
      onChangeStart: () => setState(() => _adjusting = name),
      onChangeEnd: () => setState(() => _adjusting = null),
    );

    // The clean look: soft swatches, "+" and sliders, no outlines.
    return VQuiet(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Stack(
              children: [
                // The sheet itself, faded out while a slider is dragged.
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: away ? 0 : 1,
                    duration: fade,
                    child: VGlass(
                      radius: 28,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      tint: VPalette.of(context).glassSheet,
                      blur: 14,
                      border: false,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        unless(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: ink.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text('Theme', style: VText.doto(26)),
                                  const Spacer(),
                                  Text(
                                    'Changes for both of you',
                                    style: VText.secondary.copyWith(
                                      color: ink.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text('PALETTES', style: label()),
                              const SizedBox(height: 10),
                              GridView(
                                // Not the status bar's inset, which a grid
                                // takes by default.
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                // A tile and its name, whatever the width.
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      mainAxisExtent: 82,
                                    ),
                                children: [
                                  for (final name in VWallpapers.all.keys)
                                    _Swatch(
                                      label: name,
                                      selected: theme.wallpaper.builtin == name,
                                      onTap: () => _set(
                                        theme.copyWith(
                                          wallpaper: WallpaperRef.builtin(name),
                                          ink: InkChoice.auto,
                                        ),
                                      ),
                                      child: WallpaperView(
                                        wallpaper: WallpaperRef.builtin(name),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text('YOUR PHOTOS', style: label()),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  for (final p in _photos) ...[
                                    GestureDetector(
                                      onLongPress: () {
                                        HapticFeedback.mediumImpact();
                                        setState(() => _photos.remove(p));
                                      },
                                      child: _Swatch(
                                        selected: theme.wallpaper.photo == p,
                                        onTap: () => _set(
                                          theme.copyWith(
                                            wallpaper: WallpaperRef.photo(p),
                                            ink: InkChoice.auto,
                                          ),
                                        ),
                                        child: ArtBox(
                                          art:
                                              int.tryParse(p.substring(5)) ?? 0,
                                          path: p.startsWith('mock:')
                                              ? null
                                              : p,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  Semantics(
                                    button: true,
                                    label: 'Add a photo',
                                    child: VTappable(
                                      onTap: _addPhoto,
                                      child: const SizedBox.square(
                                        dimension: 58,
                                        child: VOutlined(
                                          radius: 16,
                                          outline: VOutline.dashed,
                                          child: Center(
                                            child: VIconView(
                                              VIcon.plus,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                        // Dim, blur and glass together, in one soft card;
                        // while one is dragged, it alone, on glass.
                        AnimatedContainer(
                          duration: fade,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          decoration: BoxDecoration(
                            // Gone while one is dragged: that one has its own.
                            color: away
                                ? VColors.transparent
                                : ink.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              unless(
                                keep: 'Dim',
                                slider(
                                  'Dim',
                                  value: theme.dim / 0.8,
                                  onChanged: (v) =>
                                      _set(theme.copyWith(dim: v * 0.8)),
                                  display: '${(theme.dim * 100).round()}%',
                                ),
                              ),
                              const SizedBox(height: 8),
                              unless(
                                keep: 'Blur',
                                Opacity(
                                  opacity: theme.wallpaper.photo == null
                                      ? 0.35
                                      : 1,
                                  child: slider(
                                    'Blur',
                                    value: theme.blur,
                                    onChanged: theme.wallpaper.photo == null
                                        ? null
                                        : (v) => _set(theme.copyWith(blur: v)),
                                    display: '${(theme.blur * 30).round()}',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              unless(
                                keep: 'Glass',
                                slider(
                                  'Glass',
                                  value: theme.glass,
                                  onChanged: (v) =>
                                      _set(theme.copyWith(glass: v)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        unless(
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: VButton.primary(
                              'Apply for both',
                              onPressed: () => Navigator.of(context).pop(true),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.child,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    final tile = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // A faint edge (black and white palettes still show); the chosen one
        // a clear ring around it.
        border: Border.all(color: ink.withValues(alpha: 0.2)),
        boxShadow: selected
            ? [
                BoxShadow(color: paper, spreadRadius: 3),
                BoxShadow(color: ink, spreadRadius: 5),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(15), child: child),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label ?? 'Photo',
      child: VTappable(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile,
            if (label != null) ...[
              const SizedBox(height: 5),
              Text(label!, style: VText.inter(11, weight: 500)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fit a photo as the wallpaper (C23): a frame with a preview of the chat
/// over it, the ink the photo suits, Cancel and Use. Always white ink: it
/// sits on the photo.
class WallpaperCrop extends StatefulWidget {
  const WallpaperCrop({super.key, required this.photo});

  final String photo;

  @override
  State<WallpaperCrop> createState() => _WallpaperCropState();
}

class _WallpaperCropState extends State<WallpaperCrop> {
  var _scale = 1.0;
  var _offset = Offset.zero;
  var _start = 1.0;
  var _busy = false;

  /// [offset], held so the photo still covers the whole screen: scaled by
  /// [_scale] about the middle, it reaches (scale − 1) / 2 of the screen past
  /// each edge, and may move only that far (not at all at 1×).
  Offset _keepCovered(Offset offset, Size screen) {
    final x = (_scale - 1) * screen.width / 2;
    final y = (_scale - 1) * screen.height / 2;
    return Offset(offset.dx.clamp(-x, x), offset.dy.clamp(-y, y));
  }

  /// A photo from the phone (not the mock's stand-in).
  bool get _real => !widget.photo.startsWith('mock:');

  /// What's framed on screen, drawn into a phone-sized JPEG: the wallpaper
  /// both phones get.
  Future<String> _crop(Size screen) async {
    final bytes = await File(widget.photo).readAsBytes();
    final image = (await (await ui.instantiateImageCodec(
      bytes,
    )).getNextFrame()).image;
    final k = math.min(2.5, 1440 / screen.width);
    final out = Size(screen.width * k, screen.height * k);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(k);
    // As the preview draws it: the photo covering the screen, scaled about
    // the middle, then moved.
    final src =
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    final fit = applyBoxFit(BoxFit.cover, src.size, screen);
    final from = Alignment.center.inscribe(fit.source, src);
    final dst = Alignment.center.inscribe(
      fit.destination,
      Offset.zero & screen,
    );
    final mid = screen.center(Offset.zero);
    c
      ..translate(_offset.dx, _offset.dy)
      ..translate(mid.dx, mid.dy)
      ..scale(_scale)
      ..translate(-mid.dx, -mid.dy)
      ..drawImageRect(
        image,
        from,
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
    final framed = await rec.endRecording().toImage(
      out.width.round(),
      out.height.round(),
    );
    final png = (await framed.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final dir = Directory('${(await DataHome.dir()).path}/media');
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    try {
      final jpg = await FlutterImageCompress.compressWithList(
        png,
        quality: 88,
        format: CompressFormat.jpeg,
      );
      return (await File('${dir.path}/wallpaper-$stamp.jpg').writeAsBytes(jpg))
          .path;
    } on Object {
      // No compressor (the desktop build): keep the PNG.
      return (await File('${dir.path}/wallpaper-$stamp.png').writeAsBytes(png))
          .path;
    }
  }

  Future<void> _use(InkChoice ink) async {
    if (_busy) return;
    var photo = widget.photo;
    if (_real) {
      setState(() => _busy = true);
      try {
        photo = await _crop(MediaQuery.sizeOf(context));
      } on Object {
        // Couldn't crop: the whole photo, as it is.
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop((WallpaperRef.photo(photo), ink));
  }

  @override
  // The clean look (soft Cancel and composer), the frame excepted.
  Widget build(BuildContext context) => VQuiet(child: _build(context));

  Widget _build(BuildContext context) {
    final art = _real ? 0 : int.tryParse(widget.photo.substring(5)) ?? 0;
    return VInkScope(
      ink: VColors.white,
      child: ColoredBox(
        color: VColors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onScaleStart: (_) => _start = _scale,
              onScaleUpdate: (d) => setState(() {
                _scale = (_start * d.scale).clamp(1.0, 3.0);
                _offset = _keepCovered(
                  _offset + d.focalPointDelta,
                  MediaQuery.sizeOf(context),
                );
              }),
              child: Transform.translate(
                offset: _offset,
                child: Transform.scale(
                  scale: _scale,
                  child: _real
                      ? Image.file(
                          File(widget.photo),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          filterQuality: FilterQuality.medium,
                        )
                      : ArtBox(
                          art: art,
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                ),
              ),
            ),
            IgnorePointer(
              child: ColoredBox(color: VColors.black.withValues(alpha: 0.3)),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  Text(
                    'Pinch and drag to fit',
                    style: VText.inter(14, weight: 500),
                  ),
                  const Expanded(
                    child: IgnorePointer(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(22, 20, 22, 20),
                        // The frame is the guide to fit to: it stays.
                        child: VOutlined(
                          radius: 28,
                          width: 2,
                          quietable: false,
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _PreviewBubble(
                                    'a preview of your chat',
                                    mine: false,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _PreviewBubble(
                                    'looks so good',
                                    mine: true,
                                  ),
                                ),
                                SizedBox(height: 14),
                                SizedBox(
                                  height: 34,
                                  child: VOutlined(
                                    radius: 17,
                                    outline: VOutline.dashed,
                                    child: SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              'White ink suits this photo',
                              style: VText.inter(12),
                            ),
                            const Spacer(),
                            VLink(
                              'Use black ink',
                              style: VText.inter(12),
                              onTap: () => unawaited(_use(InkChoice.black)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: VButton.secondary(
                                'Cancel',
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: VButton.primary(
                                'Use',
                                onPressed: () =>
                                    unawaited(_use(InkChoice.auto)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble(this.text, {required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      // As the chat draws them now: theirs soft, without an outline.
      color: mine ? VColors.white : VColors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(14),
        topRight: const Radius.circular(14),
        bottomLeft: Radius.circular(mine ? 14 : 4),
        bottomRight: Radius.circular(mine ? 4 : 14),
      ),
    ),
    child: Text(
      text,
      style: VText.inter(12)
          .copyWith(color: mine ? VColors.black : VColors.white),
    ),
  );
}
