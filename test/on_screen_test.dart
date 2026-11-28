import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/platform/on_screen.dart';

/// "Is August on screen?", as the push handler and the background check
/// read it before notifying.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('on-screen');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
  });

  tearDown(() async {
    await OnScreen.hidden();
    dir.deleteSync(recursive: true);
  });

  test('shown counts; hidden or stale does not', () async {
    expect(await OnScreen.now(), isFalse);
    OnScreen.shown();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await OnScreen.now(), isTrue);
    await OnScreen.hidden();
    expect(await OnScreen.now(), isFalse);

    // Left behind by an August that was killed while open: too old.
    File('${dir.path}/on-screen').writeAsStringSync(
      DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
    );
    expect(await OnScreen.now(), isFalse);
  });
}
