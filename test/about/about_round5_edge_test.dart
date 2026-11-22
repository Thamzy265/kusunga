// M1.9a round 5 (tester): B3 toast room beyond 100% and 200% text and narrow
// windows, and B4 click focus beyond the single click.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'about_settings_harness.dart';

const _ring = 2.0;

Future<void> toScrollEnd(WidgetTester tester) async {
  await tester.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, -9000),
  );
  await tester.pump();
}

/// Shows a toast the way Settings does (floating, same messenger), with
/// [message].
Future<void> showToast(WidgetTester tester, String message) async {
  final messenger = ScaffoldMessenger.of(
    tester.element(find.byType(SingleChildScrollView).first),
  );
  messenger.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('B3 more sizes', () {
    for (final (scale, size) in [
      (1.5, const Size(800, 632)),
      (1.0, const Size(360, 640)),
      // 200% at 360 px is left out: the test font (Ahem) is wider than the
      // real one and wraps "Link copied" to two lines there. QA checks it.
      (1.0, const Size(320, 480)),
    ]) {
      testWidgets('a copied-toast under View licences at ${scale * 100}% text, '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await showSettings(tester, size: size, textScale: scale);
        await tester.ensureVisible(hook('about-copy-link'));
        await tester.pump();
        await tester.tap(button('about-copy-link'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await toScrollEnd(tester);
        final toast = tester.getRect(find.byType(SnackBar));
        final licences = tester.getRect(button('about-view-licences'));
        expect(
          toast.overlaps(licences.inflate(_ring)),
          isFalse,
          reason: 'toast $toast, View licences $licences',
        );
        // The toast has room: it is a one-line toast in these sizes.
        expect(toast.height, lessThan(80), reason: 'one line');
      });
    }

    testWidgets('the end of the page leaves room under View licences, '
        'at 100% text', (tester) async {
      await showSettings(tester);
      await toScrollEnd(tester);
      final view = settingsView(tester);
      final licences = tester.getRect(button('about-view-licences'));
      // Room for a one-line toast (about 43 + 20) plus the 16 px gutter.
      expect(view.bottom - licences.bottom, greaterThanOrEqualTo(60));
    });

    testWidgets('delete-count toast ("12 items deleted") is one line and '
        'clear of View licences', (tester) async {
      await showSettings(tester, size: const Size(360, 640));
      await toScrollEnd(tester);
      await showToast(tester, '12 items deleted');
      final toast = tester.getRect(find.byType(SnackBar));
      final licences = tester.getRect(button('about-view-licences'));
      expect(toast.overlaps(licences.inflate(_ring)), isFalse);
    });
  });

  // The import toast is several sentences. B3 sized the room for one line;
  // the long toast can still cover the end of the page (as before B3). This
  // records that the user can still reach View licences from the keyboard.
  group('B3 the long import toast (recorded limit)', () {
    const long =
        'Imported 3 snippets and 12 items. 2 snippets were already here. '
        '4 items were skipped because they were too large.';

    testWidgets('the toast can be taller than the room: View licences is '
        'still focusable and opens with Enter', (tester) async {
      await showSettings(tester, size: const Size(360, 640));
      await toScrollEnd(tester);
      await showToast(tester, long);
      final toast = tester.getRect(find.byType(SnackBar));
      expect(toast.height, greaterThan(60), reason: 'several lines');
      await tabTo(tester, button('about-view-licences'));
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });
  });

  group('B4 more ways in and out', () {
    Future<void> open(WidgetTester tester) async {
      await tester.ensureVisible(hook('about-view-licences'));
      await tester.pump();
      await tester.tap(button('about-view-licences'));
      await tester.pumpAndSettle();
    }

    testWidgets('Space opens it, and Esc returns the focus', (tester) async {
      await showSettings(tester);
      await tabTo(tester, button('about-view-licences'));
      await key(tester, LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(hasFocus(tester, button('about-view-licences')), isTrue);
    });

    testWidgets('click, Esc, click, Esc: the focus comes back every time', (
      tester,
    ) async {
      await showSettings(tester);
      for (var i = 0; i < 3; i++) {
        await open(tester);
        expect(find.byType(LicensePage), findsOneWidget, reason: 'round $i');
        await key(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsNothing, reason: 'round $i');
        expect(
          hasFocus(tester, button('about-view-licences')),
          isTrue,
          reason: 'round $i',
        );
      }
    });

    testWidgets('after a click and Esc, Shift+Tab goes to the control before '
        'it and Tab goes on from it', (tester) async {
      await showSettings(tester);
      await open(tester);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await key(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      expect(hasFocus(tester, button('about-view-licences')), isFalse);
      expect(hasFocus(tester, button('about-copy-link')), isTrue);
    });

    testWidgets('a click on Copy version does not move the focus to View '
        'licences', (tester) async {
      await showSettings(tester);
      await tester.ensureVisible(hook('about-copy-version'));
      await tester.pump();
      await tester.tap(button('about-copy-version'));
      await tester.pump();
      expect(hasFocus(tester, button('about-view-licences')), isFalse);
    });

    testWidgets('two quick clicks open one page', (tester) async {
      await showSettings(tester);
      await tester.ensureVisible(hook('about-view-licences'));
      await tester.pump();
      final at = tester.getCenter(button('about-view-licences'));
      await tester.tapAt(at);
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('the focus node of View licences is released with the '
        'section (leaving Settings while the page is open)', (tester) async {
      await showSettings(tester);
      await open(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
