import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:august/core/theme/v_colors.dart';
import 'package:august/data/models.dart';
import 'package:august/net/api.dart';
import 'package:august/net/crypto.dart';
import 'package:august/net/local_store.dart';
import 'package:august/net/push.dart';
import 'package:august/net/vault.dart';
import 'package:august/net/wire.dart';

void main() {
  late MemoryVault mine;
  late LocalStore store;
  late Channel fromShruti;

  setUp(() async {
    mine = MemoryVault();
    final me = await Identity.load(mine);
    final shruti = await Identity.load(MemoryVault());
    final dir = await Directory.systemTemp.createTemp('august-push');
    addTearDown(() => dir.delete(recursive: true));
    store = await LocalStore.open(dir)
      ..partner = Member(id: 'a', name: 'Shruti', pubkey: shruti.publicKey);
    fromShruti = await shruti.channelTo(me.publicKey);
  });

  Future<String> seal(Body body) async => fromShruti.sealJson(
    MessageEnvelope(
      Message(id: 'm', fromMe: true, at: DateTime.now(), body: body),
    ).toJson(),
  );

  test('a message shows its text by default', () async {
    final n = await Push.describe(
      {'kind': 'msg', 'body': await seal(const TextBody('see you at 8'))},
      vault: mine,
      store: store,
    );
    expect(n!.title, 'Shruti');
    expect(n.body, 'see you at 8');
  });

  test('with message text off, it says only that something came', () async {
    store.settings = store.settings.copyWith(showPreview: false);
    final n = await Push.describe(
      {'kind': 'msg', 'body': await seal(const TextBody('the secret'))},
      vault: mine,
      store: store,
    );
    expect(n!.title, 'Shruti');
    expect(n.body, 'New message');
    expect(n.body, isNot(contains('secret')));
    expect(n.moment, isFalse);
  });

  test('a moment is opened and named, on the loud channel', () async {
    final n = await Push.describe(
      {'kind': 'moment', 'body': await seal(const MomentBody(VMoment.hug))},
      vault: mine,
      store: store,
    );
    expect(n!.body, '${VMoment.hug.emoji} Shruti sent a hug');
    expect(n.moment, isTrue);
  });

  test('mail that is not a message stays quiet', () async {
    final doodle = await fromShruti.sealJson(
      const DoodleEnvelope(DoodleRenamed('d1', 'Our wall')).toJson(),
    );
    final typing = await fromShruti.sealJson(
      const TypingEnvelope(true).toJson(),
    );
    for (final data in [
      {'kind': 'doodle', 'body': doodle},
      {'kind': 'typing', 'body': typing},
      {'kind': 'wake'},
      {'kind': 'receipt'},
    ]) {
      expect(
        await Push.describe(data, vault: mine, store: store),
        isNull,
        reason: '${data['kind']}',
      );
    }
  });

  test('too big to ride along: said from the kind alone', () async {
    final n = await Push.describe({'kind': 'call'}, vault: mine, store: store);
    expect(n!.body, 'Calling you');
  });

  test('not sealed by the partner, or not paired: nothing shows', () async {
    final stranger = await (await Identity.load(MemoryVault()))
        .channelTo((await Identity.load(mine)).publicKey);
    final forged = await stranger.sealJson({'type': 'msg'});
    expect(
      await Push.describe(
        {'kind': 'msg', 'body': forged},
        vault: mine,
        store: store,
      ),
      isNull,
    );
    store.partner = null;
    expect(
      await Push.describe({'kind': 'msg'}, vault: mine, store: store),
      isNull,
    );
  });
}
