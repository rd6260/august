import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/version.dart';
import 'core/theme/v_colors.dart';
import 'features/crash_overlay.dart';
import 'net/config.dart';
import 'data/providers.dart';
import 'net/background_check.dart';
import 'net/neon_backend.dart';
import 'net/neon_calls.dart';
import 'net/phone_media.dart';
import 'net/phone_round.dart';
import 'net/phone_songs.dart';
import 'net/phone_storage.dart';
import 'net/web_memes.dart';
import 'net/phone_voice.dart';
import 'net/push.dart';
import 'net/updater.dart';
import 'features/dev/dev_pages.dart';
import 'platform/crash_log.dart';
import 'platform/data_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Linux desktop build (a second August on a laptop) plays audio
  // through libmpv.
  final android = Platform.isAndroid;
  if (Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized(linux: true);
    VideoPlayerMediaKit.ensureInitialized(linux: true);
  }
  // First, so errors from here on are logged and shown, not lost.
  CrashLog.instance
    ..appVersion = augustVersion
    ..install();
  ErrorWidget.builder = quietErrorWidget;

  // Edge to edge: the wallpaper runs under the status and navigation bars.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: VColors.transparent,
      systemNavigationBarColor: VColors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  LicenseRegistry.addLicense(() async* {
    for (final font in ['Doto', 'Inter']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$font.txt');
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });

  // The dev flavor keeps everything in the phone's own storage, which
  // needs "All files access" first (again after every reinstall).
  if (isDev && android && !await Profiles.allowed()) {
    runApp(const DevStorageGate(onAllowed: _start));
    return;
  }
  await _start();
}

/// Opens this run's data (the current profile's, in dev) and starts August.
Future<void> _start() async {
  final android = Platform.isAndroid;
  // The first dev run carries a prod install's chat into "main".
  if (isDev && android) await Profiles.moveInPrivateData();

  // On Neon when the build has a backend (env.json); the mock partner
  // otherwise.
  final config = NeonConfig.fromEnvironment;
  final backend = config == null
      ? null
      : await NeonBackend.open(
          config,
          vault: await DataHome.vault(),
          dir: await DataHome.dir(),
        );
  final songs = backend == null ? null : YouTubeSongs();
  // August's own cache folder: on Linux the "temporary directory" is the
  // whole of /tmp, which Storage must never measure or clear.
  final cache = backend == null ? null : await getApplicationCacheDirectory();
  if (backend != null) {
    backend
      ..media = PhoneMedia(backend.mediaDir)
      ..voice = PhoneVoice(backend.mediaDir)
      ..calls = NeonCalls(backend)
      // The background check is an Android foreground service.
      ..startChecking = android ? BackgroundCheck.start : null
      ..stopChecking = android ? BackgroundCheck.stop : null
      ..notifyAway = (data) async {
        final n = await Push.describe(
          data,
          vault: backend.vault,
          store: backend.store,
        );
        if (n != null) {
          await Push.show(
            n,
            id: n.moment ? 2 : 1,
            key: data['id'] as String?,
            store: backend.store,
          );
        }
      }
      ..askNotifications = Push.ask
      ..pushToken = Push.token;
    if (android) BackgroundCheck.init();
    try {
      await Push.init(onWake: () => backend.wake?.call());
      // Paired but not allowed to notify (a reinstall drops the permission,
      // and onboarding, which asks, is behind us): ask again. Android shows
      // its prompt until it's allowed or turned down for good.
      if (android && backend.store.paired && !await Push.allowed()) {
        unawaited(Push.ask());
      }
    } on Object catch (e) {
      // Without Firebase, August still polls; it just can't be woken.
      CrashLog.instance.add('push off: $e');
    }
  }
  runApp(
    ProviderScope(
      overrides: [
        ...?backend?.overrides(),
        if (backend != null) ...[
          backgroundCheckProvider.overrideWith(
            (ref) => BackgroundCheck.lastCheck(),
          ),
          // Songs come from YouTube (search, and the 15 s clips).
          musicRepositoryProvider.overrideWithValue(songs!),
          songPlayerProvider.overrideWithValue(songs),
          // Memes from Reddit (and KLIPY with a key).
          memeRepositoryProvider.overrideWithValue(WebMemes()),
          notificationsAllowedProvider.overrideWith((ref) => Push.allowed()),
          notificationSettingsProvider.overrideWithValue(Push.openSettings),
          clearNotificationsProvider.overrideWithValue(Push.clear),
          keepCheckingProvider.overrideWithValue(
            () => BackgroundCheck.keepGoing(paired: backend.store.paired),
          ),
          // Over-the-air updates from GitHub Releases (Android, prod only:
          // a release would replace a dev build with one that can't see
          // its data).
          if (android && !isDev)
            updateDepsProvider.overrideWithValue(phoneUpdateDeps()),
          // Round videos need the phone's camera plugin (Android only).
          if (android)
            roundCameraProvider.overrideWithValue(PhoneRound(backend.mediaDir)),
          storageRepositoryProvider.overrideWithValue(
            PhoneStorage(backend.store, backend.mediaDir, cache!),
          ),
        ],
      ],
      child: const AugustApp(splash: true),
    ),
  );
  // A crash on the Android side last time is shown once, now.
  unawaited(CrashLog.instance.checkLastRun());
}
