import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_palette.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';

/// The six quick reactions (B3).
const quickReactions = ['❤️', '😂', '🥺', '😮', '🔥', '👍'];

/// The row of quick reactions over a long-pressed message (or sticker): a
/// glass pill of emoji, and "+" for one more.
class ReactionBar extends StatelessWidget {
  const ReactionBar({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    void pick(String e) {
      HapticFeedback.selectionClick();
      onPick(e);
    }

    return VGlass(
      radius: 999,
      tint: VPalette.of(context).glassSheet,
      blur: 14,
      border: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in quickReactions)
              Semantics(
                button: true,
                label: 'React $e',
                child: VTappable(
                  onTap: () => pick(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'More reactions',
              child: VTappable(
                onTap: () => pick('🫶'),
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
    );
  }
}
