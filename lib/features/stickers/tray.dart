import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../net/web_memes.dart';
import '../common/art.dart';
import '../common/dot_loader.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import '../../platform/whatsapp_stickers.dart';
import '../common/sticker_view.dart';
import 'sticker_maker.dart';
import 'sticker_menu.dart';

enum TrayTab { stickers, gifs, memes }

/// The sticker, GIF and meme tray (S1, C26), from the composer's sticker
/// button. Returns what to send.
Future<Body?> showTray(
  BuildContext context, {
  TrayTab start = TrayTab.stickers,
}) => showOverlayPage<Body>(context, (_) => Tray(start: start));

class Tray extends ConsumerStatefulWidget {
  const Tray({super.key, this.start = TrayTab.stickers});

  final TrayTab start;

  @override
  ConsumerState<Tray> createState() => _TrayState();
}

class _TrayState extends ConsumerState<Tray> {
  late var _tab = widget.start;

  @override
  Widget build(BuildContext context) {
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
          left: 0,
          right: 0,
          bottom: 0,
          top: top + 70,
          child: VGlass(
            radius: 28,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            tint: VPalette.of(context).glassSheet,
            blur: 14,
            border: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: VInk.of(context).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  VSegmented<TrayTab>(
                    quiet: true,
                    segments: const {
                      TrayTab.stickers: 'Stickers',
                      TrayTab.gifs: 'GIFs',
                      TrayTab.memes: 'Memes',
                    },
                    value: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _tab == TrayTab.stickers
                        ? const _Stickers()
                        : _Memes(
                            key: ValueKey(_tab),
                            kind: _tab == TrayTab.gifs
                                ? MemeKind.gif
                                : MemeKind.meme,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A search field in an outlined pill (A6).
class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.controller,
    required this.placeholder,
    this.onChanged,
    this.autofocus = false,
    this.quiet = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  /// The clean look (the sticker tray): a soft fill, no outline, a muted
  /// placeholder.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final row = Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: VIconView(
            VIcon.search,
            size: 18,
            color: quiet ? ink.withValues(alpha: 0.6) : null,
          ),
        ),
        Expanded(
          child: CupertinoTextField(
            controller: controller,
            autofocus: autofocus,
            onChanged: onChanged,
            placeholder: placeholder,
            placeholderStyle: VText.inter(15)
                .copyWith(color: quiet ? ink.withValues(alpha: 0.5) : ink),
            style: VText.inter(15).copyWith(color: ink),
            cursorColor: ink,
            padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
            decoration: const BoxDecoration(color: VColors.transparent),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, v, _) => v.text.isEmpty
              ? const SizedBox(width: 12)
              : Semantics(
                  button: true,
                  label: 'Clear',
                  child: VTappable(
                    onTap: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(6, 10, 16, 10),
                      child: VIconView(VIcon.close, size: 18),
                    ),
                  ),
                ),
        ),
      ],
    );
    if (quiet) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: row,
      );
    }
    return VOutlined(radius: 999, child: row);
  }
}

/// S1: your stickers, by pack.
class _Stickers extends ConsumerStatefulWidget {
  const _Stickers();

  @override
  ConsumerState<_Stickers> createState() => _StickersState();
}

class _StickersState extends ConsumerState<_Stickers> {
  final _search = TextEditingController();

  /// null = favourites, '' = recent, else a pack id.
  /// Favourites (null) when there are any, else Recent (''), so a new
  /// library never opens on an empty page.
  /// The WhatsApp tab is showing.
  var _whatsApp = false;

  late String? _pack =
      ref.read(stickersProvider).any((p) => p.stickers.any((s) => s.favourite))
      ? null
      : '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Sends [s], and puts it first in Recent.
  void _send(Sticker s) {
    ref.read(recentStickersProvider.notifier).used(s);
    Navigator.of(context).pop(StickerBody(s));
  }

  Future<void> _make() async {
    final made = await makeSticker(context, ref);
    if (made != null && mounted) _send(made);
  }

  Future<void> _hold(Sticker s) async {
    final recent = !_whatsApp && _pack == '';
    final pick = await showStickerMenu(
      context,
      s,
      from: _fromLabel(s),
      recent: recent,
    );
    if (pick == StickerPick.forget) {
      ref.read(recentStickersProvider.notifier).forget(s.id);
    }
  }

