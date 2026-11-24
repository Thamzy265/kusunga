import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../../support/main_tabs.dart';

/// Reviewer W2: when the count of items to delete cannot be read, the Keep
/// dialog never shows a number it could not read (it showed "Delete 0
/// items" while confirm still trimmed), and the limit is never lowered
/// without the dialog (a failed read at open skipped it). While the count
/// is unknown the dialog says "Couldn't count the items. Try again." and
/// only Cancel works.
void main() {
  const unknown = "Couldn't count the items. Try again.";

  late FakeClipboardSource source;
  late _CountStore store;
  late HistoryService service;

  void make() {
    source = FakeClipboardSource();
    store = _CountStore();
    service = HistoryService(
      store: store,
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

  Future<void> setKeep(WidgetTester tester, int n) async {
    final field = find.descendant(
      of: find.byType(LimitField),
      matching: find.byType(TextField),
    );
    await showKeepField(tester);
    await tester.enterText(field, '$n');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  FilledButton deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    ),
  );

  void copies(int n, [String prefix = 'item']) {
    for (var i = 0; i < n; i++) {
      source.copy('$prefix $i');
    }
  }

  testWidgets('the read fails while the dialog is open: no number, Delete '
      'is off, Cancel keeps everything; a good read brings it back', (
    tester,
  ) async {
    make();
    copies(11);
    await show(tester);
    await setKeep(tester, 10);
    expect(find.text('Delete 1 item'), findsOneWidget);

    store.failCount = true;
    source.copy('arrives while the count cannot be read');
    await tester.pumpAndSettle();

    expect(find.text(unknown), findsOneWidget);
    expect(find.textContaining('0 older items'), findsNothing);
    expect(find.text('Delete 0 items'), findsNothing);
    expect(deleteButton(tester).onPressed, isNull, reason: 'Delete is on');

    store.failCount = false;
    source.copy('arrives when the count can be read again');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Keep only the newest 10 items? 3 older items will be deleted.',
      ),
      findsOneWidget,
    );
    expect(deleteButton(tester).onPressed, isNotNull);

    store.failCount = true;
    source.copy('fails again');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.limit, 200);
    expect(service.items.length, 14);
  });

  testWidgets('the read fails when the dialog would open: it still opens, '
      'says it could not count, and the limit is not lowered', (tester) async {
    make();
    copies(11);
    await show(tester);
    store.failCount = true;

    await setKeep(tester, 10);

    expect(find.byType(AlertDialog), findsOneWidget, reason: 'no warning');
    expect(find.text(unknown), findsOneWidget);
    expect(deleteButton(tester).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.limit, 200);
    expect(service.items.length, 11);
  });

  testWidgets('raising the limit deletes nothing, so it needs no count: no '
      'dialog even when the read fails', (tester) async {
    make();
    copies(11);
    await show(tester);
    store.failCount = true;
    await setKeep(tester, 300);
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.limit, 300);
    expect(service.items.length, 11);
  });

  test('the service reports an unknown count as null, not 0', () async {
    make();
    copies(11);
    expect(service.countRemovedBy(10), 1);
    store.failCount = true;
    expect(service.countRemovedBy(10), isNull);
    store.failCount = false;
    await service.close();
    expect(service.countRemovedBy(10), isNull);
  });
}

/// A store whose count of items to delete can be made to fail, like a
/// locked or damaged database read.
class _CountStore extends MemoryHistoryStore {
  bool failCount = false;

  @override
  int countRemovedBy(int newLimit) {
    if (failCount) throw const FileSystemException('read failed');
    return super.countRemovedBy(newLimit);
  }
}
