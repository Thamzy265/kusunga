// M1.9a round 6 (tester): how the Argon2 part of the SQLite3 Multiple Ciphers
// notice reads on the licence page, with the CC0 sentence (PM decision
// 2026-11-23). The paragraphs come from the real NoticeEntry over the real
// asset, and the page is the real LicensePage.
import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/licences.dart';

const _choice = 'Kusunga uses Argon2 under the CC0 1.0 option.';
const _licenceLine = 'Licence: CC0-1.0 OR Apache-2.0, at the user\'s option';

List<String> argon2Paragraphs() {
  final entry = NoticeEntry(const [
    'SQLite3 Multiple Ciphers',
  ], File(sqlite3mcNoticesAsset).readAsStringSync());
  final all = [for (final p in entry.paragraphs) p.text];
  final start = all.indexWhere((t) => t.startsWith('* Argon2 ('));
  expect(start, isNot(-1), reason: 'the Argon2 part has a paragraph');
  // The part runs up to the next "* part" paragraph.
  final end = all.indexWhere((t) => t.startsWith('* '), start + 1);
  return all.sublist(start, end == -1 ? all.length : end);
}

void main() {
  group('the Argon2 part on the page', () {
    // B4: the "Licence:" line and the choice share the same 2-space indent,
    // so without the blank line between them NoticeEntry flows them into one
    // line, "... at the user's option Kusunga uses Argon2 under the CC0 1.0
    // option." (no full stop between them). Same fault as B1 for the
    // blessing.
    test('B4: the CC0 sentence is not run onto the Licence line', () {
      final p = argon2Paragraphs();
      final holder = p.firstWhere((t) => t.contains(_choice));
      expect(
        holder,
        isNot(contains('Licence:')),
        reason: 'the sentence must read as its own line, got: $holder',
      );
      expect(holder.trim(), _choice);
    });

    test('the sentence is on the page once, before the quoted header, and '
        'the Licence line is intact', () {
      final p = argon2Paragraphs();
      expect(p.where((t) => t.contains(_choice)), hasLength(1));
      expect(p.where((t) => t.contains(_licenceLine)), hasLength(1));
      final said = p.indexWhere((t) => t.contains(_choice));
      final quote = p.indexWhere((t) => t.startsWith('Text of src/argon2'));
      expect(said, lessThan(quote));
      expect(p.first, '* Argon2 (src/argon2, including blake2)');
    });

    testWidgets('the real licence page shows the sentence as text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 20000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      LicenseRegistry.addLicense(() async* {
        yield NoticeEntry(const [
          'Kusunga',
        ], File(sqlite3mcNoticesAsset).readAsStringSync());
      });
      await tester.pumpWidget(
        MaterialApp(
          // On Flutter 3.50 the default page transition in tests snapshots
          // the whole 900 x 20000 view into one bitmap, which the test engine
          // cannot make (PictureRasterizationException; it passed on 3.44.6).
          // A transition without the snapshot keeps the tall view, so the
          // page still builds every paragraph.
          theme: ThemeData(
            pageTransitionsTheme: PageTransitionsTheme(
              builders: {
                for (final p in TargetPlatform.values)
                  p: const ZoomPageTransitionsBuilder(allowSnapshotting: false),
              },
            ),
          ),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LicensePage(applicationName: 'K'),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Kusunga'));
      await tester.pumpAndSettle();
      final texts = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (t.data != null) t.data!,
      ];
      final shown = texts.where((t) => t.contains(_choice)).toList();
      expect(shown, hasLength(1), reason: 'built on the page exactly once');
      // B4: the sentence is a Text of its own on the page.
      expect(shown.single.trim(), _choice, reason: shown.single);
    });
  });
}
