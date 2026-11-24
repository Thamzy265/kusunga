// M1.6 fix round 3 (reviewer N1): "Couldn't apply the pause. Try again."
// also shows while paused. After a launch send that failed, or a settings
// read error (which means paused until resume), native code may not be
// paused although Kusunga says it is. The Privacy tab shows the error under
// the paused line, next to Resume; the History tab shows it inside the
// paused banner, as one live region, with no second banner.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

/// Settings can't be read, so the pause starts as "until resumed" with the
/// apply error (R2).
class _UnreadableSettings extends FlakyStore {
  _UnreadableSettings() : super(MemoryHistoryStore());

  @override
  String? readSetting(String key) => throw StateError('database locked');
}

const _error = "Couldn't apply the pause. Try again.";

void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
    double textScale = 1,
  }) async {
    source = FakeClipboardSource();
    service = HistoryService(
      store: _UnreadableSettings(),
      source: source,
      log: FakeLog(),
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: HistoryHost(history: Future.value(service), initial: service),
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

  testWidgets('the start state: paused until resume, with the apply error', (
    tester,
  ) async {
    await show(tester);
    expect(service.pause.untilResumed, isTrue);
    expect(service.pause.error, PauseError.apply);
  });

  group('Privacy tab', () {
    testWidgets('the error shows under the paused line, next to Resume', (
      tester,
    ) async {
      await show(tester);
      await openPrivacy(tester);
      expect(find.text('Paused until you resume.'), findsOneWidget);
      expect(find.text(_error), findsOneWidget);
      expect(hook('pause-error'), findsOneWidget);
      final line = tester.getBottomLeft(find.text('Paused until you resume.'));
      final resume = tester.getBottomLeft(hook('pause-resume'));
      final error = tester.getTopLeft(find.text(_error));
      expect(error.dy, greaterThanOrEqualTo(line.dy));
      expect(error.dy, greaterThanOrEqualTo(resume.dy));
    });

    testWidgets('a resume that works clears it', (tester) async {
      await show(tester);
      await openPrivacy(tester);
      await tester.tap(hook('pause-resume'));
      await tester.pump();
      await tester.pump();
      expect(service.pause.isPaused, isFalse);
      expect(find.text(_error), findsNothing);
    });

    testWidgets('360 px at 200% text: no overflow, the error in view', (
      tester,
    ) async {
      await show(tester, size: const Size(360, 632), textScale: 2);
      await openPrivacy(tester);
      expect(tester.takeException(), isNull);
      final r = tester.getRect(find.text(_error));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
    });
  });

  group('History tab', () {
    testWidgets('the paused banner carries the error, as one live region, '
        'with no second banner', (tester) async {
      await show(tester);
      expect(
        find.text("History paused. New copies aren't kept."),
        findsOneWidget,
      );
      expect(find.text(_error), findsOneWidget);
      expect(hook('history-pause-failed'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(hook('history-pause-failed'))
            .properties
            .liveRegion,
        isTrue,
      );
      // Inside the paused banner: the error sits between its text and the
      // banner's bottom edge, above the list.
      final banner = find.ancestor(
        of: hook('history-paused-resume'),
        matching: find.byType(Container),
      );
      final box = tester.getRect(banner.first);
      final err = tester.getRect(find.text(_error));
      expect(box.contains(err.center), isTrue);
    });

    testWidgets('a resume from the banner clears it', (tester) async {
      await show(tester);
      await tester.tap(hook('history-paused-resume'));
      await tester.pump();
      await tester.pump();
      expect(find.text(_error), findsNothing);
      expect(find.textContaining('History paused'), findsNothing);
    });

    testWidgets('360 px at 200% text: no overflow, the error in view', (
      tester,
    ) async {
      await show(tester, size: const Size(360, 632), textScale: 2);
      expect(tester.takeException(), isNull);
      final r = tester.getRect(find.text(_error));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
      expect(find.text(_error), findsOneWidget);
    });
  });
}
