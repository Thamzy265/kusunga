import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:kusunga/ui/focus_order.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

/// Tester round 8 on 7546d52 (QA-M14-5): Tab and Shift+Tab after every kind
/// of scroll, at the ends, with partly visible rows, after adds, deletes,
/// trims and copies, after a resize and a text-size change. Whatever has the
/// focus must be fully in view, and Enter, Delete, S and E must only ever act
/// on a row that is in view. The arrow-key focus model (H1 to H7) and the
/// picker are checked with the new Tab order.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  final scale = ValueNotifier<double>(1);
  final historyWrites = <String>[];

  void create({int limit = 5000}) {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore()..setLimit(limit),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (text) async => historyWrites.add(text),
    )..start();
  }

  setUp(() {
    scale.value = 1;
    historyWrites.clear();
    create();
  });
  tearDown(() => service.dispose());

  void fillSnippets(int n, [int from = 1]) {
    for (var i = from; i < from + n; i++) {
      final two = i.toString().padLeft(3, '0');
      service.snippets.save(
        name: 'snip $two',
        content: 'content $two',
        type: SnippetType.other,
      );
    }
  }

  void fillHistory(int n, [int from = 1]) {
    for (var i = from; i < from + n; i++) {
      source.copy('history item $i');
    }
  }

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: scale,
          builder: (context, s, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(s),
            ),
            child: child!,
          ),
        ),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> tapTab(WidgetTester tester, String id) async {
    await tester.tap(hook(id));
    await tester.pumpAndSettle();
  }

  Finder listOf(Type screen) => find.descendant(
    of: find.byType(screen),
    matching: find.byType(CustomScrollView),
  );

  Future<void> wheel(WidgetTester tester, Type screen, double dy) async {
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(listOf(screen))),
    );
    await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  String? focusedHook() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? id;
    void check(Widget w) {
      if (id == null && w is Semantics && w.properties.identifier != null) {
        id = w.properties.identifier;
      }
    }

    check(context.widget);
    context.visitAncestorElements((e) {
      check(e.widget);
      return id == null;
    });
    return id;
  }

  T? focusedWidget<T extends Widget>() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    if (context.widget is T) return context.widget as T;
    return context.findAncestorWidgetOfExactType<T>();
  }

  Size windowSize(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  Rect seenArea(WidgetTester tester, FocusNode node) {
    final box = node.context!.findRenderObject()!;
    final Object? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is RenderBox) {
      return viewport.localToGlobal(Offset.zero) & viewport.size;
    }
    return Offset.zero & windowSize(tester);
  }

  void expectFocusInView(WidgetTester tester, String step) {
    final node = FocusManager.instance.primaryFocus;
    expect(node, isNotNull, reason: '$step: nothing has the focus');
    final rect = node!.rect;
    final area = seenArea(tester, node);
    expect(
      rect.top >= area.top - 0.5 && rect.bottom <= area.bottom + 0.5,
      isTrue,
      reason: '$step: ${focusedHook()} at $rect is not fully in $area',
    );
  }

  /// Tab [n] times and Shift+Tab [n] times from [tab], checking the focus.
  Future<void> walk(
    WidgetTester tester,
    String tab,
    String label, {
    int n = 30,
  }) async {
    await tapTab(tester, tab);
    for (var i = 1; i <= n; i++) {
      await press(tester);
      expectFocusInView(tester, '$label Tab $i');
    }
    await tapTab(tester, tab);
    for (var i = 1; i <= n; i++) {
      await press(tester, shift: true);
      expectFocusInView(tester, '$label Shift+Tab $i');
    }
    expect(tester.takeException(), isNull, reason: label);
  }

  /// The id of the History or Snippets row whose own node has the focus
  /// (not one of its buttons).
  ClipItem? focusedHistoryRowItem() {
    final row = focusedWidget<HistoryRow>();
    return row != null && row.focusNode == FocusManager.instance.primaryFocus
        ? row.item
        : null;
  }

  int? focusedSnippetRowId() {
    final row = focusedWidget<SnippetRow>();
    return row != null && row.focusNode == FocusManager.instance.primaryFocus
        ? row.item.id
        : null;
  }

  int? focusedSnippetId() => focusedWidget<SnippetRow>()?.item.id;
  ClipItem? focusedHistoryItem() => focusedWidget<HistoryRow>()?.item;

  Set<int> snippetsInView(WidgetTester tester) {
    final viewport = tester.getRect(
      find.descendant(
        of: find.byType(SnippetsScreen),
        matching: find.byType(Viewport),
      ),
    );
    return {
      for (final e in find.byType(SnippetRow).evaluate())
        if (tester.getRect(find.byWidget(e.widget)).top >= viewport.top - 0.5 &&
            tester.getRect(find.byWidget(e.widget)).bottom <=
                viewport.bottom + 0.5)
          (e.widget as SnippetRow).item.id,
    };
  }

  Set<int> historyInView(WidgetTester tester) {
    final viewport = tester.getRect(
      find.descendant(
        of: find.byType(HistoryScreen),
        matching: find.byType(Viewport),
      ),
    );
    return {
      for (final e in find.byType(HistoryRow).evaluate())
        if (tester.getRect(find.byWidget(e.widget)).top >= viewport.top - 0.5 &&
            tester.getRect(find.byWidget(e.widget)).bottom <=
                viewport.bottom + 0.5)
          (e.widget as HistoryRow).item.id,
    };
  }

  // ---- every kind of scroll, both tabs ----

  final scrolls = <String, Future<void> Function(WidgetTester, Type)>{
    'wheel to the bottom': (t, s) => wheel(t, s, 30000),
    'wheel to the middle': (t, s) => wheel(t, s, 900),
    'wheel to the bottom then back to the top': (t, s) async {
      await wheel(t, s, 30000);
      await wheel(t, s, -30000);
    },
    'wheel by a fraction of a row': (t, s) => wheel(t, s, 37),
    'drag up': (t, s) async {
      await t.drag(listOf(s), const Offset(0, -1500), warnIfMissed: false);
      await t.pumpAndSettle();
    },
    'fling': (t, s) async {
      await t.fling(
        listOf(s),
        const Offset(0, -800),
        3000,
        warnIfMissed: false,
      );
      await t.pumpAndSettle();
    },
    'End key': (t, s) async {
      await t.tap(
        find
            .descendant(
              of: find.byType(s),
              matching: s == HistoryScreen
                  ? find.byType(HistoryRow)
                  : find.byType(SnippetRow),
            )
            .first,
        warnIfMissed: false,
      );
      await t.pump();
      await key(t, LogicalKeyboardKey.end);
    },
    'End then Home keys': (t, s) async {
      await t.tap(
        find
            .descendant(
              of: find.byType(s),
              matching: s == HistoryScreen
                  ? find.byType(HistoryRow)
                  : find.byType(SnippetRow),
            )
            .first,
        warnIfMissed: false,
      );
      await t.pump();
      await key(t, LogicalKeyboardKey.end);
      await key(t, LogicalKeyboardKey.home);
    },
    'arrow keys down 15 times': (t, s) async {
      await t.tap(
        find
            .descendant(
              of: find.byType(s),
              matching: s == HistoryScreen
                  ? find.byType(HistoryRow)
                  : find.byType(SnippetRow),
            )
            .first,
        warnIfMissed: false,
      );
      await t.pump();
      for (var i = 0; i < 15; i++) {
        await key(t, LogicalKeyboardKey.arrowDown);
      }
    },
  };

  for (final MapEntry(key: label, value: doScroll) in scrolls.entries) {
    testWidgets('Snippets after "$label": Tab and Shift+Tab keep the focus '
        'in view', (tester) async {
      fillSnippets(40);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await doScroll(tester, SnippetsScreen);
      await walk(tester, 'main-tab-snippets', label);
    });

    testWidgets('History after "$label": Tab and Shift+Tab keep the focus '
        'in view', (tester) async {
      fillHistory(60);
      await show(tester);
      await doScroll(tester, HistoryScreen);
      await walk(tester, 'main-tab-history', label);
    });
  }

  // ---- windows with partly visible rows, text sizes, resizes ----

  for (final height in [632.0, 611.0, 575.0, 480.0, 433.0, 400.0]) {
    for (final s in [1.0, 2.0]) {
      testWidgets('window ${height.toInt()} px high at ${(s * 100).toInt()}% '
          'text: both tabs, scrolled, Tab and Shift+Tab', (tester) async {
        scale.value = s;
        fillSnippets(40);
        fillHistory(60);
        await show(tester, size: Size(800, height));
        await wheel(tester, HistoryScreen, 1234);
        await walk(tester, 'main-tab-history', 'History ${height}x$s', n: 16);
        await tapTab(tester, 'main-tab-snippets');
        await wheel(tester, SnippetsScreen, 777);
        await walk(tester, 'main-tab-snippets', 'Snippets ${height}x$s', n: 16);
      });
    }
  }

  testWidgets('a window resize in the middle of a walk: the focus is in '
      'view after the next Tab or Shift+Tab', (tester) async {
    fillSnippets(40);
    await show(tester);
    await tapTab(tester, 'main-tab-snippets');
    await wheel(tester, SnippetsScreen, 900);
    await tapTab(tester, 'main-tab-snippets');
    for (var i = 0; i < 4; i++) {
      await press(tester);
    }
    tester.view.physicalSize = const Size(520, 400);
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await press(tester);
      expectFocusInView(tester, 'after the resize, Tab $i');
    }
    for (var i = 0; i < 6; i++) {
      await press(tester, shift: true);
      expectFocusInView(tester, 'after the resize, Shift+Tab $i');
    }
    tester.view.physicalSize = const Size(900, 700);
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await press(tester);
      expectFocusInView(tester, 'after growing, Tab $i');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('BUG-T2: a text-size change while a Snippets control has the '
      'focus: the next Shift+Tab lands on a control in view (today the '
      'focused row is left with no layout and Shift+Tab reaches a control '
      'out of view)', (tester) async {
    fillSnippets(40);
    await show(tester);
    await tapTab(tester, 'main-tab-snippets');
    await wheel(tester, SnippetsScreen, 900);
    await tapTab(tester, 'main-tab-snippets');
    for (var i = 0; i < 4; i++) {
      await press(tester);
    }
    tester.view.physicalSize = const Size(520, 400);
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await press(tester);
    }
    scale.value = 2;
    await tester.pumpAndSettle();
    await press(tester, shift: true);
    expectFocusInView(tester, 'Shift+Tab after the text-size change');
    await press(tester);
    expectFocusInView(tester, 'Tab after the text-size change');
  });

  testWidgets('a text-size change set before the walk: both tabs, Tab and '
      'Shift+Tab are in view', (tester) async {
    fillSnippets(40);
    fillHistory(40);
    await show(tester, size: const Size(520, 480));
    scale.value = 2;
    await tester.pumpAndSettle();
    await walk(tester, 'main-tab-history', 'History at 200%', n: 14);
    await tapTab(tester, 'main-tab-snippets');
    await wheel(tester, SnippetsScreen, 700);
    await walk(tester, 'main-tab-snippets', 'Snippets at 200%', n: 14);
  });

  testWidgets('Snippets: the focused row wheel-scrolled away (it is '
      'disposed), then Tab, Shift+Tab, Enter, Delete and E never reach a '
      'hidden row', (tester) async {
    fillSnippets(60);
    await show(tester);
    await tapTab(tester, 'main-tab-snippets');
    await tester.tap(find.byType(SnippetRow).at(2));
    await tester.pump();
    expect(focusedSnippetId(), isNotNull);
    await wheel(tester, SnippetsScreen, 6000);
    final before = [for (final s in service.snippets.items) s.id];
    for (var i = 0; i < 10; i++) {
      await press(tester, shift: i.isOdd);
      final id = focusedSnippetId();
      if (id != null) {
        expect(snippetsInView(tester), contains(id), reason: 'step $i');
      }
      expectFocusInView(tester, 'step $i after the wheel');
    }
    await tapTab(tester, 'main-tab-snippets');
    await key(tester, LogicalKeyboardKey.delete);
    await key(tester, LogicalKeyboardKey.keyE);
    await key(tester, LogicalKeyboardKey.enter);
    expect([for (final s in service.snippets.items) s.id], before);
    expect(source.ownWrites, isEmpty);
    expect(find.text('Edit snippet'), findsNothing);
  });

  // ---- adds, deletes, trims, copies ----

  testWidgets('Snippets: after an add, a delete and a move while scrolled, '
      'Tab stays in view', (tester) async {
    fillSnippets(40);
    await show(tester);
    await tapTab(tester, 'main-tab-snippets');
    await wheel(tester, SnippetsScreen, 900);
    fillSnippets(3, 100);
    await tester.pumpAndSettle();
    await walk(tester, 'main-tab-snippets', 'after adds', n: 14);
    service.snippets.delete(service.snippets.items[5].id);
    service.snippets.delete(service.snippets.items.last.id);
    await tester.pumpAndSettle();
    await walk(tester, 'main-tab-snippets', 'after deletes', n: 14);
    service.snippets.move(service.snippets.items.first.id, 20);
    await tester.pumpAndSettle();
    await walk(tester, 'main-tab-snippets', 'after a move', n: 14);
  });

  testWidgets('History: copies arriving while scrolled, then Tab', (
    tester,
  ) async {
    fillHistory(60);
    await show(tester);
    await wheel(tester, HistoryScreen, 900);
    for (var i = 0; i < 5; i++) {
      source.copy('fresh $i');
      await tester.pumpAndSettle();
    }
    await walk(tester, 'main-tab-history', 'after copies', n: 14);
  });

  testWidgets('History: a full list that trims on every copy, scrolled to '
      'the bottom, then Tab and Shift+Tab', (tester) async {
    service.dispose();
    create(limit: 30);
    fillHistory(30);
    await show(tester);
    await wheel(tester, HistoryScreen, 30000);
    for (var i = 0; i < 4; i++) {
      source.copy('fresh $i'); // trims the oldest each time
      await tester.pumpAndSettle();
    }
    await walk(tester, 'main-tab-history', 'after trims', n: 14);
  });

  testWidgets('History: a row deleted through its Delete key while the list '
      'is scrolled, then Tab', (tester) async {
    fillHistory(60);
    await show(tester);
    await wheel(tester, HistoryScreen, 900);
    await tapTab(tester, 'main-tab-history');
    await press(tester);
    await press(tester);
    while (focusedHistoryItem() == null) {
      await press(tester);
    }
    final id = focusedHistoryItem()!.id;
    await key(tester, LogicalKeyboardKey.delete);
    expect(service.items.any((e) => e.id == id), isFalse);
    await walk(tester, 'main-tab-history', 'after a delete', n: 14);
  });

  // ---- Enter, Delete, S, E only act on a row in view ----

  group('keys act only on a row in view', () {
    for (final dy in [30000.0, 3300.0]) {
      testWidgets('Snippets scrolled by $dy: Tab to a row, then Enter copies, '
          'E edits, Delete deletes that visible row', (tester) async {
        fillSnippets(40);
        await show(tester);
        await tapTab(tester, 'main-tab-snippets');
        await wheel(tester, SnippetsScreen, dy);
        await tapTab(tester, 'main-tab-snippets');
        var guard = 0;
        while (focusedSnippetRowId() == null && guard++ < 40) {
          await press(tester);
        }
        final id = focusedSnippetRowId();
        expect(id, isNotNull);
        expect(snippetsInView(tester), contains(id));
        await key(tester, LogicalKeyboardKey.enter);
        expect(source.ownWrites, [service.snippets.textOf(id!)]);
        await key(tester, LogicalKeyboardKey.keyE);
        expect(find.text('Edit snippet'), findsOneWidget);
        expect(
          find.widgetWithText(
            TextField,
            service.snippets.items.firstWhere((s) => s.id == id).name,
          ),
          findsWidgets,
        );
        await key(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        // Back on a row (focus returns to it after the editor).
        final again = focusedSnippetRowId();
        if (again != null) {
          expect(snippetsInView(tester), contains(again));
          final before = service.snippets.items.length;
          await key(tester, LogicalKeyboardKey.delete);
          expect(service.snippets.items.length, before - 1);
          expect(service.snippets.items.any((s) => s.id == again), isFalse);
        }
      });

      testWidgets('History scrolled by $dy: Tab to a row, then Enter copies, '
          'S saves as a snippet, Delete deletes that visible row', (
        tester,
      ) async {
        fillHistory(60);
        await show(tester);
        await wheel(tester, HistoryScreen, dy);
        await tapTab(tester, 'main-tab-history');
        var guard = 0;
        while (focusedHistoryRowItem() == null && guard++ < 40) {
          await press(tester);
        }
        final item = focusedHistoryRowItem();
        expect(item, isNotNull);
        expect(historyInView(tester), contains(item!.id));
        await key(tester, LogicalKeyboardKey.enter);
        expect(historyWrites, [item.preview]);
        await key(tester, LogicalKeyboardKey.keyS);
        expect(find.text('New snippet'), findsWidgets);
        expect(find.widgetWithText(TextField, item.preview), findsWidgets);
        await key(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final again = focusedHistoryRowItem();
        if (again != null) {
          expect(historyInView(tester), contains(again.id));
          final before = service.items.length;
          await key(tester, LogicalKeyboardKey.delete);
          expect(service.items.length, before - 1);
          expect(service.items.any((e) => e.id == again.id), isFalse);
        }
      });
    }

    testWidgets('after a wheel scroll that disposes the focused History row '
        '(the focus waits on the screen node), Tab, Enter, Delete, S, E '
        'never touch a hidden row', (tester) async {
      fillHistory(60);
      await show(tester);
      await tester.tap(find.byType(HistoryRow).first);
      await tester.pump();
      await wheel(tester, HistoryScreen, 6000);
      expect(focusedHistoryItem(), isNull);
      final ids = [for (final i in service.items) i.id];
      for (var i = 0; i < 12; i++) {
        await press(tester);
        final item = focusedHistoryItem();
        if (item != null) {
          expect(historyInView(tester), contains(item.id), reason: 'Tab $i');
        }
        expectFocusInView(tester, 'Tab $i after the wheel');
      }
      await tapTab(tester, 'main-tab-history');
      for (final k in [
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.backspace,
      ]) {
        await key(tester, k);
      }
      expect(
        [for (final i in service.items) i.id],
        ids,
        reason: 'a key changed the history',
      );
    });
  });

  // ---- entering a list at a partly visible row ----

  testWidgets('BUG-T1 (Snippets): from the header, the first Tab into the '
      'list focuses a row that is fully in view (today it can focus the '
      'Copy button of a row cut off at the top)', (tester) async {
    fillSnippets(40);
    await show(tester);
    await tapTab(tester, 'main-tab-snippets');
    await wheel(tester, SnippetsScreen, 900);
    await tapTab(tester, 'main-tab-snippets');
    await press(tester); // New snippet
    await press(tester); // into the list
    final id = focusedSnippetId();
    expect(id, isNotNull);
    expect(
      snippetsInView(tester),
      contains(id),
      reason: 'entered at row $id, which is cut off',
    );
  });

  testWidgets('BUG-T1 (History): the same', (tester) async {
    fillHistory(60);
    await show(tester);
    await wheel(tester, HistoryScreen, 900);
    await tapTab(tester, 'main-tab-history');
    var guard = 0;
    while (focusedHistoryItem() == null && guard++ < 10) {
      await press(tester);
    }
    final item = focusedHistoryItem();
    expect(item, isNotNull);
    expect(
      historyInView(tester),
      contains(item!.id),
      reason: 'entered at item ${item.id}, which is cut off',
    );
  });

  // ---- the arrow-key model with the new Tab order ----

  group('arrow keys and Tab together', () {
    testWidgets('Snippets: Tab into the list, Down, End, Home, then '
        'Shift+Tab and Tab go to the neighbours in order, in view', (
      tester,
    ) async {
      fillSnippets(40);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 900);
      await tapTab(tester, 'main-tab-snippets');
      while (focusedSnippetId() == null) {
        await press(tester);
      }
      final first = focusedSnippetId()!;
      await key(tester, LogicalKeyboardKey.arrowDown);
      final items = service.snippets.items;
      expect(
        focusedSnippetId(),
        items[items.indexWhere((s) => s.id == first) + 1].id,
      );
      expectFocusInView(tester, 'Down after Tab');
      await key(tester, LogicalKeyboardKey.end);
      expect(focusedSnippetId(), items.last.id);
      expectFocusInView(tester, 'End');
      await press(tester, shift: true);
      expectFocusInView(tester, 'Shift+Tab after End');
      await key(tester, LogicalKeyboardKey.home);
      expect(focusedSnippetId(), items.first.id);
      expectFocusInView(tester, 'Home');
      await press(tester);
      expectFocusInView(tester, 'Tab after Home');
      expect(tester.takeException(), isNull);
    });

    testWidgets('History: the same, with a copy arriving in between', (
      tester,
    ) async {
      fillHistory(60);
      await show(tester);
      await tapTab(tester, 'main-tab-history');
      while (focusedHistoryItem() == null) {
        await press(tester);
      }
      final a = focusedHistoryItem()!.id;
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectFocusInView(tester, 'Down after Tab');
      source.copy('fresh');
      await tester.pumpAndSettle();
      expect(focusedHistoryItem(), isNotNull);
      expectFocusInView(tester, 'after a copy');
      await key(tester, LogicalKeyboardKey.end);
      expect(focusedHistoryItem()!.id, service.items.last.id);
      await press(tester);
      expectFocusInView(tester, 'Tab after End');
      await key(tester, LogicalKeyboardKey.home);
      await press(tester, shift: true);
      expectFocusInView(tester, 'Shift+Tab after Home');
      expect(service.items.any((e) => e.id == a), isTrue);
    });

    testWidgets('a mouse click on a row, then Tab and Shift+Tab, are in '
        'order and in view (Snippets)', (tester) async {
      fillSnippets(40);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 900);
      final row = find.byType(SnippetRow).at(3);
      final id = (tester.widget(row) as SnippetRow).item.id;
      await tester.tap(row);
      await tester.pump();
      expect(focusedSnippetId(), id);
      await press(tester);
      expectFocusInView(tester, 'Tab after a click');
      await press(tester, shift: true);
      expectFocusInView(tester, 'Shift+Tab after a click');
    });
  });

  // ---- 0, 1, a screenful of rows ----

  group('lists of 0, 1 and about one screenful', () {
    testWidgets('empty Snippets and empty History: Tab and Shift+Tab cycle '
        'without exceptions', (tester) async {
      await show(tester);
      await walk(tester, 'main-tab-history', 'empty History', n: 8);
      await tapTab(tester, 'main-tab-snippets');
      await walk(tester, 'main-tab-snippets', 'empty Snippets', n: 8);
    });

    testWidgets('how many rows fit: n-1, n, n+1 and n+2 snippets', (
      tester,
    ) async {
      fillSnippets(60);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      final fit = snippetsInView(tester).length;
      expect(fit, greaterThan(3));
      for (final n in [1, 2, fit - 1, fit, fit + 1, fit + 2]) {
        service.dispose();
        create();
        fillSnippets(n);
        await tester.pumpWidget(const SizedBox());
        await show(tester);
        await tapTab(tester, 'main-tab-snippets');
        await walk(tester, 'main-tab-snippets', '$n snippets', n: n + 6);
      }
    });

    testWidgets('how many rows fit: n-1, n, n+1 and n+2 history items', (
      tester,
    ) async {
      fillHistory(60);
      await show(tester);
      final fit = historyInView(tester).length;
      expect(fit, greaterThan(3));
      for (final n in [1, 2, fit - 1, fit, fit + 1, fit + 2]) {
        service.dispose();
        create();
        fillHistory(n);
        await tester.pumpWidget(const SizedBox());
        await show(tester);
        await walk(tester, 'main-tab-history', '$n items', n: n + 6);
      }
    });

    testWidgets('one snippet, Tab then Enter copies it, Shift+Tab goes back '
        'out', (tester) async {
      fillSnippets(1);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await press(tester); // New snippet
      await press(tester); // the row
      expect(focusedSnippetId(), service.snippets.items.single.id);
      await key(tester, LogicalKeyboardKey.enter);
      expect(source.ownWrites, hasLength(1));
      await press(tester, shift: true);
      expect(focusedSnippetId(), isNull);
      expectFocusInView(tester, 'Shift+Tab out of a one-row list');
    });
  });

  // ---- the picker ----

  group('the picker window is unaffected', () {
    late FakePickerPort port;
    late PickerController controller;

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      port = FakePickerPort();
      controller = PickerController(port: port, log: FakeLog(), isMac: true);
      await controller.start();
      await controller.attach(service);
      await tester.pumpWidget(
        KusungaApp(history: Future.value(service), picker: controller),
      );
      await tester.pump();
      await tester.pump();
      addTearDown(controller.dispose);
    }

    testWidgets('no list traversal policy inside the picker panel, and the '
        'search field keeps the focus', (tester) async {
      fillHistory(30);
      await pumpApp(tester);
      port.press();
      await tester.pump();
      await tester.pump();
      expect(find.byType(PickerPanel), findsOneWidget);
      final groups = tester.widgetList<FocusTraversalGroup>(
        find.descendant(
          of: find.byType(PickerPanel),
          matching: find.byType(FocusTraversalGroup),
        ),
      );
      expect(groups.where((g) => g.policy is ListTraversalPolicy), isEmpty);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
        reason: 'the search field has the focus',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('manage mode with the picker settings: Tab visits the '
        'header, then the Keep field, the picker settings, then the rows, '
        'in that order', (tester) async {
      fillHistory(30);
      await pumpApp(tester);
      // The first history row has the focus at the start. Shift+Tab walks
      // back up through the panel's top (Keep, More options, the picker
      // settings) to the header's tabs.
      final seen = <String?>[];
      for (var i = 0; i < 14; i++) {
        await press(tester, shift: true);
        seen.add(focusedHook());
        expectFocusInView(tester, 'Shift+Tab $i');
      }
      expect(seen, contains('main-tab-snippets'), reason: '$seen');
      expect(seen, contains('shortcut-change'), reason: '$seen');
      expect(
        seen.indexOf('shortcut-change'),
        lessThan(seen.indexOf('main-tab-snippets')),
        reason: 'the picker settings come before the header going up: $seen',
      );
      for (var i = 0; i < 14; i++) {
        await press(tester);
        expectFocusInView(tester, 'Tab back $i');
      }
      expect(tester.takeException(), isNull);
    });
  });
}
