import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../platform/data_home.dart';
import '../common/choice_sheet.dart';

/// Dev flavor only: before August can open its data in the phone's own
/// storage, Android has to allow "All files access" (again after every
/// reinstall). Comes back by itself once it's on.
class DevStorageGate extends StatefulWidget {
  const DevStorageGate({super.key, required this.onAllowed});

  final Future<void> Function() onAllowed;

  @override
  State<DevStorageGate> createState() => _DevStorageGateState();
}

class _DevStorageGateState extends State<DevStorageGate> {
  late final AppLifecycleListener _life;
  var _done = false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _check);
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_done || !await Profiles.allowed()) return;
    _done = true;
    await widget.onAllowed();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: VColors.black,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'AUGUST DEV',
                  style: VText.eyebrow.copyWith(color: VColors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  'Allow all files access',
                  style: VText.inter(
                    26,
                    weight: 600,
                  ).copyWith(color: VColors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  'This dev build keeps chats, pairing and profiles in '
                  '${DataHome.devRoot} on this phone, so a reinstall '
                  'loses nothing. Android asks again after every reinstall.',
                  style: VText.inter(
                    15,
                    weight: 300,
                    height: 1.4,
                  ).copyWith(color: VColors.white),
                ),
                const Spacer(),
                CupertinoButton.filled(
                  onPressed: () => unawaited(Profiles.ask()),
                  child: const Text('Open settings'),
                ),
                const SizedBox(height: 12),
                CupertinoButton(
                  onPressed: _check,
                  child: const Text(
                    "I've allowed it",
                    style: TextStyle(color: VColors.white),
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

/// Dev flavor only: one phone, several profiles, each with its own folder,
/// identity, account and pairing, so it can pair with more than one person.
/// Switching restarts August into the other profile.
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  late Future<(List<Profile>, String)> _load = _read();

  Future<(List<Profile>, String)> _read() async =>
      (await Profiles.all(), await Profiles.current());

  Future<void> _tap(Profile p, {required bool current}) async {
    if (current) return;
    final what = await showChoiceSheet<String>(
      context,
      title: p.name,
      choices: [
        Choice('use', 'Switch to ${p.name}'),
        Choice('delete', 'Delete ${p.name}'),
      ],
    );
    if (!mounted) return;
    switch (what) {
      case 'use':
        await Profiles.use(p.id);
      case 'delete':
        final sure = await showChoiceSheet<bool>(
          context,
          title: 'Delete ${p.name}?',
          choices: const [
            Choice(true, 'Delete its chat, pairing and identity'),
            Choice(false, 'Keep it'),
          ],
        );
        if (sure != true) return;
        await Profiles.delete(p.id);
        setState(() {
          _load = _read();
        });
    }
  }

  Future<void> _new() async {
    final c = TextEditingController();
    final name = await showVSheet<String>(
      context,
      title: 'New profile',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VTextField(
            controller: c,
            autofocus: true,
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: 14),
          VButton.primary(
            'Make it and switch',
            onPressed: () => Navigator.of(context).pop(c.text),
          ),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    final p = await Profiles.create(name);
    await Profiles.use(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return VDetailPage(
      backLabel: 'Back',
      title: 'Profiles',
      children: [
        FutureBuilder(
          future: _load,
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) return const SizedBox(height: 60);
            final (all, now) = data;
            return VListGroup(
              label: 'On this phone',
              note:
                  'Each profile is its own August: its own account, '
                  'identity, pairing and chat, in '
                  '${DataHome.devRoot}/profiles. Switching restarts August.',
              children: [
                for (final p in all)
                  VListRow(
                    title: p.name,
                    subtitle: p.partner == null
                        ? 'Not paired'
                        : 'Paired with ${p.partner}',
                    value: p.id == now ? 'Current' : null,
                    chevron: p.id != now,
                    onTap: () => _tap(p, current: p.id == now),
                  ),
                VListRow(title: 'New profile', onTap: _new),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// "Profile · Main" in Settings and on Welcome: the current one's name.
class CurrentProfileName extends StatelessWidget {
  const CurrentProfileName({super.key, required this.builder});

  final Widget Function(BuildContext context, String name) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: () async {
        final now = await Profiles.current();
        return (await Profiles.all())
            .firstWhere(
              (p) => p.id == now,
              orElse: () => Profile(id: now, name: now),
            )
            .name;
      }(),
      builder: (context, snap) => builder(context, snap.data ?? '…'),
    );
  }
}