  /// Where [s] came from, for the menu's heading.
  String _fromLabel(Sticker s) {
    if (s.id.startsWith('cut-wa-')) return 'From WhatsApp';
    if (s.from == 'me') return 'Yours';
    return 'From ${ref.read(pairingProvider).partner.name}';
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final packs = ref.watch(stickersProvider);
    final all = [for (final p in packs) ...p.stickers];
    final List<Sticker> shown;
    final String label;
    final (String, String) empty;
    if (_whatsApp) {
      shown = const [];
      label = 'From WhatsApp';
      empty = ('', '');
    } else if (_pack == null) {
      shown = all.where((s) => s.favourite).toList();
      label = 'Favourites';
      empty = (
        'No favourites yet',
        'Long-press any sticker, here, in Recent, WhatsApp or the chat, '
            'and add it to favourites.',
      );
    } else if (_pack!.isEmpty) {
      shown = ref.watch(recentStickersProvider);
      label = 'Recent';
      empty = (
        'Nothing sent yet',
        'Stickers you send show up here, WhatsApp ones too.',
      );
    } else {
      final p = packs.firstWhere(
        (p) => p.id == _pack,
        orElse: () => packs.first,
      );
      shown = p.stickers;
      label = p.name;
      empty = ('No stickers yet', 'Make one from a photo or a doodle with +.');
    }
    void pick(String? pack) => setState(() {
      _whatsApp = false;
      _pack = pack;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchPill(
          controller: _search,
          placeholder: 'Search your stickers',
          quiet: true,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _PackTab(
                      selected: !_whatsApp && _pack == '',
                      label: 'Recent',
                      onTap: () => pick(''),
                      child: const VIconView(VIcon.pending, size: 20),
                    ),
                    _PackTab(
                      selected: !_whatsApp && _pack == null,
                      label: 'Favourites',
                      onTap: () => pick(null),
                      child: const VIconView(VIcon.star, size: 20),
                    ),
                    // "Saved" holds favourites from elsewhere: they show in
                    // Favourites, not as a pack of their own.
                    for (final p in packs.where((p) => p.id != 'saved'))
                      _PackTab(
                        selected: !_whatsApp && _pack == p.id,
                        label: 'Pack: ${p.name}',
                        onTap: () => pick(p.id),
                        child: p.stickers.isEmpty
                            ? Text(
                                p.name.isEmpty
                                    ? '?'
                                    : p.name.characters.first.toUpperCase(),
                                style: VText.inter(15, weight: 600),
                              )
                            : StickerView(
                                p.stickers.first,
                                size: 26,
                                border: 2,
                                shadow: false,
                              ),
                      ),
                    _PackTab(
                      selected: false,
                      label: 'Make a sticker',
                      onTap: _make,
                      child: const VIconView(VIcon.plus, size: 20),
                    ),
                  ],
                ),
              ),
              // WhatsApp's own stickers, on the right, outside the scroll.
              if (WhatsAppStickers.supported) ...[
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  selected: _whatsApp,
                  label: 'Stickers from WhatsApp',
                  child: VTappable(
                    onTap: () => setState(() => _whatsApp = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _whatsApp ? ink : ink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'WhatsApp',
                        style: VText.inter(13, weight: 600).copyWith(
                          color: _whatsApp ? VColors.onColor(ink) : ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            label.toUpperCase(),
            style: VText.eyebrow.copyWith(color: ink.withValues(alpha: 0.55)),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _whatsApp
              ? _WhatsApp(onSend: _send)
              : shown.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: EmptyCard(
                    quiet: true,
                    title: empty.$1,
                    body: empty.$2,
                  ),
                )
              : GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  padding: const EdgeInsets.only(bottom: 30),
                  children: [
                    for (final (i, s) in shown.indexed)
                      Semantics(
                        button: true,
                        label: 'Sticker',
                        child: GestureDetector(
                          onLongPress: () => _hold(s),
                          child: VTappable(
                            onTap: () => _send(s),
                            child: Center(
                              child: StickerView(
                                s,
                                size: 70,
                                tilt: ((i * 17) % 14) - 7.0,
                                border: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 8,
            top: 4,
          ),
          child: Text(
            _whatsApp
                ? 'Tap to send · long-press to add it to favourites'
                : 'Long-press a sticker for favourites',
            style: VText.secondary.copyWith(color: ink.withValues(alpha: 0.5)),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// The WhatsApp tab: the stickers WhatsApp keeps on this phone, newest
/// first, read live from its folder (picked once).
class _WhatsApp extends ConsumerStatefulWidget {
  const _WhatsApp({required this.onSend});

  final void Function(Sticker s) onSend;

  @override
  ConsumerState<_WhatsApp> createState() => _WhatsAppState();
}

class _WhatsAppState extends ConsumerState<_WhatsApp> {
  late Future<List<File>?> _load = _read();

  /// null when the folder hasn't been picked yet.
  Future<List<File>?> _read() async {
    if (!await WhatsAppStickers.hasFolder()) return null;
    return WhatsAppStickers.list();
  }

  Future<void> _pick() async {
    if (await WhatsAppStickers.pickFolder()) {
      setState(() {
        _load = _read();
      });
    }
  }

  Future<void> _send(File f) async =>
      widget.onSend(await WhatsAppStickers.sticker(f));

  Future<void> _hold(File f) async {
    final s = await WhatsAppStickers.sticker(f);
    if (!mounted) return;
    await showStickerMenu(context, s, from: 'From WhatsApp');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: DotLoader());
        }
        if (snap.hasError) {
          return Align(
            alignment: Alignment.topCenter,
            child: EmptyCard(
              quiet: true,
              title: "Couldn't read WhatsApp's stickers",
              body: 'Pick its sticker folder again.',
              action: 'Choose folder',
              onAction: _pick,
            ),
          );
        }
        final files = snap.data;
        if (files == null) {
          return Align(
            alignment: Alignment.topCenter,
            child: EmptyCard(
              quiet: true,
              title: 'Your WhatsApp stickers',
              body:
                  'Android asks once which folder August may read. It opens '
                  'at WhatsApp Stickers: tap “Use this folder”, then Allow.',
              action: 'Choose folder',
              onAction: _pick,
            ),
          );
        }
        if (files.isEmpty) {
          return const Align(
            alignment: Alignment.topCenter,
            child: EmptyCard(
              quiet: true,
              title: 'No WhatsApp stickers yet',
              body: 'Stickers you send or get on WhatsApp show up here.',
            ),
          );
        }
        return GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            for (final f in files)
              Semantics(
                button: true,
                label: 'WhatsApp sticker',
                child: GestureDetector(
                  onLongPress: () => _hold(f),
                  child: VTappable(
                    onTap: () => _send(f),
                    child: Image.file(
                      f,
                      fit: BoxFit.contain,
                      cacheWidth: 210,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PackTab extends StatelessWidget {
  const _PackTab({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: VTappable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: selected ? 0.18 : 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// C26: GIFs and memes from KLIPY or Reddit, searchable.
class _Memes extends ConsumerStatefulWidget {
  const _Memes({super.key, required this.kind});

  final MemeKind kind;

  @override
  ConsumerState<_Memes> createState() => _MemesState();
}

class _MemesState extends ConsumerState<_Memes> {
  final _search = TextEditingController();
  // KLIPY first, as the canvas has it; Reddit when there's no KLIPY key.
  late var _source = ref.read(onNeonProvider) && !WebMemes.hasKlipy
      ? MemeSource.reddit
      : MemeSource.klipy;
  late MemeKind? _kind = widget.kind;
  var _query = '';
  Meme? _chosen;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(
      memeSearchProvider((query: _query, source: _source, kind: _kind)),
    );
    // With the keyboard up (searching), the send bar and the grid's end
    // ride above it; otherwise above the gesture bar.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = keyboard > 0
        ? keyboard
        : MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchPill(
              controller: _search,
              placeholder: 'Search memes',
              quiet: true,
              onChanged: (q) => setState(() => _query = q),
            ),
            const SizedBox(height: 12),
            // What kind, then where from (compact, on the right).
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final (k, label) in [
                          (null, 'Trending'),
                          (MemeKind.gif, 'GIFs'),
                          (MemeKind.sticker, 'Stickers'),
                          (MemeKind.meme, 'Memes'),
                          (MemeKind.clip, 'Clips'),
                        ])
                          _Chip(
                            label,
                            selected: _kind == k,
                            onTap: () => setState(() => _kind = k),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  VSegmented<MemeSource>(
                    quiet: true,
                    compact: true,
                    segments: const {
                      MemeSource.klipy: 'KLIPY',
                      MemeSource.reddit: 'Reddit',
                    },
                    value: _source,
                    onChanged: (s) => setState(() => _source = s),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.when(
                loading: () => const Center(child: DotLoader()),
                error: (_, _) => Align(
                  alignment: Alignment.topCenter,
                  child: _ErrorCard(
                    source: _source,
                    onRetry: () => ref.invalidate(memeSearchProvider),
                    onSwitch: () => setState(
                      () => _source = _source == MemeSource.klipy
                          ? MemeSource.reddit
                          : MemeSource.klipy,
                    ),
                  ),
                ),
                data: (memes) => memes.isEmpty
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: EmptyCard(
                          quiet: true,
                          title: 'Nothing for "$_query"',
                          body: 'Check the spelling, or try fewer words.',
                        ),
                      )
                    : _Masonry(
                        memes: memes,
                        chosen: _chosen,
                        bottom: bottom + 100,
                        onTap: (m) => setState(() => _chosen = m),
                      ),
              ),
            ),
          ],
        ),
        if (_chosen != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 14,
            child: VGlass(
              radius: 22,
              tint: VPalette.of(context).glassSheet,
              blur: 14,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    ArtBox(
                      art: _chosen!.art,
                      url: _chosen!.thumb ?? _chosen!.url,
                      width: 44,
                      height: 44,
                      radius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send this ${_chosen!.kind == MemeKind.gif ? 'GIF' : _chosen!.tag.toLowerCase()}?',
                            style: VText.inter(13, weight: 500),
                          ),
                          Text(
                            '${_chosen!.credit}${_chosen!.kind == MemeKind.gif ? ' · plays on loop' : ''}',
                            style: VText.secondary,
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Send',
                      child: VCircleButton(
                        icon: VIcon.send,
                        size: 44,
                        filled: true,
                        onTap: () =>
                            Navigator.of(context).pop(MemeBody(_chosen!)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Masonry extends StatelessWidget {
  const _Masonry({
    required this.memes,
    required this.chosen,
    required this.bottom,
    required this.onTap,
  });

  final List<Meme> memes;
  final Meme? chosen;
  final double bottom;
  final void Function(Meme m) onTap;

  @override
  Widget build(BuildContext context) {
    final left = <Meme>[], right = <Meme>[];
    var lh = 0.0, rh = 0.0;
    for (final m in memes) {
      if (lh <= rh) {
        left.add(m);
        lh += 1 / m.aspect;
      } else {
        right.add(m);
        rh += 1 / m.aspect;
      }
    }
    Widget column(List<Meme> ms) => Column(
      children: [
        for (final m in ms)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              button: true,
              selected: chosen == m,
              label: m.title,
              child: VTappable(
                onTap: () => onTap(m),
                child: Container(
                  decoration: chosen == m
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: VInk.of(context), width: 2),
                        )
                      : null,
                  padding: EdgeInsets.all(chosen == m ? 2 : 0),
                  child: AspectRatio(
                    aspectRatio: m.aspect,
                    child: ArtBox(
                      art: m.art,
                      url: m.thumb ?? m.url,
                      radius: BorderRadius.circular(14),
                      child: OnMedia(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: VOutlined(
                              radius: 5,
                              color: VColors.white,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                child: Text(
                                  m.tag,
                                  style: VText.inter(9, weight: 600),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: column(left)),
          const SizedBox(width: 8),
          Expanded(child: column(right)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.source,
    required this.onRetry,
    required this.onSwitch,
  });

  final MemeSource source;
  final VoidCallback onRetry;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final name = source == MemeSource.klipy ? 'KLIPY' : 'Reddit';
    final other = source == MemeSource.klipy ? 'Reddit' : 'KLIPY';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VInk.of(context).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InlineError("$name isn't answering"),
          const SizedBox(height: 6),
          Text('Try again, or switch to $other.', style: VText.secondary),
          const SizedBox(height: 10),
          Row(
            children: [
              VPill('Try again', fill: VFill.filled, onTap: onRetry),
              const SizedBox(width: 8),
              VPill(other, onTap: onSwitch),
            ],
          ),
        ],
      ),
    );
  }
}

/// A soft category chip: filled when chosen, a faint fill otherwise.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: VTappable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? ink : ink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: VText.inter(
                13,
                weight: selected ? 600 : 500,
              ).copyWith(color: selected ? VColors.onColor(ink) : ink),
            ),
          ),
        ),
      ),
    );
  }
}
