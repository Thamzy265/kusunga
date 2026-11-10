// M1.6 tester, round 4: the apply error while paused (N1): one banner only,
// announced once and not on every tick, focus order, narrow layout at large
// text, and clearing on the user's next pause or resume.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

const _error = "Couldn't apply the pause. Try again.";

class _Unreadable extends FlakyStore {
  _Unreadable() : super(MemoryHistoryStore());
  @override
  String? readSetting(String key) => throw StateError('locked');
}

void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  var now = DateTime(2026, 11, 10, 14, 15).millisecondsSinceEpoch;

  Future<void> show(
    WidgetTester tester, {
    bool unreadable = true,
    Size size = const Size(800, 632),
    double textScale = 1,
    int copies = 0,
    Set<HistoryNotice> notices = const {},
    bool failedLaunch = false,
  }) async {
    now = DateTime(2026, 11, 10, 14, 15).millisecondsSinceEpoch;
    source = FakeClipboardSource();
    final HistoryStore store;
    if (failedLaunch) {
      final m = MemoryHistoryStore();
      for (var i = 0; i < copies; i++) {
        m.insertOrBump('copy $i', ClipKind.text, now + i);
      }
      m.writeSetting(historyPausedSetting, '-1');
      source.pauseAnswer = false;
      store = m;
    } else {
      store = unreadable ? _Unreadable() : MemoryHistoryStore();
    }
    service = HistoryService(
      store: store,
      source: source,
      log: FakeLog(),
      notices: notices,
      clock: () => now,
    )..start();
    addTearDown(service.dispose);
    if (!failedLaunch) {
      for (var i = 0; i < copies; i++) {
        source.copy('copy $i');
        now += 1;
      }
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(disableAnimations: true, alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await tester.pump();
    if (failedLaunch) {
      await service.pause.tick(); // the first retry fails: the error shows
      await tester.pump();
    }
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  String? focusedId() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    String? id;
    var row = false;
    ctx.visitAncestorElements((e) {
      final w = e.widget;
      if (w is HistoryRow) row = true;
      if (id == null && w is Semantics && w.properties.identifier != null) {
        id = w.properties.identifier;
      }
      return true;
    });
    return row ? 'row' : id;
  }

  testWidgets('one banner only: the History tab has one paused banner and '
      'one error, never a second warning banner', (tester) async {
    await show(tester);
    expect(find.text(_error), findsOneWidget);
    expect(hook('history-pause-failed'), findsOneWidget);
    expect(hook('history-paused-resume'), findsOneWidget);
    expect(find.textContaining('History paused'), findsOneWidget);
  });

  testWidgets('a failed second pause while already paused: still one banner '
      'with the error; the next good pause clears it; so does Resume', (
    tester,
  ) async {
    await show(tester, unreadable: false);
    await service.pause.pause(PauseLength.hour);
    await tester.pump();
    source.pauseAnswer = false;
    await service.pause.pause(PauseLength.untilResumed);
    await tester.pump();
    expect(service.pause.isPaused, isTrue);
    expect(find.text(_error), findsOneWidget);
    expect(hook('history-paused-resume'), findsOneWidget);
    source.pauseAnswer = true;
    await service.pause.pause(PauseLength.quarterHour);
    await tester.pump();
    expect(find.text(_error), findsNothing);

    source.pauseAnswer = false;
    await service.pause.pause(PauseLength.hour);
    source.pauseAnswer = true;
    await service.pause.resume();
    await tester.pump();
    expect(find.text(_error), findsNothing);
    expect(find.textContaining('History paused'), findsNothing);
  });

  testWidgets('the error is not announced again on ticks: its live node '
      'exists once, and no "History paused" announcement is added', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester);
    for (var i = 0; i < 6; i++) {
      now += 15000;
      await service.pause.tick();
      await tester.pump();
      expect(find.bySemanticsLabel(_error).evaluate().length, 1, reason: '$i');
    }
    expect(find.bySemanticsLabel('History paused'), findsNothing);
    expect(find.bySemanticsLabel('History resumed'), findsNothing);
    handle.dispose();
  });

  testWidgets('the Privacy tab shows the error once, under the paused line, '
      'with Resume', (tester) async {
    await show(tester);
    await tester.tap(hook('main-tab-privacy'));
    await tester.pump();
    expect(find.text(_error), findsOneWidget);
    expect(hook('pause-error'), findsOneWidget);
    expect(hook('pause-resume'), findsOneWidget);
    final line = tester.getTopLeft(find.text('Paused until you resume.'));
    final err = tester.getTopLeft(find.text(_error));
    expect(err.dy, greaterThan(line.dy));
  });

  testWidgets('focus order in the History tab: tabs, then banner Resume '
      'before any row; the error text takes no focus', (tester) async {
    await show(tester, copies: 3, failedLaunch: true);
    final seen = <String?>[];
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      seen.add(focusedId());
    }
    expect(seen, isNot(contains('history-pause-failed')));
    final r = seen.indexOf('history-paused-resume');
    expect(r, isPositive, reason: '$seen');
    // Banner Resume sits right after the tab strip and right before the
    // first row.
    expect(
      seen[r - 1] == null || seen[r - 1]!.startsWith('main-tab'),
      isTrue,
      reason: '$seen',
    );
    expect(seen[r + 1], 'row', reason: '$seen');
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('360 px at ${scale * 100}% text: the banner with its error '
        'and Resume fit the window, no overflow', (tester) async {
      await show(
        tester,
        size: const Size(360, 640),
        textScale: scale,
        copies: 2,
        failedLaunch: true,
      );
      expect(tester.takeException(), isNull);
      for (final id in ['history-paused-resume', 'history-pause-failed']) {
        final r = tester.getRect(hook(id));
        expect(r.left, greaterThanOrEqualTo(0), reason: id);
        expect(r.right, lessThanOrEqualTo(360), reason: id);
      }
      await tester.tap(hook('main-tab-privacy'));
      await tester.pump();
      await tester.ensureVisible(hook('pause-error'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
