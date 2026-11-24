import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

/// Tester round 18 on df38af8 (reviewer F-M1): the focus returns to the very
/// node of the visible "More options" button, on every path, also at 0 items
/// and with the setup card shown.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  Future<void> show(WidgetTester tester, {int items = 4}) async {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore()..setLimit(200),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
    for (var i = 1; i <= items; i++) {
      source.copy('item $i');
    }
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

  Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
  }

  /// The primary focus is the focusable, traversable node of the IconButton
  /// with the tooltip, and sits exactly where the user sees that button.
  void expectOnVisibleMore(WidgetTester tester, String reason) {
    final n = FocusManager.instance.primaryFocus;
    expect(n, isNotNull, reason: reason);
    expect(n!.canRequestFocus, isTrue, reason: reason);
    expect(n.skipTraversal, isFalse, reason: reason);
    final button = n.context!.findAncestorWidgetOfExactType<IconButton>();
    expect(button?.tooltip, 'More options', reason: reason);
    final box = n.context!.findRenderObject()! as RenderBox;
    final seen = tester.getRect(find.byTooltip('More options'));
    final mine = box.localToGlobal(Offset.zero) & box.size;
    expect(seen.overlaps(mine), isTrue, reason: '$reason: $mine vs $seen');
    expect(n.hasPrimaryFocus, isTrue, reason: reason);
  }

  Future<void> openClear(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
  }

  final closers = <String, Future<void> Function(WidgetTester)>{
    'Cancel': (t) async {
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
    },
    'Escape': (t) => key(t, LogicalKeyboardKey.escape),
    'confirm': (t) async {
      await t.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await t.pumpAndSettle();
    },
    'auto-close': (t) async {
      service.clear();
      await t.pumpAndSettle();
    },
  };

  for (final MapEntry(key: name, value: close) in closers.entries) {
    testWidgets('after Clear closed by $name the ring is on the visible More '
        'options button', (tester) async {
      await show(tester);
      await openClear(tester);
      await close(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expectOnVisibleMore(tester, name);
    });

    testWidgets('same with the Mac setup card shown, closed by $name', (
      tester,
    ) async {
      await show(tester);
      await openClear(tester);
      source.access = PasteAccess.needsSetup;
      await tester.runAsync(() => service.recheckPasteAccess());
      await tester.pumpAndSettle();
      await close(tester);
      expectOnVisibleMore(tester, name);
    });
  }

  testWidgets('menu dismissed by Escape and by a click outside: the ring is '
      'on the visible button', (tester) async {
    await show(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.escape);
    expectOnVisibleMore(tester, 'Escape');
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 600));
    await tester.pumpAndSettle();
    expectOnVisibleMore(tester, 'outside');
  });

  testWidgets('0 items: the button is present and enabled, the menu item is '
      'disabled; Escape and a click on the disabled item both end with the '
      'ring on the button, no dialog', (tester) async {
    await show(tester, items: 0);
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.more_horiz),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNotNull, reason: 'the button is not disabled');
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.escape);
    expectOnVisibleMore(tester, 'Escape at 0');
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tapAt(const Offset(5, 600));
    await tester.pumpAndSettle();
    expectOnVisibleMore(tester, 'disabled item at 0');
  });
}
