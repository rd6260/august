import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/v_palette.dart';
import '../core/theme/v_text.dart';
import '../core/widgets/v_glass.dart';
import '../core/widgets/v_ink.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../features/common/avatar.dart';
import 'router.dart';

/// The in-app notification: a message from the partner while you're not
/// looking at the chat (another tab, or a page over it) slides a banner
/// down from the top. Tap it for the chat; swipe it up, or it goes after
/// 4 s. Moments have their burst and calls their screen, so not those.
class MessageBannerListener extends ConsumerStatefulWidget {
  const MessageBannerListener({super.key, required this.onChat});

  /// Whether the chat is what's showing (its tab, nothing over it).
  final bool Function() onChat;

  @override
  ConsumerState<MessageBannerListener> createState() =>
      _MessageBannerListenerState();
}

class _MessageBannerListenerState extends ConsumerState<MessageBannerListener> {
  OverlayEntry? _shown;

  @override
  void dispose() {
    _shown?.remove();
    _shown = null;
    super.dispose();
  }

  void _show(Message m) {
    final session = ref.read(sessionProvider);
    if (session.decoy || (session.locked && session.pin.isNotEmpty)) return;
    if (widget.onChat()) return;
    unawaited(HapticFeedback.lightImpact());
    _shown?.remove();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Banner(
        key: ValueKey(m.id),
        partner: ref.read(pairingProvider).partner,
        text: m.quote().text,
        onTap: () {
          _close(entry);
          // The chat, with whatever was over it closed.
          final nav = Navigator.of(context, rootNavigator: true);
          nav.popUntil((r) => r.isFirst);
          GoRouter.of(context).go(Routes.chat);
        },
        onDone: () => _close(entry),
      ),
    );
    _shown = entry;
    overlay.insert(entry);
  }

  void _close(OverlayEntry entry) {
    if (!entry.mounted) return;
    entry.remove();
    if (identical(_shown, entry)) _shown = null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<Message>>(messagesProvider, (before, now) {
      final known = {for (final m in before ?? const <Message>[]) m.id};
      final fresh = now.where(
        (m) =>
            !m.fromMe &&
            !known.contains(m.id) &&
            m.body is! MomentBody &&
            m.body is! CallBody &&
            m.body is! SystemBody,
      );
      if (fresh.isNotEmpty) _show(fresh.last);
    });
    return const SizedBox.shrink();
  }
}

class _Banner extends StatefulWidget {
  const _Banner({
    super.key,
    required this.partner,
    required this.text,
    required this.onTap,
    required this.onDone,
  });

  final Person partner;
  final String text;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), _away);
  }

  Future<void> _away() async {
    _timer?.cancel();
    if (!mounted) return;
    await _in.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final ink = VInk.of(context);
    final slide = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return Positioned(
      left: 12,
      right: 12,
      top: top + 8,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(slide),
        child: FadeTransition(
          opacity: slide,
          child: GestureDetector(
            onTap: widget.onTap,
            // Swiped up: away.
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -100) unawaited(_away());
            },
            child: Semantics(
              button: true,
              liveRegion: true,
              label: '${widget.partner.name}: ${widget.text}. Open the chat',
              excludeSemantics: true,
              child: VGlass(
                radius: 20,
                tint: VPalette.of(context).glassSheet,
                blur: 16,
                border: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                  child: Row(
                    children: [
                      Avatar(widget.partner, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.partner.name,
                              style: VText.inter(14, weight: 600),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              widget.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VText.inter(13)
                                  .copyWith(color: ink.withValues(alpha: 0.75)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
