import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../data/models.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import 'bubbles.dart';

/// What was picked on the message actions overlay.
sealed class MessageAction {
  const MessageAction();
}

class ReactAction extends MessageAction {
  const ReactAction(this.emoji);
  final String emoji;
}

class ReplyAction extends MessageAction {
  const ReplyAction();
}

class CopyAction extends MessageAction {
  const CopyAction();
}

class SaveAction extends MessageAction {
  const SaveAction();
}

class DeleteAction extends MessageAction {
  const DeleteAction();
}

/// The six quick reactions (B3).
const quickReactions = ['❤️', '😂', '🥺', '😮', '🔥', '👍'];

/// Opens the long-press overlay for [m] (B13).
Future<MessageAction?> showMessageActions(
  BuildContext context, {
  required Message m,
  required String partner,
}) => showOverlayPage<MessageAction>(
  context,
  (_) => MessageActions(message: m, partner: partner),
);

class MessageActions extends StatelessWidget {
  const MessageActions({
    super.key,
    required this.message,
    required this.partner,
  });

  final Message message;
  final String partner;

  /// Photos, videos and GIFs/memes can be saved to the phone; stickers
  /// stay in August (they're kept with Long-press › Keep in the tray).
  bool get _media => switch (message.body) {
    PhotoBody() || VideoBody() || RoundVideoBody() || MemeBody() => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    void pick(MessageAction a) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop(a);
    }

    final m = message;
    final info = [
      'Sent ${hhmm(m.at)}',
      if (m.fromMe && m.delivery.index >= Delivery.delivered.index)
        'Delivered ${hhmm(m.deliveredAt ?? m.at)}',
      if (m.fromMe && m.delivery == Delivery.seen)
        'Seen ${hhmm(m.seenAt ?? m.at)}',
    ].join(' · ');

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: ColoredBox(color: VPalette.of(context).popupScrim),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 120, 14, 0),
            child: Column(
              crossAxisAlignment: m.fromMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                VGlass(
                  radius: 999,
                  tint: VPalette.of(context).glassSheet,
                  blur: 14,
                  border: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in quickReactions)
                          Semantics(
                            button: true,
                            label: 'React $e',
                            child: VTappable(
                              onTap: () => pick(ReactAction(e)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        Semantics(
                          button: true,
                          label: 'More reactions',
                          child: VTappable(
                            onTap: () => pick(const ReactAction('🫶')),
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: VInk.of(context).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const VIconView(VIcon.plus, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                IgnorePointer(
                  child: MessageView(message: m, partner: partner),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VGlass(
            radius: 28,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            tint: VPalette.of(context).glassSheet,
            blur: 14,
            border: false,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: _Handle()),
                    const SizedBox(height: 12),
                    // When it was sent, delivered and seen: a quiet line.
                    Text(
                      info,
                      textAlign: TextAlign.center,
                      style: VText.secondary.copyWith(
                        color: VInk.of(context).withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Group(
                      rows: [
                        _Row(
                          VIcon.reply,
                          'Reply',
                          () => pick(const ReplyAction()),
                        ),
                        if (m.body is TextBody)
                          _Row(
                            VIcon.copy,
                            'Copy',
                            () => pick(const CopyAction()),
                          ),
                        if (_media)
                          _Row(
                            VIcon.download,
                            'Save media',
                            () => pick(const SaveAction()),
                          ),
                        _Row(
                          VIcon.trash,
                          'Delete for me',
                          () => pick(const DeleteAction()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: VInk.of(context).withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// The actions in one soft card, with faint dividers from the text on.
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: SizedBox(
                  height: 0.5,
                  width: double.infinity,
                  child: ColoredBox(color: ink.withValues(alpha: 0.14)),
                ),
              ),
            r,
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.onTap);

  final VIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: VTappable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          child: Row(
            children: [
              VIconView(icon, size: 20, color: ink.withValues(alpha: 0.75)),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: VText.rowTitle)),
            ],
          ),
        ),
      ),
    );
  }
}
