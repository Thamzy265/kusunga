// M1.9a round 5, B3 (QA): the "Version copied" / "Link copied" toast never
// covers View licences, however far Settings is scrolled and at any text size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'about_settings_harness.dart';

/// The focus ring of View licences reaches this far outside the button.
const _ring = 2.0;

void main() {
  group('B3: the toast never covers View licences', () {
    for (final scale in [1.0, 2.0]) {
      for (final id in ['about-copy-version', 'about-copy-link']) {
        testWidgets('$id at ${(scale * 100).toInt()}% text, Settings scrolled '
            'to the end', (tester) async {
          await showSettings(tester, textScale: scale);
          await tester.ensureVisible(hook(id));
          await tester.pump();
          await tester.tap(button(id));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          // With the toast showing, the user scrolls to the end.
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -6000),
          );
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);
          final toast = tester.getRect(find.byType(SnackBar));
          final licences = tester.getRect(button('about-view-licences'));
          expect(
            toast.overlaps(licences.inflate(_ring)),
            isFalse,
            reason: 'toast $toast, View licences $licences',
          );
        });
      }
    }
  });
}
