// F9: history rows switch at a 600 px window, as the UI spec says (not at
// 600 px of row width, which is 32 px less).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  Future<int> show(WidgetTester tester, double width) async {
    final source = FakeClipboardSource();
    final service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(service.dispose);
    source.copy('hello');
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: HistoryScreen(service: service),
      ),
    );
    await tester.pump();
    return service.items.single.id;
  }

  bool onOneLine(WidgetTester tester, int id) {
    final text = tester.getCenter(find.text('hello')).dy;
    final copy = tester
        .getCenter(find.bySemanticsIdentifier('history-copy-$id'))
        .dy;
    return (text - copy).abs() < 4;
  }

  testWidgets('a 620 px window has the wide row (buttons beside the text)', (
    tester,
  ) async {
    final id = await show(tester, 620);
    expect(onOneLine(tester, id), isTrue);
  });

  testWidgets('a 599 px window has the narrow row (buttons below)', (
    tester,
  ) async {
    final id = await show(tester, 599);
    expect(onOneLine(tester, id), isFalse);
  });
}
