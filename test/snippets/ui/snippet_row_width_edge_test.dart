import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../snippet_service_test.dart' show FlakySnippetStore;
import '../../support/fakes.dart';
import '../../support/row_hover.dart';

/// Tester probes for QA-M14-3 (1f65843): the row layout at 600, 640, 699 and
/// 700 px, at 200% text, and on touch. Hidden row actions take no width and
/// no clicks; the name is laid out first; the edited time gets at most 40%.
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

  void addSome() {
    add('QA Mobile', '07700 900123');
    add('QA Work email', 'test@example.com');
    add('QA Meeting link', 'https://example.com/meet/qa-123');
    add('QA Home address', 'Street\nTesttown\nTE1 1ST');
  }

  Future<void> show(
    WidgetTester tester,
    double width, {
    double textScale = 1,
    double height = 632,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: SnippetsScreen(service: service, now: () => 60000),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Finder rowBox(int id) => find.byKey(ValueKey('snippet-row-box-$id'));

  bool cut(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  for (final width in [600.0, 640.0, 699.0, 700.0, 701.0]) {
    testWidgets('${width.toInt()} px: no overflow, the same layout either side '
        'of 700, the edited time in the row, hidden buttons take no clicks', (
      tester,
    ) async {
      addSome();
      await show(tester, width);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < service.items.length; i++) {
        final s = service.items[i];
        final row = tester.getRect(rowBox(s.id));
        final name = tester.getRect(find.text(s.name));
        expect(name.right, lessThanOrEqualTo(row.right + 0.5));
        expect(name.left, greaterThanOrEqualTo(row.left));
        expect(cut(tester, s.name), isFalse, reason: s.name);
        final e = tester.getRect(find.textContaining('edited ').at(i));
        expect(e.right, lessThanOrEqualTo(row.right + 0.5));
        expect(e.left, greaterThanOrEqualTo(name.right - 0.5));
        expect(find.byIcon(Icons.more_horiz), findsNothing);
      }
      // A click where a hidden Delete is drawn (it overflows its zero-width
      // box, invisible) must not delete.
      final first = service.items.first;
      final hidden = tester.getCenter(hook('snippet-delete-${first.id}'));
      await tester.tapAt(hidden);
      await tester.pump();
      expect(service.items, hasLength(4), reason: 'hidden Delete took a click');
    });
  }

  for (final width in [600.0, 640.0, 699.0, 700.0, 701.0, 1000.0]) {
    testWidgets('${width.toInt()} px at 200% text: the More menu is used '
        '(200% stands in for 320 px), nothing overflows or is cut by the '
        'buttons', (tester) async {
      addSome();
      await show(tester, width, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_horiz), findsNWidgets(4));
      for (final s in service.items) {
        final row = tester.getRect(rowBox(s.id));
        final name = tester.getRect(find.text(s.name));
        expect(name.right, lessThanOrEqualTo(row.right + 0.5));
      }
    });
  }

  testWidgets('the edited time never takes more than 40% of the first line, '
      'whatever the name', (tester) async {
    add('N' * 90, 'x');
    for (final width in [600.0, 700.0, 900.0]) {
      await show(tester, width);
      final id = service.items.single.id;
      final row = tester.getRect(rowBox(id));
      final edited = tester.getRect(find.textContaining('edited '));
      final name = tester.getRect(find.text('N' * 90));
      expect(edited.width, lessThanOrEqualTo((row.width - 40) * 0.4 + 1));
      expect(name.width, greaterThan(0));
      expect(
        edited.left,
        greaterThanOrEqualTo(name.right - 0.5),
        reason: 'no overlap at $width px',
      );
    }
  });

  testWidgets('a name of one character and a name of 100 do not overflow at '
      '200% text at 600 px', (tester) async {
    add('a', 'x');
    add('W' * 100, 'y');
    await show(tester, 600, textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus shows the buttons at 600 px and 100% text, inside the '
      'row, without overflow', (tester) async {
    addSome();
    await show(tester, 600);
    await tester.tap(find.text('QA Mobile'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final id = service.items.first.id;
    final row = tester.getRect(rowBox(id));
    expect(
      tester.getRect(hook('snippet-delete-$id')).right,
      lessThanOrEqualTo(row.right + 0.5),
    );
  });

  testWidgets('a mouse click on the far right of an idle row never hits a '
      'hidden button', (tester) async {
    addSome();
    await show(tester, 700);
    final id = service.items.first.id;
    final row = tester.getRect(rowBox(id));
    // Hover first (a real mouse is over the row), then click where Delete
    // WILL be: after the hover the buttons exist, so this hits Delete. The
    // point of this test is the order: a click without hover first does not.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.down(row.centerRight - const Offset(20, 0));
    await mouse.up();
    await tester.pump();
    expect(service.items, hasLength(4), reason: 'a jump-in click deletes none');
    await mouse.removePointer();
  });

  testWidgets('the real hover helper still reaches Delete (the buttons work '
      'once shown)', (tester) async {
    addSome();
    await show(tester, 700);
    final id = service.items.first.id;
    await clickRowAction(
      tester,
      find.descendant(
        of: hook('snippet-delete-$id'),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pump();
    expect(service.items, hasLength(3));
  });

  group('touch', () {
    for (final width in [600.0, 640.0, 700.0, 900.0]) {
      testWidgets('at ${width.toInt()} px the first tap at the far right of '
          'a row focuses it and deletes nothing', (tester) async {
        addSome();
        await show(tester, width);
        final id = service.items.first.id;
        final row = tester.getRect(rowBox(id));
        for (final dx in [4.0, 20.0, 60.0, 120.0, 200.0]) {
          // A fresh window each time, so every tap is a first tap.
          await tester.pumpWidget(const SizedBox());
          await show(tester, width);
          final at = Offset(row.right - dx, row.center.dy);
          final g = await tester.startGesture(
            at,
            kind: PointerDeviceKind.touch,
          );
          await g.up();
          await tester.pump();
          expect(service.items, hasLength(4), reason: 'dx $dx');
          expect(
            Focus.of(tester.element(find.text('QA Mobile'))).hasPrimaryFocus,
            isTrue,
            reason: 'dx $dx: the row is focused',
          );
        }
      });
    }

    testWidgets('a slow touch (down, frames pass, up) at the Delete place '
        'does not delete: the buttons that appear on focus never take the '
        'gesture', (tester) async {
      addSome();
      await show(tester, 700);
      final id = service.items.first.id;
      final row = tester.getRect(rowBox(id));
      final at = Offset(row.right - 30, row.center.dy);
      final g = await tester.startGesture(at, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pump();
      expect(service.items, hasLength(4));
    });

    testWidgets('after the first tap the buttons are shown and a second tap '
        'on one works (touch can reach every action)', (tester) async {
      addSome();
      await show(tester, 700);
      final id = service.items.first.id;
      await tester.tap(find.text('QA Mobile'), kind: PointerDeviceKind.touch);
      await tester.pump();
      final del = hook('snippet-delete-$id');
      expect(tester.getRect(del).width, greaterThan(20));
      await tester.tap(
        find.descendant(of: del, matching: find.byType(TextButton)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(service.items, hasLength(3));
    });

    testWidgets('under 600 px a touch reaches the More menu in one tap', (
      tester,
    ) async {
      addSome();
      await show(tester, 400);
      final id = service.items.first.id;
      await tester.tap(
        find.descendant(
          of: hook('snippet-more-$id'),
          matching: find.byType(IconButton),
        ),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      expect(service.items, hasLength(4));
    });

    testWidgets('a tap on the row, then a tap on another row, deletes '
        'nothing in either', (tester) async {
      addSome();
      await show(tester, 640);
      final a = tester.getRect(rowBox(service.items[0].id));
      final b = tester.getRect(rowBox(service.items[1].id));
      for (final r in [a, b, a]) {
        await tester.tapAt(r.centerRight - const Offset(10, 0));
        await tester.pump();
      }
      expect(service.items, hasLength(4));
    });
  });
}
