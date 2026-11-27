import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_ink.dart';

/// The clean menus' card (a message's long-press, a sticker's): the
/// actions in one soft card, with faint dividers from the text on.
class ActionGroup extends StatelessWidget {
  const ActionGroup({super.key, required this.rows});

  final List<ActionRow> rows;

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
                padding: EdgeInsets.only(left: r.icon == null ? 16 : 52),
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

/// One action in an [ActionGroup]: a muted icon and a label.
class ActionRow extends StatelessWidget {
  const ActionRow(
    this.icon,
    this.label,
    this.onTap, {
    super.key,
    this.sub,
    this.trailing,
    this.selected = false,
  });

  /// None for a plain list of options.
  final VIcon? icon;
  final String label;
  final VoidCallback onTap;
  final String? sub;
  final Widget? trailing;

  /// The current choice: a check on the right.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      excludeSemantics: true,
      child: VTappable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          child: Row(
            children: [
              if (icon != null) ...[
                VIconView(icon!, size: 20, color: ink.withValues(alpha: 0.75)),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: selected
                          ? VText.inter(15, weight: 600)
                          : VText.rowTitle,
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub!,
                        style: VText.secondary.copyWith(
                          color: ink.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (selected) ...[
                const SizedBox(width: 10),
                const VIconView(VIcon.check, size: 20, strokeWidth: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
