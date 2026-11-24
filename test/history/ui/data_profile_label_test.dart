import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../../theme/tokens_test.dart' show contrast;

/// With a test data profile the main window says so, on both tabs, so test
/// data is never mistaken for real data (PM decision 2026-11-05).
void main() {
  late HistoryService service;

  setUp(() {
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
    )..start();
  });
  tearDown(() => service.dispose());

  Finder label() => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == 'data-profile-label',
  );

  Future<void> show(WidgetTester tester, Widget home, Brightness b) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: KusungaTokens.themeData(b), home: home),
    );
    await tester.pump();
    await tester.pump();
  }

  for (final b in Brightness.values) {
    testWidgets('${b.name}: "Test profile: qa" on both tabs, readable', (
      tester,
    ) async {
      await show(
        tester,
        HistoryHost(history: Future.value(service), dataProfile: 'qa'),
        b,
      );
      expect(find.text('Test profile: qa'), findsOneWidget);
      expect(label(), findsOneWidget);
      final t = KusungaTokens.of(tester.element(find.text('Test profile: qa')));
      final text = tester.widget<Text>(find.text('Test profile: qa'));
      expect(contrast(text.style!.color!, t.bannerWarnBg), greaterThan(4.5));
      await tester.tap(find.text('Snippets'));
      await tester.pump();
      expect(find.text('Test profile: qa'), findsOneWidget);
    });
  }

  testWidgets('no profile: no label', (tester) async {
    await show(
      tester,
      HistoryHost(history: Future.value(service)),
      Brightness.light,
    );
    expect(find.textContaining('Test profile'), findsNothing);
    expect(label(), findsNothing);
  });

  testWidgets('the app passes the profile name to the main window', (
    tester,
  ) async {
    await tester.pumpWidget(
      KusungaApp(history: Future.value(service), dataProfile: 'qa'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Test profile: qa'), findsOneWidget);
  });
}
