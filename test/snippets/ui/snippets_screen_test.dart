import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../snippet_service_test.dart' show FlakySnippetStore;
import '../../support/fakes.dart';
import '../../support/row_hover.dart';

void main() {
  late FlakySnippetStore store;
  late SnippetService service;
  late FakeLog log;
  late List<String> copied;
  late GlobalKey<SnippetsScreenState> key;
  const now = 1000000000;

  SnippetService make({bool editable = true}) => SnippetService(
    store: store,
    log: log,
    editable: editable,
    clock: () => now - 2 * 86400000,
    writeClipboard: (text) async {
      copied.add(text);
      return true;
    },
  );

  setUp(() {
    store = FlakySnippetStore();
    log = FakeLog();
    copied = [];
    service = make();
    key = GlobalKey<SnippetsScreenState>();
  });

  void add(String name, String content, [SnippetType? type]) => service.save(
    name: name,
    content: content,
    type: type ?? suggestType(content),
  );

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: SnippetsScreen(key: key, service: service, now: () => now),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  String? labelOf(WidgetTester tester, String id) =>
      tester.widget<Semantics>(hook(id)).properties.label;

  List<String> names() => service.items.map((s) => s.name).toList();

  int idOf(String name) => service.items.firstWhere((s) => s.name == name).id;

  Future<void> focusRow(WidgetTester tester, String name) async {
    // A click on the row's text (not on a row button) focuses the row.
    await tester.tap(find.text(name));
    await tester.pump();
  }

  Future<void> altKey(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(k);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  }

  group('list', () {
    testWidgets('rows in the user order: name, content, edited time', (
      tester,
    ) async {
      add('My mobile', '07700 900123');
      add('Work email', 'will@example.com');
      await show(tester);
      expect(find.text('My mobile'), findsOneWidget);
      expect(find.text('07700 900123'), findsOneWidget);
      expect(find.text('edited 2 days ago'), findsNWidgets(2));
      expect(find.text('2 snippets'), findsOneWidget);
      final a = tester.getTopLeft(find.text('My mobile'));
      final b = tester.getTopLeft(find.text('Work email'));
      expect(a.dy, lessThan(b.dy));
    });

    testWidgets('accessible names say which snippet each button acts on', (
      tester,
    ) async {
      add('My mobile', '07700 900123');
      add('Work email', 'will@example.com');
      await show(tester);
      final id = idOf('My mobile');
      expect(
        labelOf(tester, 'snippet-row-$id'),
        'My mobile, Phone, 07700 900123',
      );
      expect(labelOf(tester, 'snippet-copy-$id'), 'Copy My mobile');
      expect(labelOf(tester, 'snippet-edit-$id'), 'Edit My mobile');
      expect(labelOf(tester, 'snippet-down-$id'), 'Move My mobile down');
      expect(labelOf(tester, 'snippet-delete-$id'), 'Delete My mobile');
    });

    testWidgets('Move up is not on the first row, Move down not on the last', (
      tester,
    ) async {
      add('A', 'a');
      add('B', 'b');
      await show(tester);
      expect(hook('snippet-up-${idOf('A')}'), findsNothing);
      expect(hook('snippet-down-${idOf('A')}'), findsOneWidget);
      expect(hook('snippet-up-${idOf('B')}'), findsOneWidget);
      expect(hook('snippet-down-${idOf('B')}'), findsNothing);
    });

    testWidgets('empty: the copy and a New snippet button', (tester) async {
      await show(tester);
      expect(find.text('No snippets yet'), findsOneWidget);
      expect(
        find.text(
          'Save things you paste often, like your phone number or email.',
        ),
        findsOneWidget,
      );
      expect(hook('snippet-new-empty'), findsOneWidget);
      expect(find.text('0 snippets'), findsOneWidget);
    });

    testWidgets('long name and content are cut to one line each', (
      tester,
    ) async {
      add('n' * 100, 'c' * 5000);
      await show(tester, size: const Size(360, 400));
      expect(tester.takeException(), isNull);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        if ((t.data ?? '').startsWith('nnnn') ||
            (t.data ?? '').startsWith('cccc')) {
          expect(t.maxLines, 1);
          expect(t.overflow, TextOverflow.ellipsis);
        }
      }
    });
  });

  group('keyboard', () {
    testWidgets('Up/Down move the focus, Enter copies', (tester) async {
      add('A', 'aaa');
      add('B', 'bbb');
      await show(tester);
      await focusRow(tester, 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(copied, ['bbb']);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('Alt+Down moves the snippet, keeps focus on it, and says '
        'where it went', (tester) async {
      add('My mobile', '1');
      add('B', '2');
      add('C', '3');
      add('D', '4');
      await show(tester);
      await focusRow(tester, 'My mobile');
      await altKey(tester, LogicalKeyboardKey.arrowDown);
      expect(names(), ['B', 'My mobile', 'C', 'D']);
      expect(Focus.of(tester.element(find.text('My mobile'))).hasFocus, isTrue);
      final note = tester.widget<Semantics>(
        find.byKey(const ValueKey('snippet-move-announcement')),
      );
      expect(note.properties.label, 'My mobile, moved to position 2 of 4');
      await altKey(tester, LogicalKeyboardKey.arrowUp);
      expect(names(), ['My mobile', 'B', 'C', 'D']);
    });

    testWidgets('E and F2 edit; Delete removes with Undo', (tester) async {
      add('A', 'a');
      add('B', 'b');
      await show(tester);
      await focusRow(tester, 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      expect(find.text('Edit snippet'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Edit snippet'), findsNothing);
      await focusRow(tester, 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('Edit snippet'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await focusRow(tester, 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(names(), ['B']);
      expect(find.text('Snippet deleted'), findsOneWidget);
      // Focus goes to the next row.
      await tester.pump();
      expect(Focus.of(tester.element(find.text('B'))).hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(names(), ['A', 'B']);
    });

    testWidgets('deleting the last row moves focus to the previous one', (
      tester,
    ) async {
      add('A', 'a');
      add('B', 'b');
      await show(tester);
      await focusRow(tester, 'B');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      await tester.pump();
      expect(Focus.of(tester.element(find.text('A'))).hasFocus, isTrue);
    });

    testWidgets('Undo goes after 5 seconds', (tester) async {
      add('A', 'a');
      await show(tester);
      await focusRow(tester, 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Undo'), findsOneWidget, reason: 'still there at 4.5 s');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      expect(service.items, isEmpty);
    });
  });

  testWidgets('delete A, Copy, delete B: the Undo for B shows at once and '
      'brings back B (F4)', (tester) async {
    add('A', 'a');
    add('B', 'b');
    add('C', 'c');
    await show(tester);
    await clickRowAction(tester, hook('snippet-delete-${idOf('A')}'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await clickRowAction(tester, hook('snippet-copy-${idOf('C')}'));
    await tester.pump();
    await clickRowAction(tester, hook('snippet-delete-${idOf('B')}'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Copied'), findsNothing);
    expect(find.text('Snippet deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(names(), ['B', 'C']);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(
      find.text('Copied'),
      findsNothing,
      reason: 'the stale toast is gone',
    );
  });

  group('buttons', () {
    testWidgets('Move down by button keeps the order and focus', (
      tester,
    ) async {
      add('A', 'a');
      add('B', 'b');
      await show(tester);
      await clickRowAction(tester, hook('snippet-down-${idOf('A')}'));
      await tester.pump();
      expect(names(), ['B', 'A']);
    });

    testWidgets('a failed move keeps the old order and says so', (
      tester,
    ) async {
      add('A', 'a');
      add('B', 'b');
      await show(tester);
      store.failWrites = true;
      await clickRowAction(tester, hook('snippet-down-${idOf('A')}'));
      await tester.pump();
      expect(names(), ['A', 'B']);
      expect(
        find.text("Couldn't move the snippet. Try again."),
        findsOneWidget,
      );
      expect(log.codes, [LogCode.snippetMoveFailed]);
    });

    testWidgets('a failed delete keeps the row and says so', (tester) async {
      add('A', 'a');
      await show(tester);
      store.failWrites = true;
      await clickRowAction(tester, hook('snippet-delete-${idOf('A')}'));
      await tester.pump();
      expect(names(), ['A']);
      expect(
        find.text("Couldn't delete the snippet. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('Edit opens the editor filled in, and Save shows a toast', (
      tester,
    ) async {
      add('A', 'aaa');
      await show(tester);
      await clickRowAction(tester, hook('snippet-edit-${idOf('A')}'));
      await tester.pumpAndSettle();
      expect(find.text('Edit snippet'), findsOneWidget);
      await tester.tap(hook('snippet-editor-save'));
      await tester.pumpAndSettle();
      expect(find.text('Snippet saved'), findsOneWidget);
      // The edited row is selected.
      expect(Focus.of(tester.element(find.text('A'))).hasFocus, isTrue);
    });

    testWidgets('New snippet from the empty state saves and selects the row', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(hook('snippet-new-empty'));
      await tester.pumpAndSettle();
      expect(find.text('New snippet'), findsWidgets);
      await tester.enterText(
        find.descendant(
          of: hook('snippet-editor-name'),
          matching: find.byType(TextField),
        ),
        'Home',
      );
      await tester.enterText(
        find.descendant(
          of: hook('snippet-editor-content'),
          matching: find.byType(TextField),
        ),
        '1 High Street',
      );
      await tester.tap(hook('snippet-editor-save'));
      await tester.pumpAndSettle();
      expect(names(), ['Home']);
      expect(find.text('Snippet saved'), findsOneWidget);
      expect(Focus.of(tester.element(find.text('Home'))).hasFocus, isTrue);
    });
  });

  group('memory-only or incompatible', () {
    testWidgets('the banner shows; Edit, Move and Delete are off; Copy works', (
      tester,
    ) async {
      store.insert(
        name: 'A',
        content: 'kept',
        type: SnippetType.other,
        nowMs: 1,
      );
      store.insert(name: 'B', content: 'b', type: SnippetType.other, nowMs: 1);
      service = make(editable: false);
      await show(tester);
      expect(
        find.text(
          "Snippets can't be opened right now, because Kusunga can't reach "
          'your keychain.',
        ),
        findsOneWidget,
      );
      final id = service.items.first.id;
      for (final h in ['edit', 'down', 'delete']) {
        final button = tester.widget<Semantics>(hook('snippet-$h-$id'));
        expect(button.properties.enabled, isFalse, reason: h);
      }
      await clickRowAction(tester, hook('snippet-copy-$id'));
      await tester.pump();
      expect(copied, ['kept']);
      // Keys do nothing either.
      await focusRow(tester, 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await altKey(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      expect(names(), ['A', 'B']);
      expect(find.text('Edit snippet'), findsNothing);
      expect(key.currentState!.canCreate, isFalse);
    });
  });

  testWidgets('a read error shows the banner with Try again', (tester) async {
    store.failReads = true;
    service = make();
    await show(tester);
    expect(
      find.text("Kusunga couldn't read your snippets. Try again."),
      findsOneWidget,
    );
    store.failReads = false;
    store.insert(name: 'A', content: 'a', type: SnippetType.other, nowMs: 1);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    expect(
      find.text("Kusunga couldn't read your snippets. Try again."),
      findsNothing,
    );
  });

  group('narrow', () {
    testWidgets('under 600 px the row actions are in a More menu', (
      tester,
    ) async {
      add('My mobile', '07700 900123');
      add('B', 'b');
      await show(tester, size: const Size(400, 600));
      final id = idOf('My mobile');
      expect(hook('snippet-edit-$id'), findsNothing);
      expect(labelOf(tester, 'snippet-more-$id'), 'More actions for My mobile');
      await tester.tap(hook('snippet-more-$id'));
      await tester.pumpAndSettle();
      for (final item in ['Copy', 'Edit', 'Move down', 'Delete']) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      expect(find.text('Move up'), findsNothing);
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(names(), ['B', 'My mobile']);
    });

    for (final b in Brightness.values) {
      testWidgets('360 px at 200% text has no overflow ($b)', (tester) async {
        add('My mobile', '07700 900123');
        store.failReads = false;
        await show(
          tester,
          size: const Size(360, 400),
          textScale: 2,
          brightness: b,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('every button has a label and is at least 24 px', (tester) async {
    add('My mobile', '07700 900123');
    add('B', 'b');
    await show(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(
      tester,
      meetsGuideline(
        const MinimumTapTargetGuideline(size: Size(24, 24), link: ''),
      ),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  test('the cap is 1,000', () => expect(SnippetStore.maxCount, 1000));
}
