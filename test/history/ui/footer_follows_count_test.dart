import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

/// BUG-F1 (tester round 12): the footers ("N of L items", "N snippets", a
/// polite live region, at most one change every 2 s) keep following the
/// count. The service is made INSIDE each test: one made in setUp listens to
/// the fake clipboard outside the test's fake-async zone, so the footer's
/// 2-second timer would run on real time and never fire under tester.pump
/// (that, not the app, froze the footer in the tester's repro).
void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  void make() {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
  }

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder footer(String text) => find.text(text);

  for (final gap in [1, 5, 30]) {
    for (final start in [0, 1, 2, 10]) {
      testWidgets('History footer, $start items, copies $gap s apart', (
        tester,
      ) async {
        make();
        for (var i = 0; i < start; i++) {
          source.copy('start $i');
        }
        await show(tester);
        for (var i = 0; i < 6; i++) {
          source.copy('copy $i');
          await tester.pump(Duration(seconds: gap));
          // At most one change every 2 s: with gaps of 2 s or more every
          // copy shows by the next one.
          if (gap >= 2) {
            expect(
              footer('${service.items.length} of 200 items'),
              findsOneWidget,
              reason: 'after copy $i',
            );
          }
        }
        await tester.pump(const Duration(seconds: 3));
        expect(footer('${start + 6} of 200 items'), findsOneWidget);
      });
    }
  }

  testWidgets('History footer follows deletes 5 s apart', (tester) async {
    make();
    for (var i = 0; i < 10; i++) {
      source.copy('item $i');
    }
    await show(tester);
    for (var left = 9; left >= 5; left--) {
      service.delete(service.items.first.id);
      await tester.pump(const Duration(seconds: 5));
      expect(footer('$left of 200 items'), findsOneWidget);
    }
  });

  testWidgets('Snippets footer follows saves 5 s apart', (tester) async {
    make();
    await show(tester);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == 'main-tab-snippets',
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 1; i <= 6; i++) {
      service.snippets.save(
        name: 'snip $i',
        content: 'content $i',
        type: SnippetType.other,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(footer(i == 1 ? '1 snippet' : '$i snippets'), findsOneWidget);
    }
  });
}
