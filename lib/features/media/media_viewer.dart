import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../common/art.dart';
import '../common/video_frame.dart';
import '../common/parts.dart';
import '../common/rotation.dart';
import '../common/toast.dart';

/// One item the viewer can show, with who sent it and when.
class ViewerItem {
  const ViewerItem({
    required this.media,
    required this.from,
    required this.at,
    this.message,
  });

  final Media media;
  final String from;
  final DateTime at;

  /// The message it came in, for Reply.
  final Message? message;

  bool get video => media.duration != null;
}

/// Every photo and video in [messages], oldest first.
List<ViewerItem> viewerItems(
  List<Message> messages, {
  required String partner,
}) => [
  for (final m in messages)
    ...switch (m.body) {
      PhotoBody(:final photos) => photos,
      VideoBody(:final video) => [video],
      RoundVideoBody(:final video) => [video],
      _ => const <Media>[],
    }.map(
      (media) => ViewerItem(
        media: media,
        from: m.fromMe ? 'You' : partner,
        at: m.at,
        message: m,
      ),
    ),
];

/// The media viewer (C21): full screen on the page colour, swipe between
/// every photo and video in the chat, pinch to zoom, video controls, and
/// Reply / Save / Share.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.items,
    required this.start,
    this.onReply,
  });

  final List<ViewerItem> items;
  final int start;
  final void Function(ViewerItem item)? onReply;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final _page = PageController(initialPage: widget.start);
  late int _at = widget.start;
  bool _playing = false;
  double _position = 0;
  Timer? _clock;

  /// The real video on screen, when its file is on the phone.
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
  }

  @override
  void dispose() {
    _zoom.dispose();
    _clock?.cancel();
    _video?.dispose();
    _page.dispose();
    super.dispose();
  }

  void _dropVideo() {
    final v = _video;
    _video = null;
    unawaited(v?.dispose());
  }

  Future<void> _toggle() async {
    final item = widget.items[_at];
    _clock?.cancel();
    final path = item.media.path;
    if (path != null) {
      var v = _video;
      if (v == null) {
        v = _video = VideoPlayerController.file(File(path));
        try {
          await v.initialize();
        } on Object {
          _video = null;
          unawaited(v.dispose());
          if (mounted) showToast(context, "This video can't play here");
          return;
        }
        v.addListener(() {
          if (!mounted || _video != v) return;
          final d = v!.value.duration.inMilliseconds;
          final ended = d > 0 && v.value.position.inMilliseconds >= d - 50;
          setState(() {
            _playing = v!.value.isPlaying && !ended;
            _position = d == 0 ? 0 : v.value.position.inMilliseconds / d;
            if (ended) _position = 1;
          });
        });
      }
      if (v.value.isPlaying) {
        await v.pause();
      } else {
        if (v.value.position >= v.value.duration) await v.seekTo(Duration.zero);
        await v.play();
      }
      return;
    }
    if (_playing) {
      setState(() => _playing = false);
      return;
    }
    final total = item.media.duration!.inMilliseconds;
    setState(() => _playing = true);
    _clock = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        _position += 100 / total;
        if (_position >= 1) {
          _position = 0;
          _playing = false;
          _clock?.cancel();
        }
      });
    });
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final day = d == today
        ? 'Today'
        : today.difference(d).inDays == 1
        ? 'Yesterday'
        : '${t.day}/${t.month}';
    return '$day, ${hhmm(t)}';
  }

  Widget _header(ViewerItem item) => Row(
    children: [
      VCircleButton(
        icon: VIcon.back,
        size: 44,
        onTap: () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.from, style: VText.inter(15, weight: 600)),
            Text(
              '${_when(item.at)} · ${_at + 1} of ${widget.items.length}',
              style: VText.secondary,
            ),
          ],
        ),
      ),
    ],
  );

  /// The header and actions: a tap on the picture hides them, and another
  /// brings them back.
  bool _chrome = true;

  /// The photo on screen is zoomed: swiping to the next waits, so a drag
  /// moves the photo instead.
  bool _zoomed = false;
  final _zoom = TransformationController();
  TapDownDetails? _doubleTapAt;

  void _onZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  /// Double-tap: 2.5× where you tapped, or back to fit.
  void _doubleTap() {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final at = _doubleTapAt?.localPosition ?? Offset.zero;
    const k = 2.5;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-at.dx * (k - 1), -at.dy * (k - 1), 0, 1)
      ..scaleByDouble(k, k, 1, 1);
  }

  Widget _pages() => PageView.builder(
    controller: _page,
    physics: _zoomed
        ? const NeverScrollableScrollPhysics()
        : const PageScrollPhysics(),
    itemCount: widget.items.length,
    onPageChanged: (i) {
      _clock?.cancel();
      _zoom.value = Matrix4.identity();
      _dropVideo();
      setState(() {
        _at = i;
        _playing = false;
        _position = 0;
      });
    },
    itemBuilder: (context, i) {
      final it = widget.items[i];
      return GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        onDoubleTapDown: (d) => _doubleTapAt = d,
        onDoubleTap: i == _at && !it.video ? _doubleTap : null,
        child: InteractiveViewer(
          // Only the photo on screen zooms (one controller).
          transformationController: i == _at ? _zoom : null,
          minScale: 1,
          maxScale: 5,
          panEnabled: _zoomed,
          onInteractionUpdate: (_) => _onZoom(),
          onInteractionEnd: (_) => _onZoom(),
          child: Center(
            child: AspectRatio(
              aspectRatio: it.media.aspect,
              child: ArtBox(
                art: it.media.art,
                path: it.video ? null : it.media.path,
                full: true,
                child: it.video
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          if (i == _at && _video?.value.isInitialized == true)
                            VideoPlayer(_video!)
                          else if (it.media.path case final path?)
                            VideoFrame(path),
                          Center(
                            child: Semantics(
                              button: true,
                              label: _playing ? 'Pause' : 'Play',
                              child: VTappable(
                                onTap: _toggle,
                                child: Opacity(
                                  opacity: _playing && i == _at ? 0 : 1,
                                  child: Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: VColors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                    child: const Center(
                                      child: VIconView(
                                        VIcon.play,
                                        size: 28,
                                        color: VColors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _scrubber(ViewerItem item) {
    final total = item.media.duration ?? Duration.zero;
    return Row(
      children: [
        Text(mss(total * _position), style: VText.doto(13)),
        const SizedBox(width: 10),
        Expanded(child: VBar(value: _position, height: 4)),
        const SizedBox(width: 10),
        Text(mss(total), style: VText.doto(13)),
      ],
    );
  }

  /// Into the phone's gallery (Pictures/August, Movies/August); on the
  /// desktop, into Downloads.
  Future<void> _save(ViewerItem item) async {
    final path = item.media.path;
    if (path == null) {
      showToast(context, "It isn't on this phone yet");
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    try {
      if (Platform.isAndroid) {
        if (!await Gal.hasPermission(toAlbum: true)) {
          await Gal.requestPermission(toAlbum: true);
        }
        final ext = item.video ? 'mp4' : _imageExt(path);
        final named = await File(path).copy(
          '${(await getTemporaryDirectory()).path}/august-${item.media.id}.$ext',
        );
        item.video
            ? await Gal.putVideo(named.path, album: 'August')
            : await Gal.putImage(named.path, album: 'August');
      } else {
        final dir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        await File(path).copy(
          '${dir.path}/august-${item.media.id}.${item.video ? 'mp4' : _imageExt(path)}',
        );
      }
      if (mounted) showToast(context, 'Saved');
    } on Object {
      if (mounted) showToast(context, "Couldn't save it");
    }
  }

  Future<void> _share(ViewerItem item) async {
    final path = item.media.path;
    if (path == null) {
      showToast(context, "It isn't on this phone yet");
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    final ext = item.video ? 'mp4' : _imageExt(path);
    final named = await File(path).copy(
      '${(await getTemporaryDirectory()).path}/august-${item.media.id}.$ext',
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(named.path, mimeType: item.video ? 'video/mp4' : 'image/$ext'),
        ],
      ),
    );
  }

  /// The image's real type from its first bytes (files are kept without
  /// an extension).
  static String _imageExt(String path) {
    final head = File(path).openSync()..setPositionSync(0);
    final b = head.readSync(12);
    head.closeSync();
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpeg';
    if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length >= 12 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
    if (b.length >= 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
    return 'jpeg';
  }

  Widget _actions(ViewerItem item) => VGlass(
    radius: 26,
    tint: VColors.black.withValues(alpha: 0.35),
    blur: 18,
    border: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Action(VIcon.reply, 'Reply', () {
            Navigator.of(context).pop();
            widget.onReply?.call(item);
          }),
          _Action(VIcon.download, 'Save', () => unawaited(_save(item))),
          _Action(VIcon.share, 'Share', () => unawaited(_share(item))),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_at];
    const fade = Duration(milliseconds: 200);
    // Full screen on black, whatever the theme: the picture edge to edge,
    // the header and actions floating over it on soft shades. Turning the
    // phone keeps the same layout.
    final top = Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              VColors.black.withValues(alpha: 0.55),
              VColors.black.withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: _header(item),
          ),
        ),
      ),
    );
    final bottom = Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              VColors.black.withValues(alpha: 0.55),
              VColors.black.withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.video) ...[
                      _scrubber(item),
                      const SizedBox(height: 14),
                    ],
                    _actions(item),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Widget chrome(Positioned p) => Positioned(
      left: p.left,
      right: p.right,
      top: p.top,
      bottom: p.bottom,
      child: IgnorePointer(
        ignoring: !_chrome,
        child: AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: fade,
          child: p.child,
        ),
      ),
    );
    return AllowRotation(
      child: VQuiet(
        child: VInkScope(
          ink: VColors.white,
          child: ColoredBox(
            color: VColors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [_pages(), chrome(top), chrome(bottom)],
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);

  final VIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: VTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VIconView(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, style: VText.inter(12, weight: 500)),
          ],
        ),
      ),
    ),
  );
}
