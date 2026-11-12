// F10: "Save as snippet" on a history item whose whole text can't be read
// does not open the editor; it says "Couldn't open the snippet. Try again."
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

class _ReadFails extends FlakyStore {
  _ReadFails() : super(MemoryHistoryStore());
  bool fail = false;

  @override
  String? contentOf(int id, {int? notBefore}) {
    if (fail) throw StateError('read failed');
    return super.contentOf(id, notBefore: notBefore);
  }
}

void main() {
  for (final how in ['throws', 'is gone']) {
    testWidgets('the read $how: a toast, no editor, a log code', (
      tester,
    ) async {
      final store = _ReadFails();
      final log = FakeLog();
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        source: source,
        log: log,
        snippetStore: MemorySnippetStore(),
      )..start();
      addTearDown(service.dispose);
      source.copy('pin me');
      final id = service.items.single.id;
      if (how == 'throws') {
        store.fail = true;
      } else {
        store.inner.delete(id); // gone behind the list's back
      }
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
      await tester.tap(find.bySemanticsIdentifier('history-save-snippet-$id'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('snippet-editor'), findsNothing);
      expect(
        find.text("Couldn't open the snippet. Try again."),
        findsOneWidget,
      );
      expect(log.codes, contains(LogCode.snippetOpenFailed));
      expect(tester.takeException(), isNull);
      // The keyboard path says the same.
      await tester.tap(find.text('pin me'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('snippet-editor'), findsNothing);
    });
  }
}
