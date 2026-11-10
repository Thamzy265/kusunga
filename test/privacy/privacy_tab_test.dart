// M1.6 UI spec (docs/ui/sensitive-content.md): the Privacy tab in the main
// window, its Pause history states, the History banner while paused, and
// the moved ignored-apps list with the "Edit ignored apps" link.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  late int now;

  setUp(() {
    source = FakeClipboardSource();
    now = DateTime(2026, 11, 10, 14, 15).millisecondsSinceEpoch;
  });

  HistoryService make({Set<HistoryNotice> notices = const {}}) {
    final s = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      notices: notices,
      clock: () => now,
    )..start();
    addTearDown(s.dispose);
    return s;
  }

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
    double textScale = 1,
    Widget? ignoredApps,
    Widget? snippetsTopSlot,
    Set<HistoryNotice> notices = const {},
  }) async {
    service = make(notices: notices);
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
          ).copyWith(disableAnimations: true, alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: HistoryHost(
          history: Future.value(service),
          initial: service,
          ignoredAppsSlot: ignoredApps,
          snippetsTopSlot: snippetsTopSlot,
        ),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> openPrivacy(WidgetTester tester) async {
    await tester.tap(hook('main-tab-privacy'));
    await tester.pump();
  }

  Future<void> tapHook(WidgetTester tester, String id) async {
    await tester.tap(hook(id));
    await tester.pump();
    await tester.pump();
  }

  bool focused(WidgetTester tester, String id) {
    final el = tester.element(hook(id));
    final node = Focus.maybeOf(el);
    var hasFocus = node?.hasFocus ?? false;
    el.visitChildElements((c) {
      void walk(Element e) {
        if (e.widget is Focus &&
            (e.widget as Focus).focusNode?.hasFocus == true) {
          hasFocus = true;
        }
        e.visitChildElements(walk);
      }

      walk(c);
    });
    return hasFocus;
  }

  group('the Privacy tab', () {
    testWidgets('a third tab named Privacy, after History and Snippets', (
      tester,
    ) async {
      await show(tester);
      final tabs = [
        for (final id in [
          'main-tab-history',
          'main-tab-snippets',
          'main-tab-privacy',
        ])
          tester.widget<Semantics>(hook(id)).properties.label,
      ];
      expect(tabs, ['History', 'Snippets', 'Privacy']);
    });

    testWidgets('not paused: the heading, text and three buttons', (
      tester,
    ) async {
      await show(tester);
      await openPrivacy(tester);
      expect(find.text('Pause history'), findsOneWidget);
      expect(
        find.text('Stop adding copies to history for a while.'),
        findsOneWidget,
      );
      expect(find.text('For 15 minutes'), findsOneWidget);
      expect(find.text('For 1 hour'), findsOneWidget);
      expect(find.text('Until I resume'), findsOneWidget);
      final labels = [
        for (final id in ['pause-15', 'pause-60', 'pause-until'])
          tester.widget<Semantics>(hook(id)).properties.label,
      ];
      expect(labels, [
        'Pause history for 15 minutes',
        'Pause history for 1 hour',
        'Pause history until I resume',
      ]);
      final heading = tester.getSemantics(find.text('Pause history'));
      expect(heading.flagsCollection.isHeader, isTrue);
    });

    testWidgets('For 15 minutes: paused until the time, focus on Resume', (
      tester,
    ) async {
      await show(tester);
      await openPrivacy(tester);
      await tapHook(tester, 'pause-15');
      expect(service.pause.isPaused, isTrue);
      expect(find.text('Paused until 14:30.'), findsOneWidget);
      expect(find.text('For 15 minutes'), findsNothing);
      expect(
        tester.widget<Semantics>(hook('pause-resume')).properties.label,
        'Resume history',
      );
      expect(focused(tester, 'pause-resume'), isTrue);
    });

    testWidgets('Until I resume, then Resume: focus back on For 15 minutes', (
      tester,
    ) async {
      await show(tester);
      await openPrivacy(tester);
      await tapHook(tester, 'pause-until');
      expect(find.text('Paused until you resume.'), findsOneWidget);
      await tapHook(tester, 'pause-resume');
      expect(service.pause.isPaused, isFalse);
      expect(find.text('For 15 minutes'), findsOneWidget);
      expect(focused(tester, 'pause-15'), isTrue);
    });

    testWidgets('an end not today says tomorrow', (tester) async {
      now = DateTime(2026, 11, 10, 23, 30).millisecondsSinceEpoch;
      await show(tester);
      await openPrivacy(tester);
      await tapHook(tester, 'pause-60');
      expect(find.text('Paused until tomorrow 00:30.'), findsOneWidget);
    });

    testWidgets('pausing and resuming are announced in a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await openPrivacy(tester);
      await tapHook(tester, 'pause-15');
      expect(
        find.bySemanticsLabel('History paused until 14:30'),
        findsOneWidget,
      );
      await tapHook(tester, 'pause-resume');
      expect(find.bySemanticsLabel('History resumed'), findsOneWidget);
      await tapHook(tester, 'pause-until');
      expect(find.bySemanticsLabel('History paused'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('memory-only: the buttons work, with the note', (tester) async {
      await show(tester, notices: const {HistoryNotice.memoryOnly});
      await openPrivacy(tester);
      expect(
        find.text("Pause won't last after Kusunga quits."),
        findsOneWidget,
      );
      await tapHook(tester, 'pause-15');
      expect(service.pause.isPaused, isTrue);
    });

    testWidgets('native call failed: the error, and the buttons stay', (
      tester,
    ) async {
      await show(tester);
      await openPrivacy(tester);
      source.pauseAnswer = false;
      await tapHook(tester, 'pause-60');
      expect(find.text("Couldn't apply the pause. Try again."), findsOneWidget);
      expect(find.text('For 1 hour'), findsOneWidget);
    });

    testWidgets('resume failed: stays paused, with its error', (tester) async {
      await show(tester);
      await openPrivacy(tester);
      await tapHook(tester, 'pause-until');
      source.pauseAnswer = false;
      await tapHook(tester, 'pause-resume');
      expect(find.text("Couldn't resume. Try again."), findsOneWidget);
      expect(find.text('Paused until you resume.'), findsOneWidget);
    });

    testWidgets('the Ignored apps section with its copy and the list', (
      tester,
    ) async {
      await show(tester, ignoredApps: const Text('THE LIST'));
      await openPrivacy(tester);
      expect(find.text('Ignored apps'), findsOneWidget);
      expect(
        find.text(
          "Copies from these apps aren't kept, and typed shortcuts don't "
          'work in them.',
        ),
        findsOneWidget,
      );
      expect(find.text('THE LIST'), findsOneWidget);
      expect(
        find.text('Kusunga also skips anything an app marks as private.'),
        findsOneWidget,
      );
      final heading = tester.getSemantics(find.text('Ignored apps'));
      expect(heading.flagsCollection.isHeader, isTrue);
    });

    testWidgets('without a list there is no Ignored apps section', (
      tester,
    ) async {
      await show(tester);
      await openPrivacy(tester);
      expect(find.text('Ignored apps'), findsNothing);
    });

    testWidgets('"Edit ignored apps" opens Privacy with focus on the heading', (
      tester,
    ) async {
      await show(
        tester,
        ignoredApps: const Text('THE LIST'),
        snippetsTopSlot: Builder(
          builder: (context) => TextButton(
            onPressed: () => HistoryHost.showIgnoredApps(context),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(hook('main-tab-snippets'));
      await tester.pump();
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Semantics>(hook('main-tab-privacy')).properties.selected,
        isTrue,
      );
      expect(focused(tester, 'privacy-ignored-apps-heading'), isTrue);
    });

    testWidgets('360 px at 200% text: no overflow; the buttons stack', (
      tester,
    ) async {
      await show(
        tester,
        size: const Size(360, 632),
        textScale: 2,
        ignoredApps: const Text('THE LIST'),
      );
      await openPrivacy(tester);
      expect(tester.takeException(), isNull);
      final a = tester.getTopLeft(hook('pause-15'));
      final b = tester.getTopLeft(hook('pause-60'));
      expect(b.dy, greaterThan(a.dy));
      await tapHook(tester, 'pause-60');
      expect(tester.takeException(), isNull);
    });
  });

  group('the History banner while paused', () {
    testWidgets('shows until when, with Resume before the list', (
      tester,
    ) async {
      await show(tester);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      expect(
        find.text('History paused until 14:30. New copies aren\'t kept.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Semantics>(hook('history-paused-resume'))
            .properties
            .label,
        'Resume history',
      );
      await tapHook(tester, 'history-paused-resume');
      expect(service.pause.isPaused, isFalse);
      expect(find.textContaining('History paused'), findsNothing);
    });

    testWidgets('until resumed: no time', (tester) async {
      await show(tester);
      await service.pause.pause(PauseLength.untilResumed);
      await tester.pump();
      expect(
        find.text('History paused. New copies aren\'t kept.'),
        findsOneWidget,
      );
    });

    testWidgets('goes when a timed pause ends', (tester) async {
      await show(tester);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      now += 15 * 60 * 1000;
      await service.pause.tick();
      await tester.pump();
      expect(find.textContaining('History paused'), findsNothing);
    });

    testWidgets('wraps at narrow widths without overflow', (tester) async {
      await show(tester, size: const Size(360, 632), textScale: 2);
      await service.pause.pause(PauseLength.quarterHour);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no banner when not paused', (tester) async {
      await show(tester);
      expect(hook('history-paused-resume'), findsNothing);
    });
  });
}
