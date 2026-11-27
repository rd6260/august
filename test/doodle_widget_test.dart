import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:august/data/chat_theme.dart';
import 'package:august/data/models.dart';
import 'package:august/data/providers.dart';
import 'package:august/mock/mock_data.dart';
import 'package:august/mock/mock_repositories.dart';
import 'package:august/net/wire.dart';
import 'package:august/platform/doodle_widget.dart';

/// Records what the doodles share and how often the partner is woken.
class _Recorder extends MockChatRepository {
  final shared = <DoodleOp>[];
  var wakes = 0;

  @override
  void shareDoodle(DoodleOp op) => shared.add(op);

  @override
  void wakeWidget() => wakes++;
}

/// The home screen widget's doodle: the shared pick, its wake-ups, the
/// pure op applier the background redraw uses, and the picture itself.
void main() {
  Stroke line(double y) => Stroke(
    tool: PenTool.fineLiner,
    argb: 0xFFFF5C7A,
    size: 4,
    opacity: 1,
    points: [Offset(40, y), Offset(200, y + 10), Offset(320, y)],
  );

  test('the pick travels as a pin op; older phones read it as nothing', () {
    for (final id in ['d1', null]) {
      final back = Wire.doodleOp(Wire.fromDoodleOp(DoodlePinned(id)));
      expect(back, isA<DoodlePinned>());
      expect((back as DoodlePinned).id, id);
    }
    // What 0.33.0 does with it: an unknown op is a presence change, which
    // only moves the "live" dot.
    final j = Wire.fromDoodleOp(const DoodlePinned('d1'));
    expect(j['op'], 'pin');
  });

  test('picking shares it, and a remote pick lands without echo', () {
    final repo = _Recorder();
    final c = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final d = c.read(doodlesProvider).first;
    c.read(widgetDoodleProvider.notifier).pin(d.id);
    expect(c.read(widgetDoodleProvider), d.id);
    expect(repo.shared.single, isA<DoodlePinned>());

    c.read(doodlesProvider.notifier).applyRemote(const DoodlePinned('other'));
    expect(c.read(widgetDoodleProvider), 'other');
    expect(repo.shared, hasLength(1));
  });

  testWidgets('drawing on the picked board wakes the partner, bunched', (
    t,
  ) async {
    var clock = DateTime(2026, 11, 27, 14);
    WidgetDoodleNotifier.now = () => clock;
    addTearDown(() => WidgetDoodleNotifier.now = DateTime.now);
    Future<void> wait(int seconds) async {
      for (var i = 0; i < seconds * 4; i++) {
        clock = clock.add(const Duration(milliseconds: 250));
        await t.pump(const Duration(milliseconds: 250));
      }
    }

    final repo = _Recorder();
    final c = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final boards = c.read(doodlesProvider);
    final pinned = boards.first.id;
    final other = boards.last.id;
    c.read(widgetDoodleProvider.notifier).pin(pinned);
    await wait(4);
    expect(repo.wakes, 1, reason: 'the pick itself');

    // Another board: no wake.
    c.read(doodlesProvider.notifier).setStrokes(other, [line(100)]);
    await wait(4);
    expect(repo.wakes, 1);

    // A stroke a second for 20 s: one at 15 s, then one after the pause.
    var strokes = <Stroke>[];
    for (var i = 0; i < 20; i++) {
      strokes = [...strokes, line(100.0 + i)];
      c.read(doodlesProvider.notifier).setStrokes(pinned, strokes);
      await wait(1);
    }
    expect(repo.wakes, 2);
    await wait(4);
    expect(repo.wakes, 3);
  });

  test('ops apply the same way in the app and in the background', () {
    final start = MockData.doodles();
    final id = start.first.id;
    final at = DateTime(2026, 11, 27, 14, 32);
    var boards = applyDoodleOp(
      start,
      StrokesAdded(id, [line(50)]),
      partner: 'Aatika',
      at: at,
    );
    final d = boards.first;
    expect(d.strokes.length, start.first.strokes.length + 1);
    expect(d.editedBy, 'Aatika');
    expect(DoodleWidget.caption(d, now: at), 'Aatika · 14:32');
    expect(
      DoodleWidget.caption(d, now: at.add(const Duration(days: 2))),
      'Aatika · 27 Nov',
    );
    boards = applyDoodleOp(boards, DoodleDeleted(id), partner: 'Aatika');
    expect(boards.any((b) => b.id == id), isFalse);
    expect(
      identical(
        applyDoodleOp(boards, const DoodlePinned('x'), partner: 'A'),
        boards,
      ),
      isTrue,
    );
  });

  test('the picture is a square PNG, on either ink', () async {
    for (final wp in ['night', 'paper']) {
      final png = await DoodleWidget.render(
        MockData.doodles().first,
        ChatTheme(wallpaper: WallpaperRef.builtin(wp)),
        size: 120,
      );
      expect(png.sublist(1, 4), Uint8List.fromList('PNG'.codeUnits));
    }
  });
}
