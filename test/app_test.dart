import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import 'support/fakes.dart';

Future<HistoryService> _history() async => HistoryService(
  store: MemoryHistoryStore(),
  source: FakeClipboardSource(),
  log: const NullErrorLog(),
)..start();

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(800, 632),
  double textScale = 1.0,
  Brightness? brightness,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  if (brightness != null) {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }
  await tester.pumpWidget(KusungaApp(history: _history()));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('app title is Kusunga', (tester) async {
    await _pump(tester);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Kusunga',
    );
  });

  testWidgets('the home view is the history list', (tester) async {
    await _pump(tester);
    // The History tab (M1.4) and the history screen's heading.
    expect(find.text('History'), findsNWidgets(2));
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('renders in ${b.name} mode with matching tokens', (
      tester,
    ) async {
      await _pump(tester, brightness: b);
      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, b);
      expect(
        Theme.of(context).extension<KusungaTokens>(),
        b == Brightness.dark ? KusungaTokens.dark : KusungaTokens.light,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the smallest window (360x400) has no overflow', (tester) async {
    await _pump(tester, size: const Size(360, 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text scale 2.0 at the smallest window has no overflow', (
    tester,
  ) async {
    await _pump(tester, size: const Size(360, 400), textScale: 2.0);
    expect(tester.takeException(), isNull);
  });
}
