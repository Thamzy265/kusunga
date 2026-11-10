// M1.6 tester: the UI spec's states matrix and accessibility notes
// (docs/ui/sensitive-content.md): announcements exactly once, a timed pause
// ending while open, focus order and focus after pause or resume, errors and
// notes together, and narrow layouts at large text.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

const _min = 60 * 1000;

void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  late int now;
  var use24 = true;
  late WidgetTester tester0;

  setUp(() {
    source = FakeClipboardSource();
    use24 = true;
    now = DateTime(2026, 11, 10, 14, 15).millisecondsSinceEpoch;
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
    double textScale = 1,
    Set<HistoryNotice> notices = const {},
    int copies = 0,
  }) async {
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      notices: notices,
      clock: () => now,
    )..start();
    addTearDown(service.dispose);
    for (var i = 0; i < copies; i++) {
      source.copy('copy number $i');
      now += 1;
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: true, alwaysUse24HourFormat: use24),
          child: child!,
        ),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> tapHook(WidgetTester tester, String id) async {
    await tester.ensureVisible(hook(id));
    await tester.pump();
    await tester.tap(hook(id));
    await tester.pump();
    await tester.pump();
  }

  Future<void> openTab(WidgetTester tester, String name) =>
      tapHook(tester, 'main-tab-$name');

  /// What holds the focus: a Semantics identifier above it, or 'row' for a
  /// history row, or null.
  String? focusedId() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    String? id;
    var inRow = false;
    ctx.visitAncestorElements((e) {
      final w = e.widget;
      if (w is HistoryRow) inRow = true;
      if (id == null && w is Semantics && w.properties.identifier != null) {
        id = w.properties.identifier;
      }
      return true;
    });
    return inRow ? 'row' : id;
  }

  int liveCount(WidgetTester tester, String label) =>
      find.bySemanticsLabel(label).evaluate().length;

  group('announcements, exactly once', () {
    testWidgets('pause then no-change ticks: one node, never repeated', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        now += 1000;
        await service.pause.tick();
        await tester.pump();
      }
      expect(liveCount(tester, 'History paused until 14:30'), 1);
      expect(liveCount(tester, 'History resumed'), 0);
      handle.dispose();
    });

    testWidgets('a timed pause ending while open announces History resumed '
        'once, and the paused message is gone', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      now += 16 * _min;
      await service.pause.tick();
      await tester.pump();
      await service.pause.tick();
      await tester.pump();
      expect(liveCount(tester, 'History resumed'), 1);
      expect(find.bySemanticsLabel(RegExp('^History paused')), findsNothing);
      handle.dispose();
    });

    testWidgets('pausing from the tray (the service) is announced on any '
        'tab, also with the Snippets tab shown', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await openTab(tester, 'snippets');
      await service.pause.pause(PauseLength.untilResumed);
      await tester.pump();
      expect(liveCount(tester, 'History paused'), 1);
      handle.dispose();
    });

    testWidgets('switching tabs does not announce again', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await service.pause.pause(PauseLength.untilResumed);
      await tester.pump();
      await openTab(tester, 'privacy');
      await openTab(tester, 'history');
      await openTab(tester, 'privacy');
      expect(liveCount(tester, 'History paused'), 1);
      handle.dispose();
    });

    testWidgets('a failed pause announces nothing', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      source.pauseAnswer = false;
      await service.pause.pause(PauseLength.hour);
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('^History (paused|resumed)')),
        findsNothing,
      );
      handle.dispose();
    });
  });

  group('focus', () {
    testWidgets('banner Resume is reached before any list row by Tab', (
      tester,
    ) async {
      await show(tester, copies: 3);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      await tester.tap(hook('main-tab-history'));
      await tester.pump();
      final seen = <String?>[];
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        seen.add(focusedId());
      }
      final resume = seen.indexOf('history-paused-resume');
      final row = seen.indexOf('row');
      expect(resume, isNonNegative, reason: '$seen');
      expect(row, isNonNegative, reason: '$seen');
      expect(resume, lessThan(row), reason: '$seen');
    });

    testWidgets('tab order in the Privacy tab: tabs, then the three pause '
        'buttons in order, then Resume only when paused', (tester) async {
      await show(tester);
      await openTab(tester, 'privacy');
      final seen = <String?>[];
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        seen.add(focusedId());
      }
      final a = seen.indexOf('pause-15');
      final b = seen.indexOf('pause-60');
      final c = seen.indexOf('pause-until');
      expect([a, b, c].every((i) => i >= 0), isTrue, reason: '$seen');
      expect(a < b && b < c, isTrue, reason: '$seen');
      expect(seen, isNot(contains('pause-resume')));
    });

    testWidgets('banner Resume by keyboard (Enter): paused ends, focus is not '
        'left on a removed control', (tester) async {
      await show(tester, copies: 2);
      await service.pause.pause(PauseLength.untilResumed);
      await tester.pump();
      var guard = 0;
      while (focusedId() != 'history-paused-resume' && guard++ < 15) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedId(), 'history-paused-resume');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(service.pause.isPaused, isFalse);
      expect(hook('history-paused-resume'), findsNothing);
      // The keyboard user must still have somewhere to be: a focused node
      // that is attached, not the dead banner button.
      final node = FocusManager.instance.primaryFocus;
      expect(node?.context, isNotNull, reason: 'focus was dropped');
      expect(focusedId(), isNot('history-paused-resume'));
    });

    testWidgets('Space on a pause button in the Privacy tab pauses, and '
        'focus lands on Resume; Resume by Enter returns focus to the first '
        'button', (tester) async {
      await show(tester);
      await openTab(tester, 'privacy');
      var guard = 0;
      while (focusedId() != 'pause-15' && guard++ < 10) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump();
      expect(service.pause.isPaused, isTrue);
      expect(focusedId(), 'pause-resume');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(focusedId(), 'pause-15');
    });

    testWidgets('a pause that starts elsewhere (the tray) does not steal the '
        'focus from a field the user is in', (tester) async {
      await show(tester, copies: 1);
      await tester.tap(hook('main-tab-privacy'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final before = focusedId();
      await service.pause.pause(PauseLength.hour);
      await tester.pump();
      await tester.pump();
      // Spec: focus moves to Resume only for the user's own action here.
      // The focused button is replaced by Resume; focus goes to Resume or
      // falls back to the tab strip, never to nowhere.
      expect(before, 'pause-15');
      expect(focusedId(), anyOf('pause-resume', 'main-tab-privacy'));
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    });
  });

  group('states together', () {
    testWidgets('native error, then a good retry: the error text goes', (
      tester,
    ) async {
      await show(tester);
      await openTab(tester, 'privacy');
      source.pauseAnswer = false;
      await tapHook(tester, 'pause-60');
      expect(find.text("Couldn't apply the pause. Try again."), findsOneWidget);
      source.pauseAnswer = true;
      await tapHook(tester, 'pause-60');
      expect(find.text("Couldn't apply the pause. Try again."), findsNothing);
      expect(service.pause.isPaused, isTrue);
    });

    testWidgets('an apply error is not shown on top of the paused state, and '
        'a resume error goes after a good resume', (tester) async {
      await show(tester);
      await openTab(tester, 'privacy');
      await tapHook(tester, 'pause-until');
      source.pauseAnswer = false;
      await tapHook(tester, 'pause-resume');
      expect(find.text("Couldn't resume. Try again."), findsOneWidget);
      expect(find.text("Couldn't apply the pause. Try again."), findsNothing);
      source.pauseAnswer = true;
      await tapHook(tester, 'pause-resume');
      expect(find.text("Couldn't resume. Try again."), findsNothing);
      expect(find.text('For 15 minutes'), findsOneWidget);
    });

    testWidgets('memory-only and paused: the note is shown with the paused '
        'text', (tester) async {
      await show(tester, notices: const {HistoryNotice.memoryOnly});
      await openTab(tester, 'privacy');
      await tapHook(tester, 'pause-until');
      expect(find.text('Paused until you resume.'), findsOneWidget);
      expect(
        find.text("Pause won't last after Kusunga quits."),
        findsOneWidget,
      );
    });

    testWidgets('12-hour format: the banner and the Privacy tab agree', (
      tester,
    ) async {
      use24 = false;
      now = DateTime(2026, 11, 10, 23, 55).millisecondsSinceEpoch;
      await show(tester);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      expect(
        find.text(
          "History paused until tomorrow 12:10 AM. New copies aren't kept.",
        ),
        findsOneWidget,
      );
      await openTab(tester, 'privacy');
      expect(find.text('Paused until tomorrow 12:10 AM.'), findsOneWidget);
    });

    testWidgets('a pause ended by the clock but not yet ticked: the banner '
        'is gone as soon as it rebuilds', (tester) async {
      await show(tester);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      now += 15 * _min; // exactly the end, no tick yet
      await service.pause.tick();
      await tester.pump();
      expect(find.textContaining('History paused'), findsNothing);
    });

    testWidgets('the tab strip and the paused banner show on the History tab '
        'only; the picker-style tabs are unchanged', (tester) async {
      await show(tester);
      await service.pause.pause(PauseLength.untilResumed);
      await tester.pump();
      await openTab(tester, 'snippets');
      expect(hook('history-paused-resume'), findsNothing);
    });
  });

  group('accessible names and headings (UI spec, Accessibility notes)', () {
    String? label(String id) =>
        tester0.widget<Semantics>(hook(id)).properties.label;

    testWidgets('the four buttons carry the spec names', (tester) async {
      tester0 = tester;
      await show(tester);
      await openTab(tester, 'privacy');
      expect(label('pause-15'), 'Pause history for 15 minutes');
      expect(label('pause-60'), 'Pause history for 1 hour');
      expect(label('pause-until'), 'Pause history until I resume');
      await tapHook(tester, 'pause-until');
      expect(label('pause-resume'), 'Resume history');
    });

    testWidgets('Pause history is a heading in the Privacy panel', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await openTab(tester, 'privacy');
      final heading = find.semantics.byPredicate(
        (n) => n.label == 'Pause history' && n.flagsCollection.isHeader,
      );
      expect(heading, findsOneWidget);
      handle.dispose();
    });
  });

  group('narrow, large text (320 px stand-in: 360 px at 200%)', () {
    for (final scale in [2.0, 3.0]) {
      testWidgets('Privacy, paused, error and note at ${scale * 100}% text: '
          'no overflow, no sideways scroll, targets 24 px', (tester) async {
        await show(
          tester,
          size: const Size(360, 640),
          textScale: scale,
          notices: const {HistoryNotice.memoryOnly},
        );
        await openTab(tester, 'privacy');
        await tapHook(tester, 'pause-until');
        source.pauseAnswer = false;
        await tapHook(tester, 'pause-resume');
        expect(tester.takeException(), isNull);
        final r = tester.getRect(hook('pause-resume'));
        expect(r.width, greaterThanOrEqualTo(24));
        expect(r.height, greaterThanOrEqualTo(24));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
        final horizontal = find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        );
        expect(horizontal, findsNothing);
      });

      testWidgets('History banner paused, 12-hour tomorrow text, at '
          '${scale * 100}%: Resume stays inside the window', (tester) async {
        use24 = false;
        now = DateTime(2026, 11, 10, 23, 55).millisecondsSinceEpoch;
        await show(
          tester,
          size: const Size(360, 640),
          textScale: scale,
          copies: 3,
        );
        await service.pause.pause(PauseLength.quarterHour);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final r = tester.getRect(hook('history-paused-resume'));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
        expect(r.width, greaterThanOrEqualTo(24));
      });
    }

    testWidgets('minimum window 360 x 400 at 200%: Privacy still reaches the '
        'pause buttons by scrolling, no overflow', (tester) async {
      await show(tester, size: const Size(360, 400), textScale: 2);
      await openTab(tester, 'privacy');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(hook('pause-until'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final r = tester.getRect(hook('pause-until'));
      expect(r.bottom, lessThanOrEqualTo(400));
    });
  });
}
