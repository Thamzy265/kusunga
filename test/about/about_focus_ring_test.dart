// M1.9a round 5, B2 (QA, WCAG 2.4.7): the whole focus ring of Copy version,
// Copy link and View licences is in view when Tab scrolls them in. The ring is
// drawn outside the button, so a button scrolled flush to the edge of its view
// had it cut off there.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'about_settings_harness.dart';

/// Where the focus ring is drawn: the outline of a focused button (2 px,
/// outside it), see `KusungaTokens.themeData`.
const _ring = 2.0;

void main() {
  /// The focused control as drawn: its focus node's own box (the button
  /// without Material's invisible tap-target margin), plus the ring.
  Rect ringOfFocus() => FocusManager.instance.primaryFocus!.rect.inflate(_ring);

  group('B2: the whole focus ring is in view after Tab', () {
    for (final size in [const Size(800, 632), const Size(360, 640)]) {
      testWidgets('Tab down to each About button at ${size.width.toInt()} px', (
        tester,
      ) async {
        await showSettings(tester, size: size);
        for (final id in aboutButtonIds) {
          await tabTo(tester, button(id));
          final ring = ringOfFocus();
          final box = settingsView(tester);
          expect(ring.bottom, lessThanOrEqualTo(box.bottom), reason: id);
          expect(ring.top, greaterThanOrEqualTo(box.top), reason: id);
          expect(ring.left, greaterThanOrEqualTo(box.left), reason: id);
          expect(ring.right, lessThanOrEqualTo(box.right), reason: id);
        }
      });
    }

    testWidgets('Shift+Tab back up through the About buttons', (tester) async {
      await showSettings(tester);
      await tabTo(tester, button('about-view-licences'));
      for (final id in aboutButtonIds.reversed.skip(1)) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await key(tester, LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        // The link text may take a stop between the two buttons.
        if (!hasFocus(tester, button(id))) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
          await key(tester, LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        }
        expect(hasFocus(tester, button(id)), isTrue, reason: id);
        final ring = ringOfFocus();
        final box = settingsView(tester);
        expect(ring.top, greaterThanOrEqualTo(box.top), reason: id);
        expect(ring.bottom, lessThanOrEqualTo(box.bottom), reason: id);
      }
    });
  });
}
