import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/action_group.dart';
import '../common/overlay.dart';
import '../common/reaction_bar.dart';
import '../common/sticker_view.dart';
import '../common/toast.dart';

/// What a [showStickerMenu] hands back for its caller to do; the library
/// changes (keep, favourite, remove) it makes itself.
enum StickerPick {
  /// Chat: reply to the sticker's message.
  reply,

  /// Chat: delete the sticker's message on this phone.
  delete,

  /// Tray: take it off Recent.
  forget,
}

/// The sticker long-press menu, wherever a sticker is: the tray (a pack,
/// Recent, WhatsApp) and the chat (yours and theirs). A big look at the
/// sticker, where it's from, and what fits:
///
/// - Add to favourites (keeping it, in the hidden "Saved" pack, if it's
///   from elsewhere) or Remove from favourites (which lets go of one from
///   elsewhere; one you made stays in its pack);
/// - one of your packs' (Ours): Delete sticker;
/// - [recent]: Remove from recent; [chat]: Reply and Delete for me.
///
/// In the chat, [onReact] puts the quick reactions over the sheet, as on
/// any message; picking one closes the menu.
Future<StickerPick?> showStickerMenu(
  BuildContext context,
  Sticker sticker, {
  required String from,
  bool recent = false,
  bool chat = false,
  ValueChanged<String>? onReact,
}) {
  HapticFeedback.mediumImpact();
  return showOverlayPage<StickerPick>(
    context,
    (_) => _StickerMenu(
      sticker: sticker,
      from: from,
      recent: recent,
      chat: chat,
      onReact: onReact,
    ),
  );
}

class _StickerMenu extends ConsumerWidget {
  const _StickerMenu({
    required this.sticker,
    required this.from,
    required this.recent,
    required this.chat,
    this.onReact,
  });

  final Sticker sticker;

  /// "From Shruti", "From WhatsApp", "Yours"…
  final String from;
  final bool recent;
  final bool chat;
  final ValueChanged<String>? onReact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = VInk.of(context);
    final packs = ref.watch(stickersProvider);
    final pack = packs
        .where((p) => p.stickers.any((s) => s.id == sticker.id))
        .firstOrNull;
    // The library's own copy (it carries the favourite), if it's in one.
    final owned = pack?.stickers.firstWhere((s) => s.id == sticker.id);
    final n = ref.read(stickersProvider.notifier);
    // Favourites from elsewhere go in "Saved" when there is one (Neon),
    // else "Ours", else the first pack.
    String? into() => packs.any((p) => p.id == 'saved')
        ? 'saved'
        : packs.any((p) => p.id == 'ours')
        ? 'ours'
        : packs.firstOrNull?.id;

    void done(String? toast, [StickerPick? pick]) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop(pick);
      if (toast != null) showToast(context, toast);
    }

    // "Saved" is where favourites from elsewhere live; it isn't shown as a
    // pack, so a sticker there that isn't a favourite is as good as unkept.
    final hidden = pack?.id == 'saved';
    final starred = owned?.favourite ?? false;
    final status = starred
        ? (hidden
              ? 'In your favourites'
              : 'In your favourites · "${pack!.name}"')
        : owned == null || hidden
        ? 'Not in your favourites'
        : 'In "${pack!.name}"';

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ColoredBox(color: VPalette.of(context).popupScrim),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // React to it, as to any message: the row just over the sheet.
              if (onReact case final react?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ReactionBar(
                    onPick: (e) {
                      Navigator.of(context).pop();
                      react(e);
                    },
                  ),
                ),
              VGlass(
                radius: 28,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
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
                        const SizedBox(height: 18),
                        Center(
                          child: StickerView(sticker, size: 132, tilt: -4),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          from,
                          textAlign: TextAlign.center,
                          style: VText.inter(15, weight: 600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: VText.secondary.copyWith(
                            color: ink.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ActionGroup(
                          rows: [
                            if (!starred)
                              ActionRow(VIcon.star, 'Add to favourites', () {
                                if (owned != null) {
                                  n.toggleFavourite(owned.id);
                                } else {
                                  // Kept (in the hidden "Saved"), as a favourite.
                                  final p = into();
                                  if (p == null) return;
                                  n.add(p, sticker.withFavourite(true));
                                }
                                done('In your favourites');
                              })
                            else
                              ActionRow(VIcon.star, 'Remove from favourites', () {
                                // One you made keeps its place in its pack; one
                                // from elsewhere goes (it was only a favourite).
                                hidden
                                    ? n.remove(owned!.id)
                                    : n.toggleFavourite(owned!.id);
                                done('Not in your favourites');
                              }),
                            if (owned != null && !hidden)
                              ActionRow(VIcon.trash, 'Delete sticker', () {
                                n.remove(owned.id);
                                done('Sticker deleted');
                              }),
                            if (recent)
                              ActionRow(
                                VIcon.close,
                                'Remove from recent',
                                () => done(null, StickerPick.forget),
                              ),
                            if (chat) ...[
                              ActionRow(
                                VIcon.reply,
                                'Reply',
                                () => done(null, StickerPick.reply),
                              ),
                              ActionRow(
                                VIcon.trash,
                                'Delete for me',
                                () => done(null, StickerPick.delete),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
