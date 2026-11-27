import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
        'partner': {'id': 'x', 'name': 'Aatika', 'pubkey': 'k'},
      }),
    );
    final all = await Profiles.all();
    expect(all.map((p) => p.name), ['Main', 'Tester Two']);
    expect(all.last.partner, 'Aatika');
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
}
