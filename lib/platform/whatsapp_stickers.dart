import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import 'data_home.dart';

/// The stickers WhatsApp keeps on this phone (`WhatsApp Stickers`, under
/// Android/media), shown live in the tray's WhatsApp tab. Android lets
/// August read that folder only after it's picked once in the folder picker
/// (`WhatsAppStickers.kt` keeps the access).
abstract final class WhatsAppStickers {
  static const _channel = MethodChannel('august/whatsapp');

  /// Android only: WhatsApp's folder isn't on other platforms.
  static bool get supported => debugSupported ?? Platform.isAndroid;

  /// Shows the WhatsApp tab off Android (tests and previews).
  @visibleForTesting
  static bool? debugSupported;

  /// Whether the folder has been picked (and Android still allows it).
  static Future<bool> hasFolder() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasFolder') ?? false;
    } on Object {
      return false;
    }
  }

  /// Opens the folder picker at WhatsApp's sticker folder. True when one was
  /// picked.
  static Future<bool> pickFolder() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('pickFolder') ?? false;
    } on Object {
      return false;
    }
  }

  /// The newest stickers, as files in August's cache, newest first.
  static Future<List<File>> list({int max = 300}) async {
    if (!supported) return const [];
    final cache = Directory(
      '${(await getApplicationCacheDirectory()).path}/whatsapp',
    );
    final found = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'list',
      {'cache': cache.path, 'max': max},
    );
    return [
      for (final f in found ?? const <Map<Object?, Object?>>[])
        File(f['path']! as String),
    ];
  }

  /// A sticker to send or keep, from WhatsApp's [file]: copied into August's
  /// own stickers (the cache can be cleared), as a cut-out so it's drawn in
  /// its own shape, transparent edges and all.
  static Future<Sticker> sticker(File file) async {
    final dir = Directory('${(await DataHome.dir()).path}/stickers');
    await dir.create(recursive: true);
    final name = file.uri.pathSegments.last.replaceAll(
      RegExp('[^A-Za-z0-9._-]'),
      '_',
    );
    final id = 'cut-wa-$name';
    final kept = File('${dir.path}/$id');
    if (!kept.existsSync()) await file.copy(kept.path);
    return Sticker.photo(id: id, art: 0, path: kept.path);
  }
}
