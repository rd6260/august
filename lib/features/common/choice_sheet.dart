import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/widgets/v_glass.dart';
import 'action_group.dart';

/// One row of a [showChoiceSheet].
class Choice<T> {
  const Choice(this.value, this.label, {this.icon, this.sub});

  final T value;
  final String label;
  final VIcon? icon;
  final String? sub;
}

/// A sheet of options to pick from, in the clean look: one soft card, a
/// muted icon each, and a check on the current one ([selected]).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
  T? selected,
}) {
  return showVSheet<T>(
    context,
    title: title,
    builder: (context) => ActionGroup(
      rows: [
        for (final c in choices)
          ActionRow(
            c.icon,
            c.label,
            () => Navigator.of(context).pop(c.value),
            sub: c.sub,
            selected: selected != null && c.value == selected,
          ),
      ],
    ),
  );
}
