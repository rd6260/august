import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/doodles/doodles_page.dart';
import '../platform/doodle_widget.dart';
import 'router.dart';

/// Keeps the home screen widget in step while August is open: redraws it
/// when the picked doodle, the pick or the theme changes, tells the server
/// whether this phone has a widget, and opens the board when it's tapped.
class DoodleWidgetSync {
  DoodleWidgetSync(this.ref, this.router);

  final WidgetRef ref;
  final GoRouter router;
  final _subs = <ProviderSubscription<Object?>>[];
  StreamSubscription<Uri?>? _clicks;
  Timer? _redraw;
  bool? _told;

  Future<void> start() async {
    if (!DoodleWidget.supported) return;
    _subs
      ..add(ref.listenManual(widgetDoodleProvider, (_, _) => _soon()))
      ..add(ref.listenManual(chatThemeProvider, (_, _) => _soon()))
      ..add(
        ref.listenManual<Doodle?>(_pinnedDoodle, (a, b) {
          if (!identical(a, b)) _soon();
        }),
      );
    _soon();
    unawaited(placed());
    try {
      _open(await HomeWidget.initiallyLaunchedFromHomeWidget());
      _clicks = HomeWidget.widgetClicked.listen(_open);
    } on Object {
      // No widget plugin here.
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    _redraw?.cancel();
    unawaited(_clicks?.cancel());
  }

  /// Tells the server, once it changes, whether there's a widget here, so
  /// the partner's drawing wakes this phone only when it has one.
  Future<void> placed() async {
    final yes = await DoodleWidget.placed();
    if (yes == _told) return;
    _told = yes;
    ref.read(chatRepositoryProvider).hasWidget(yes);
  }

  /// Puts the board on the home screen: the launcher's own "Add widget"
  /// when it can, and reports it once it's there.
  Future<void> add() async {
    await DoodleWidget.add();
    await Future<void>.delayed(const Duration(seconds: 2));
    await placed();
  }

  void _soon() {
    _redraw?.cancel();
    _redraw = Timer(const Duration(milliseconds: 600), () async {
      try {
        await DoodleWidget.show(
          doodle: ref.read(_pinnedDoodle),
          theme: ref.read(chatThemeProvider),
          dir: await getApplicationSupportDirectory(),
        );
      } on Object {
        // The widget can wait for the next change.
      }
    });
  }

  void _open(Uri? uri) {
    if (uri == null || uri.host != DoodleWidget.host) return;
    final id = uri.queryParameters['id'];
    router.go(Routes.doodles);
    if (id == null || !ref.read(doodlesProvider).any((d) => d.id == id)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (context != null && context.mounted) unawaited(openBoard(context, id));
    });
  }
}

/// The board on the widget, or null when none is picked (or it's gone).
final _pinnedDoodle = Provider<Doodle?>((ref) {
  final id = ref.watch(widgetDoodleProvider);
  if (id == null) return null;
  return ref.watch(doodlesProvider).where((d) => d.id == id).firstOrNull;
});

/// The app's [DoodleWidgetSync], for the doodles page's "Add to home
/// screen" (null in tests and off Android).
DoodleWidgetSync? doodleWidgetSync;
