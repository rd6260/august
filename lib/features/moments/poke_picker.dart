import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../data/providers.dart';
import '../common/overlay.dart';

/// Opens the poke picker under the header's poke button (C24) and returns
/// the moment picked.
Future<VMoment?> showPokePicker(
  BuildContext context, {
  required String partner,
}) => showOverlayPage<VMoment>(context, (_) => PokePicker(partner: partner));

class PokePicker extends ConsumerStatefulWidget {
  const PokePicker({super.key, required this.partner});

  final String partner;

  @override
  ConsumerState<PokePicker> createState() => _PokePickerState();
}

class _PokePickerState extends ConsumerState<PokePicker> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Count the cooldowns down while the picker is open.
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(momentCooldownProvider);
    final cd = ref.read(momentCooldownProvider.notifier);
    final ink = VInk.of(context);
    Widget tile(VMoment m) => _Tile(
      moment: m,
      wait: cd.left(m),
      onTap: () {
        if (cd.left(m) > Duration.zero) {
          HapticFeedback.heavyImpact();
          return;
        }
        Navigator.of(context).pop(m);
      },
    );
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ColoredBox(color: VPalette.of(context).popupScrim),
          ),
        ),
        Positioned(
          right: 14,
          top: top + 66,
          width: 312,
          // Grows out of the poke button, top right.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (context, k, child) => Transform.scale(
              scale: k,
              alignment: Alignment.topRight,
              child: child,
            ),
            child: VGlass(
              radius: 28,
              tint: VPalette.of(context).glassSheet,
              blur: 14,
              border: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Send ${widget.partner} a…',
                        style: VText.inter(16, weight: 600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      padding: EdgeInsets.zero, // not the status bar's inset
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.92,
                      children: [for (final m in VMoment.values) tile(m)],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'One of each every 10 seconds, so they stay special.',
                        style: VText.inter(12)
                            .copyWith(color: ink.withValues(alpha: 0.55)),
                      ),
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

/// A moment to send: a soft wash of its colour, the emoji and its name.
/// Recharging, the emoji fades, the seconds show, and a bar along the
/// bottom fills back up.
class _Tile extends StatelessWidget {
  const _Tile({required this.moment, required this.wait, required this.onTap});

  final VMoment moment;
  final Duration wait;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final cooling = wait > Duration.zero;
    final total = MomentCooldown.cooldown.inMilliseconds;
    final back = 1 - (wait.inMilliseconds / total).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: cooling
          ? '${moment.label}, ready in ${wait.inSeconds + 1} seconds'
          : 'Send a ${moment.label}',
      child: VTappable(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: moment.color.withValues(alpha: cooling ? 0.1 : 0.24),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedOpacity(
                        opacity: cooling ? 0.35 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          moment.emoji,
                          style: const TextStyle(fontSize: 34, height: 1),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cooling ? '${wait.inSeconds + 1} s' : moment.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cooling
                            ? VText.doto(13)
                                  .copyWith(color: ink.withValues(alpha: 0.6))
                            : VText.inter(12, weight: 600),
                      ),
                    ],
                  ),
                ),
                if (cooling)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 3,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: back,
                      child: ColoredBox(color: moment.color),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
