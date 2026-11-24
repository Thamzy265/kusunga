// M1.8 tester, R2 re-check: the waiting Undo after clears that come from
// outside the History screen. Memory store only.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  late FlakyStore store;

  Future<void> show(WidgetTester t) async {
    source = FakeClipboardSource();
    store = FlakyStore(MemoryHistoryStore());
    service = HistoryService(
      store: store,
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(service.dispose);
    source.copy('row one');
    source.copy('row two');
    source.copy('row three');
    await t.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await t.pump();
  }

  Future<void> cmdZ(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
  }

  List<String> shown() => service.items.map((i) => i.preview).toList();

  testWidgets('delete A, clear, delete B: Cmd+Z brings back B only, and A '
      'is gone for good', (t) async {
    await show(t);
    await t.sendKeyEvent(LogicalKeyboardKey.delete); // the newest row
    await t.pump();
    expect(shown(), ['row two', 'row one']);
    expect(service.deleteAllHistory(), 2);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Undo'), findsNothing);
    source.copy('row four');
    source.copy('row five');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.delete); // row five
    await t.pump();
    expect(find.text('Undo'), findsOneWidget);
    await cmdZ(t);
    expect(shown(), ['row five', 'row four']);
    expect(shown(), isNot(contains('row three')));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a clear that fails keeps the Undo waiting and working', (
    t,
  ) async {
    await show(t);
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    store.failClear = true;
    expect(service.deleteAllHistory(), isNull);
    await t.pump();
    expect(find.text('Undo'), findsOneWidget);
    store.failClear = false;
    await cmdZ(t);
    expect(shown(), hasLength(3));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('tapping the toast\'s Undo button works before a clear, and '
      'there is no button after it', (t) async {
    await show(t);
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Undo'));
    await t.pump();
    expect(shown(), hasLength(3));
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    service.clear();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Undo'), findsNothing);
    expect(shown(), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
