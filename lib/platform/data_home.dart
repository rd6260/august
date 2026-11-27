import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../net/vault.dart';

/// The dev flavor on Android (`flutter run --flavor dev`): data lives in the
/// phone's own storage and comes in profiles. Prod builds and other
/// platforms (Linux, even with --flavor dev) keep August's private folder.
final bool isDev = appFlavor == 'dev' && Platform.isAndroid;

/// Where August keeps its things, for the app and its background isolates
/// (push, the background check, the widget) alike.
///
/// Prod: the app's private folder, secrets in the Keystore. Dev: the phone's
/// own storage at [devRoot], one folder per profile with a plain `vault.json`
/// beside the data, so an uninstall (a debug-key build, say) loses nothing:
/// the next install finds the same identity, pairing and history. The files
/// can be read by any app with storage access; that's fine for dev only.
abstract final class DataHome {
  /// The top of the phone's own storage (what Files shows as "Internal
  /// storage"), then August.
  static const devRoot = '/storage/emulated/0/August';

  /// [devRoot], or a temporary folder in tests.
  @visibleForTesting
  static String root = devRoot;

  static Directory get _profiles => Directory('$root/profiles');

  /// This run's folder: the current profile's in dev.
  static Future<Directory> dir() async {
    if (!isDev) return getApplicationSupportDirectory();
    final d = Directory('${_profiles.path}/${await Profiles.current()}');
    await d.create(recursive: true);
    return d;
  }

  /// This run's secrets.
  static Future<Vault> vault() async {
    if (isDev) return FileVault('${(await dir()).path}/vault.json');
    if (Platform.isAndroid) return const SecureVault();
    return FileVault(
      '${(await getApplicationSupportDirectory()).path}/vault.json',
    );
  }
}

/// A dev profile: its own folder, identity, account and pairing.
class Profile {
  const Profile({required this.id, required this.name, this.partner});

  final String id;
  final String name;

  /// Who it's paired with, or null.
  final String? partner;
}

/// The dev flavor's profiles, so one phone can pair with several people
/// (for testing). Each is a folder under `August/profiles/`; `current.json`
/// says which one this run uses. Switching restarts August.
abstract final class Profiles {
  static const _channel = MethodChannel('august/dev');
  static File get _current => File('${DataHome.root}/current.json');

  static Future<String> current() async {
    try {
      final j = jsonDecode(await _current.readAsString()) as Map;
      final id = j['profile'];
      if (id is String && id.isNotEmpty) return id;
    } on Object {
      // None yet: the first profile.
    }
    return 'main';
  }

  static Future<List<Profile>> all() async {
    final now = await current();
    final dirs = DataHome._profiles.existsSync()
        ? DataHome._profiles.listSync().whereType<Directory>().toList()
        : <Directory>[];
    final out = [
      for (final d in dirs)
        await _read(d.uri.pathSegments.lastWhere((s) => s.isNotEmpty)),
    ];
    if (!out.any((p) => p.id == now)) out.add(await _read(now));
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Future<Profile> _read(String id) async {
    final dir = '${DataHome._profiles.path}/$id';
    var name = id == 'main' ? 'Main' : id;
    String? partner;
    try {
      final j = jsonDecode(await File('$dir/profile.json').readAsString());
      name = (j as Map)['name'] as String? ?? name;
    } on Object {
      // Unnamed.
    }
    try {
      final j = jsonDecode(await File('$dir/moose.json').readAsString());
      final p = (j as Map)['partner'];
      if (p is Map) partner = p['name'] as String?;
    } on Object {
      // Not set up yet.
    }
    return Profile(id: id, name: name, partner: partner);
  }

  /// A new, empty profile named [name] (it starts at Welcome).
  static Future<Profile> create(String name) async {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final id =
        '${slug.isEmpty ? 'profile' : slug}-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final dir = Directory('${DataHome._profiles.path}/$id');
    await dir.create(recursive: true);
    await File('${dir.path}/profile.json')
        .writeAsString(jsonEncode({'name': name.trim()}));
    return Profile(id: id, name: name.trim());
  }

  /// Deletes profile [id]'s folder (never the current one). Its server
  /// account stays; it's only test data.
  static Future<void> delete(String id) async {
    if (id == await current()) return;
    final dir = Directory('${DataHome._profiles.path}/$id');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Makes [id] the profile and restarts August into it.
  static Future<void> use(String id) async {
    await _current.parent.create(recursive: true);
    await _current.writeAsString(jsonEncode({'profile': id}), flush: true);
    await _channel.invokeMethod<void>('restart');
  }

  /// Whether August may use the phone's own storage ("All files access").
  static Future<bool> allowed() async {
    try {
      return await _channel.invokeMethod<bool>('allowed') ?? false;
    } on Object {
      return false;
    }
  }

  /// Opens Android's page to allow it.
  static Future<void> ask() => _channel.invokeMethod<void>('ask');

  /// The first dev run on a phone that had a prod install: moves that
  /// install's data and secrets into the "main" profile, so the chat and
  /// the pairing carry on. Only when [DataHome.devRoot] has no profiles yet,
  /// and only possible if the dev build was installed over prod without an
  /// uninstall (signed with the release key).
  static Future<void> moveInPrivateData() async {
    final profiles = DataHome._profiles;
    if (profiles.existsSync() && profiles.listSync().isNotEmpty) return;
    final from = await getApplicationSupportDirectory();
    final to = Directory('${DataHome._profiles.path}/main');
    await to.create(recursive: true);
    await File('${to.path}/profile.json')
        .writeAsString(jsonEncode({'name': 'Main'}));
    if (!File('${from.path}/moose.json').existsSync()) return;
    await _copy(from, to);
    // Stored media paths point into the old folder; point them here.
    final store = File('${to.path}/moose.json');
    final text = await store.readAsString();
    await store.writeAsString(text.replaceAll(from.path, to.path), flush: true);
    final vault = FileVault('${to.path}/vault.json');
    for (final key in vaultKeys) {
      final v = await const SecureVault().read(key);
      if (v != null) await vault.write(key, v);
    }
  }

  static Future<void> _copy(Directory from, Directory to) async {
    await for (final e in from.list(followLinks: false)) {
      final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      // Downloaded updates and Flutter's own engine files stay behind.
      if (name == 'updates' || name == 'flutter_assets') continue;
      if (e is Directory) {
        final sub = Directory('${to.path}/$name');
        await sub.create(recursive: true);
        await _copy(e, sub);
      } else if (e is File) {
        await e.copy('${to.path}/$name');
      }
    }
  }
}
