import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';
import '../theme/tokens_test.dart' show contrast;

/// QA-M14-4 (WCAG 2.4.7, 1.4.11): every button on the main window shows the
/// 2 px `color.focus` ring when it has the keyboard focus, drawn outside the
/// button so it sits on the background, at 3:1 or more against it in light
/// and dark. The row focus ring (7.6:1, a 2 px border) is the model.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  setUp(() {
    source = FakeClipboardSource();
  });

  Future<KusungaTokens> show(
    WidgetTester tester,
    Brightness brightness, {
    Size size = const Size(800, 632),
  }) async {
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: HistoryHost(history: Future.value(service)),
      ),
    );
    await tester.pump();
    await tester.pump();
    return brightness == Brightness.dark
        ? KusungaTokens.dark
        : KusungaTokens.light;
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  /// The button's own Material: its shape carries the ring.
  Material materialIn(WidgetTester tester, Finder control) => tester
      .widgetList<Material>(
        find.descendant(of: control, matching: find.byType(Material)),
      )
      .first;

  BorderSide sideOf(WidgetTester tester, Finder control) {
    final shape = materialIn(tester, control).shape;
    return shape is OutlinedBorder ? shape.side : BorderSide.none;
  }

  bool hasFocus(WidgetTester tester, Finder control) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    final target = tester.element(control);
    var found = false;
    focused.visitAncestorElements((e) {
      if (e == target) found = true;
      return !found;
    });
    return found || focused == target;
  }

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }

  /// Tabs until [control] has the focus (at most 30 times).
  Future<void> tabTo(WidgetTester tester, Finder control) async {
    for (var i = 0; i < 30 && !hasFocus(tester, control); i++) {
      await tab(tester);
    }
    expect(hasFocus(tester, control), isTrue, reason: 'Tab reaches it');
  }

  void expectRing(
    WidgetTester tester,
    Finder control,
    KusungaTokens t,
    List<Color> behind,
    String what,
  ) {
    final side = sideOf(tester, control);
    expect(side.style, BorderStyle.solid, reason: '$what: a ring is drawn');
    expect(side.color, t.focus, reason: '$what: color.focus');
    expect(side.width, greaterThanOrEqualTo(2), reason: '$what: 2 px');
    expect(
      side.strokeAlign,
      BorderSide.strokeAlignOutside,
      reason: '$what: outside the button, on the background',
    );
    for (final bg in behind) {
      final ratio = contrast(side.color, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(3),
        reason: '$what: ring on $bg is ${ratio.toStringAsFixed(2)}:1',
      );
    }
  }

  void expectNoRing(WidgetTester tester, Finder control, KusungaTokens t) {
    final side = sideOf(tester, control);
    expect(
      side.style == BorderStyle.none || side.color != t.focus,
      isTrue,
      reason: 'no ring without the focus',
    );
  }

  for (final brightness in Brightness.values) {
    group('${brightness.name}:', () {
      testWidgets('New snippet', (tester) async {
        final t = await show(tester, brightness);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        final button = find.descendant(
          of: hook('snippet-new'),
          matching: find.byType(FilledButton),
        );
        expectNoRing(tester, button, t);
        await tab(tester);
        expect(hasFocus(tester, button), isTrue, reason: 'after the tab');
        expectRing(tester, button, t, [t.surface], 'New snippet');
      });

      testWidgets('snippet row actions', (tester) async {
        final t = await show(tester, brightness);
        service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
        service.snippets.save(name: 'B', content: 'b', type: SnippetType.other);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        final id = service.snippets.items.first.id;
        await tester.tap(find.text('A'));
        await tester.pump();
        for (final (hookId, what) in [
          ('snippet-copy-$id', 'Copy'),
          ('snippet-edit-$id', 'Edit'),
          ('snippet-down-$id', 'Move down'),
          ('snippet-delete-$id', 'Delete'),
        ]) {
          final button = find.descendant(
            of: hook(hookId),
            matching: find.byType(TextButton),
          );
          await tabTo(tester, button);
          // The row is "active" (hover colour) while a button in it is
          // focused; the ring must show on both backgrounds.
          expectRing(tester, button, t, [t.surface, t.surfaceHover], what);
        }
      });

      testWidgets('the More menu button under 600 px, and its items', (
        tester,
      ) async {
        final t = await show(tester, brightness, size: const Size(500, 632));
        service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        final id = service.snippets.items.first.id;
        final more = find.descendant(
          of: hook('snippet-more-$id'),
          matching: find.byType(IconButton),
        );
        await tester.tap(find.text('A'));
        await tester.pump();
        await tabTo(tester, more);
        expectRing(tester, more, t, [t.surface, t.surfaceHover], 'More');

        // A menu item shows its focus as a fill of color.selection (3:1 on
        // the menu, text 4.5:1 on it).
        await tester.tap(more);
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(find.text('Delete').last));
        final menu = theme.popupMenuTheme.color!;
        expect(theme.focusColor, t.selection);
        expect(contrast(theme.focusColor, menu), greaterThanOrEqualTo(3));
        expect(contrast(t.text, theme.focusColor), greaterThanOrEqualTo(4.5));
      });

      testWidgets('editor Cancel and Save, and the discard dialog', (
        tester,
      ) async {
        final t = await show(tester, brightness);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: hook('snippet-new'),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        final save = find.widgetWithText(FilledButton, 'Save');
        expectNoRing(tester, cancel, t);
        await tabTo(tester, cancel);
        expectRing(tester, cancel, t, [t.surface], 'Cancel');
        await tabTo(tester, save);
        expectRing(tester, save, t, [t.surface], 'Save');

        // Something changed: Cancel asks first.
        await tester.enterText(find.byType(TextField).first, 'x');
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        final dialog = materialIn(tester, find.byType(AlertDialog)).color!;
        final keep = find.widgetWithText(TextButton, 'Keep editing');
        final discard = find.widgetWithText(TextButton, 'Discard');
        expect(hasFocus(tester, keep), isTrue);
        expectRing(tester, keep, t, [dialog], 'Keep editing');
        await tabTo(tester, discard);
        expectRing(tester, discard, t, [dialog], 'Discard');
      });

      testWidgets('the Undo in the "Snippet deleted" toast', (tester) async {
        await show(tester, brightness);
        service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        await tester.tap(find.text('A'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        final undo = find.widgetWithText(TextButton, 'Undo');
        final toast = materialIn(tester, find.byType(SnackBar)).color!;
        await tabTo(tester, undo);
        await tester.pump(const Duration(milliseconds: 300)); // colour change
        // On the dark toast the ring colour would be lost, so the focused
        // Undo is filled with the toast's text colour instead.
        final fill = materialIn(tester, undo).color!;
        final text = tester
            .widget<DefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text('Undo'),
                    matching: find.byType(DefaultTextStyle),
                  )
                  .first,
            )
            .style
            .color!;
        expect(contrast(fill, toast), greaterThanOrEqualTo(3));
        expect(contrast(text, fill), greaterThanOrEqualTo(4.5));
      });

      testWidgets('History tab: row buttons and More options', (tester) async {
        final t = await show(tester, brightness);
        source.copy('first');
        source.copy('second');
        await tester.pump();
        final more = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is PopupMenuButton && w.tooltip == 'More options',
          ),
          matching: find.byType(IconButton),
        );
        await tabTo(tester, more);
        expectRing(tester, more, t, [t.surface], 'More options');
        final id = service.items.first.id;
        for (final (hookId, what) in [
          ('history-copy-$id', 'Copy'),
          ('history-save-snippet-$id', 'Save as snippet'),
          ('history-delete-$id', 'Delete'),
        ]) {
          final button = find.descendant(
            of: hook(hookId),
            matching: find.byType(TextButton),
          );
          await tabTo(tester, button);
          expectRing(tester, button, t, [t.surface, t.surfaceHover], what);
        }
      });
    });
  }

  test('the ring also meets 3:1 on the warning banners (Try again, '
      'Dismiss)', () {
    for (final t in [KusungaTokens.light, KusungaTokens.dark]) {
      expect(contrast(t.focus, t.bannerWarnBg), greaterThanOrEqualTo(3));
    }
  });
}
