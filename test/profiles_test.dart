import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/features/dev/dev_pages.dart';
import 'package:august/platform/data_home.dart';

/// The dev flavor's profiles: folders under August/profiles, one current.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('august-dev');
    DataHome.root = root.path;
  });

  tearDown(() async {
    DataHome.root = DataHome.devRoot;
    await root.delete(recursive: true);
  });

  test('main is the first profile, until another is picked', () async {
    expect(await Profiles.current(), 'main');
    final all = await Profiles.all();
    expect(all.single.id, 'main');
    expect(all.single.name, 'Main');
    File('${root.path}/current.json')
        .writeAsStringSync(jsonEncode({'profile': 'test-1'}));
    expect(await Profiles.current(), 'test-1');
  });

  test('a new profile has its own folder and name; pairing shows', () async {
    final p = await Profiles.create('Tester Two');
    expect(p.id, startsWith('tester-two-'));
    expect(Directory('${root.path}/profiles/${p.id}').existsSync(), isTrue);
    File('${root.path}/profiles/${p.id}/moose.json').writeAsStringSync(
      jsonEncode({
        'partner': {'id': 'x', 'name': 'Shruti', 'pubkey': 'k'},
      }),
    );
    final all = await Profiles.all();
    expect(all.map((p) => p.name), ['Main', 'Tester Two']);
    expect(all.last.partner, 'Shruti');
    expect(all.first.partner, isNull);
  });

  test('deleting removes a profile, never the current one', () async {
    final p = await Profiles.create('Gone');
    await Profiles.delete(p.id);
    expect(Directory('${root.path}/profiles/${p.id}').existsSync(), isFalse);
    Directory('${root.path}/profiles/main').createSync(recursive: true);
    await Profiles.delete('main');
    expect(Directory('${root.path}/profiles/main').existsSync(), isTrue);
  });

  testWidgets('a tap switches; a long press offers Switch and Delete', (
    t,
  ) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('august/dev'),
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('august/dev'),
        null,
      ),
    );
    await t.runAsync(() => Profiles.create('Second'));
    // The list is read from the files (real time, not the test's).
    await t.runAsync(
      () => t.pumpWidget(const CupertinoApp(home: ProfilesPage())),
    );
    for (var i = 0; i < 10 && find.text('Second').evaluate().isEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
    }
    expect(find.text('Second'), findsOneWidget);

    // A long press: the menu, and nothing switched.
    await t.longPress(find.text('Second'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Switch to Second'), findsOneWidget);
    expect(find.text('Delete Second'), findsOneWidget);
    expect(calls, isEmpty);
    // Put the menu away without picking.
    Navigator.of(t.element(find.text('Switch to Second'))).pop();
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Switch to Second'), findsNothing);

    // A tap: straight to it.
    await t.tap(find.text('Second'));
    for (var i = 0; i < 20 && calls.isEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Switch to Second'), findsNothing);
    expect(calls, ['restart']);
    final now = await t.runAsync(Profiles.current);
    expect(now, isNot('main'));
  });
}
