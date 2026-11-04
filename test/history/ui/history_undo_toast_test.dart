// TB-4 on the History screen: a later toast must not take the Undo away
// before its 5 seconds are over.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('a Copy while the Undo toast is up keeps Undo for its 5 s; '
      '"Copied" shows after it', (tester) async {
    final source = FakeClipboardSource();
    final service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
    source.copy('a');
    source.copy('b');
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: HistoryScreen(service: service),
      ),
    );
    await tester.pump();
    final b = service.items.first.id;
    final a = service.items.last.id;
    await tester.tap(find.bySemanticsIdentifier('history-delete-$a'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.bySemanticsIdentifier('history-copy-$b'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Undo'), findsOneWidget, reason: 'deleted 2 s ago');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Undo'), findsOneWidget, reason: 'deleted 4 s ago');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Copied'), findsOneWidget, reason: 'queued after Undo');
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
