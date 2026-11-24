// M1.9a round 5, B4 (QA): Esc or Back on the licences page returns the focus
// to View licences after a mouse click, as it does after the keyboard.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'about_settings_harness.dart';

void main() {
  group('B4: Esc returns the focus to View licences', () {
    testWidgets('after a mouse click', (tester) async {
      await showSettings(tester);
      await tester.ensureVisible(hook('about-view-licences'));
      await tester.tap(button('about-view-licences'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(hasFocus(tester, button('about-view-licences')), isTrue);
    });

    testWidgets('after the keyboard (unchanged)', (tester) async {
      await showSettings(tester);
      await tabTo(tester, button('about-view-licences'));
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(hasFocus(tester, button('about-view-licences')), isTrue);
    });

    testWidgets('after a mouse click and the Back button', (tester) async {
      await showSettings(tester);
      await tester.ensureVisible(hook('about-view-licences'));
      await tester.tap(button('about-view-licences'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(hasFocus(tester, button('about-view-licences')), isTrue);
    });
  });
}
