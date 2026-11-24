// R2 (M1.8 review): every clear of the history drops History's waiting
// Undo and hides its toast, not only the History tab's own Clear history.
// Settings › Your data › Delete all history (and Delete everything's memory
// clear) call HistoryService.clear() from outside the History screen.
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

  Future<void> show(WidgetTester t) async {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(service.dispose);
    source.copy('row one');
    source.copy('row two');
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

  testWidgets('a delete waiting for Undo, then Delete all history from '
      'Settings: the toast goes, and Cmd+Z brings nothing back', (t) async {
    await show(t);
    await t.sendKeyEvent(LogicalKeyboardKey.delete); // the first row
    await t.pump();
    expect(service.items.length, 1);
    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // What Settings › Your data › Delete all history does once confirmed.
    expect(service.deleteAllHistory(), 1);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Undo'), findsNothing);
    expect(service.items, isEmpty);

    await cmdZ(t);
    expect(service.items, isEmpty, reason: 'the cleared item stays gone');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a change that is not a clear (a new copy) keeps the Undo '
      'waiting', (t) async {
    await show(t);
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    source.copy('row three');
    await t.pump();
    expect(find.text('Undo'), findsOneWidget);
    await cmdZ(t);
    expect(service.items.length, 3);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('the clear counter moves only when a clear works', () {
    final store = FlakyStore(MemoryHistoryStore());
    final s = HistoryService(
      store: store,
      source: FakeClipboardSource(),
      log: const NullErrorLog(),
    )..start();
    addTearDown(s.dispose);
    final before = s.clears;
    store.failClear = true;
    expect(s.clear(), isNull);
    expect(s.clears, before);
    store.failClear = false;
    expect(s.clear(), 0);
    expect(s.clears, before + 1);
  });
}
