import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../snippet_service_test.dart' show FlakySnippetStore;
import '../../support/fakes.dart';

/// QA-M14-3: from 600 to about 700 px the rows kept the room of the hidden
/// row actions, and the name had at most half of what was left, so names
/// were cut ("QA Work ...") while half the row was empty. The name now uses
/// the free space, and is cut only when there is no room (UI spec, "Long
/// content"). The 600 px switch to the More menu (F9) stays.
void main() {
  late SnippetService service;

  setUp(() {
    service = SnippetService(
      store: FlakySnippetStore(),
      log: FakeLog(),
      editable: true,
      clock: () => 0,
      writeClipboard: (_) async => true,
    );
  });

  void add(String name, String content) =>
      service.save(name: name, content: content, type: suggestType(content));

  void addQaSnippets() {
    // QA's names and contents from session 3.
    add('QA Mobile', '07700 900123');
    add('QA Work email', 'test@example.com');
    add('QA Meeting link', 'https://example.com/meet/qa-123');
    add('QA Home address', 'Street\nTesttown\nTE1 1ST');
  }

  Future<void> show(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: SnippetsScreen(service: service, now: () => 60000),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  bool cut(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  for (final width in [600.0, 640.0, 699.0]) {
    testWidgets('at ${width.toInt()} px no name or content is cut while the '
        'row has room', (tester) async {
      addQaSnippets();
      await show(tester, width);
      expect(tester.takeException(), isNull);
      for (final s in service.items) {
        expect(cut(tester, s.name), isFalse, reason: '"${s.name}" is cut');
      }
      expect(cut(tester, 'https://example.com/meet/qa-123'), isFalse);
      expect(find.byIcon(Icons.more_horiz), findsNothing, reason: 'F9: 600+');
    });
  }

  testWidgets('a long name runs to the end of the row (no reserved gap)', (
    tester,
  ) async {
    add('N' * 80, 'short');
    await show(tester, 600);
    final id = service.items.single.id;
    final row = tester.getRect(find.byKey(ValueKey('snippet-row-box-$id')));
    final name = tester.getRect(find.text('N' * 80));
    final content = tester.getRect(find.text('short'));
    expect(cut(tester, 'N' * 80), isTrue, reason: 'too long for any row');
    // The name may leave room for the edited time (at most 40%), but no
    // longer for the hidden buttons.
    expect(name.width, greaterThan((row.right - content.left) * 0.55));
  });

  testWidgets('hover or focus shows the buttons, which take the room they '
      'need and work; nothing overflows', (tester) async {
    addQaSnippets();
    await show(tester, 600);
    final id = service.items.first.id;
    await tester.tap(find.text('QA Mobile'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final copy = hook('snippet-copy-$id');
    final row = tester.getRect(find.byKey(ValueKey('snippet-row-box-$id')));
    final copyRect = tester.getRect(copy);
    final name = tester.getRect(find.text('QA Mobile'));
    expect(copyRect.left, greaterThanOrEqualTo(name.right));
    expect(copyRect.right, lessThanOrEqualTo(row.right));
    // Tab still goes from the row to its buttons.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      Focus.of(
        tester.element(find.descendant(of: copy, matching: find.text('Copy'))),
      ).hasPrimaryFocus,
      isTrue,
    );
  });

  testWidgets('hidden buttons take no clicks: a click on the row end '
      'focuses the row and deletes nothing', (tester) async {
    addQaSnippets();
    await show(tester, 640);
    final id = service.items.first.id;
    final row = tester.getRect(find.byKey(ValueKey('snippet-row-box-$id')));
    await tester.tapAt(row.centerRight - const Offset(20, 0));
    await tester.pump();
    expect(service.items.length, 4);
    expect(
      Focus.of(tester.element(find.text('QA Mobile'))).hasPrimaryFocus,
      isTrue,
    );
  });

  testWidgets('599 px still uses the More menu (F9)', (tester) async {
    addQaSnippets();
    await show(tester, 599);
    expect(find.byIcon(Icons.more_horiz), findsNWidgets(4));
    for (final s in service.items) {
      expect(cut(tester, s.name), isFalse, reason: '"${s.name}" is cut');
    }
  });
}
