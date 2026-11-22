// M1.9a round 5 (tester): what flutterNotices drops, what it keeps, and what
// it does with a NOTICES.Z that is empty or garbled.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/flutter_notices.dart';
import 'package:kusunga/about/licences.dart';

/// Serves [notices] as NOTICES.Z bytes and [licence] as LICENSE.
class NoticesBundle extends CachingAssetBundle {
  NoticesBundle(this.noticesBytes, [this.licence = 'THE LICENCE TEXT']);
  final List<int> noticesBytes;
  final String? licence;

  factory NoticesBundle.of(List<String> blocks, [String? licence]) =>
      NoticesBundle(
        gzip.encode(utf8.encode(blocks.join('\n${'-' * 80}\n'))),
        licence ?? 'THE LICENCE TEXT',
      );

  @override
  Future<ByteData> load(String key) async {
    final List<int> bytes;
    if (key == 'NOTICES.Z') {
      bytes = noticesBytes;
    } else if (key == kusungaLicenceAsset && licence != null) {
      bytes = utf8.encode(licence!);
    } else {
      throw FlutterError('no $key');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

Future<List<String>> packagesOf(NoticesBundle b) async => [
  for (final e in await flutterNotices(bundle: b).toList())
    e.packages.join('+'),
];

void main() {
  const gpl = 'THE LICENCE TEXT';

  group('what is dropped', () {
    test(
      'only an entry for exactly ["kusunga"] with the LICENSE text',
      () async {
        expect(
          await packagesOf(NoticesBundle.of(['kusunga\n\n$gpl'])),
          isEmpty,
        );
      },
    );

    test('the upper-case name is another package and is kept', () async {
      expect(await packagesOf(NoticesBundle.of(['Kusunga\n\n$gpl'])), [
        'Kusunga',
      ]);
    });

    test(
      '["kusunga", other] with the same text is kept, in either order',
      () async {
        expect(
          await packagesOf(
            NoticesBundle.of([
              'kusunga\nzlib\n\n$gpl',
              'zlib\nkusunga\n\n$gpl',
            ]),
          ),
          ['kusunga+zlib', 'zlib+kusunga'],
        );
      },
    );

    test(
      'an entry with no package line and the LICENSE text is kept',
      () async {
        expect(await packagesOf(NoticesBundle.of([gpl])), ['']);
      },
    );

    test(
      'LICENSE text with something added or cut is a different text',
      () async {
        expect(
          await packagesOf(
            NoticesBundle.of([
              'kusunga\n\n$gpl and more',
              'kusunga\n\nTHE LICENCE',
            ]),
          ),
          ['kusunga', 'kusunga'],
        );
      },
    );

    test(
      'white space in the text does not matter, a changed word does',
      () async {
        final b = NoticesBundle.of([
          'kusunga\n\n  THE\r\n\tLICENCE   TEXT\n\n',
          'kusunga\n\nTHE LICENSE TEXT',
        ]);
        expect(await packagesOf(b), ['kusunga']);
      },
    );

    test(
      'every copy of the app licence is dropped, the neighbours stay',
      () async {
        expect(
          await packagesOf(
            NoticesBundle.of([
              'a\n\nx',
              'kusunga\n\n$gpl',
              'kusunga\n\n$gpl',
              'b\n\ny',
            ]),
          ),
          ['a', 'b'],
        );
      },
    );

    test('when LICENSE cannot be read nothing is dropped', () async {
      final b = NoticesBundle(
        gzip.encode(utf8.encode('kusunga\n\n$gpl\n${'-' * 80}\nb\n\ny')),
        null,
      );
      expect(await packagesOf(b), ['kusunga', 'b']);
    });

    test('with an empty LICENSE nothing but empty text is dropped', () async {
      expect(await packagesOf(NoticesBundle.of(['kusunga\n\nreal text'], '')), [
        'kusunga',
      ]);
    });
  });

  group('what is kept', () {
    test('every other notice, in order, with its packages and text', () async {
      final blocks = [
        for (var i = 0; i < 300; i++) 'pkg$i\nalias$i\n\ntext $i\n\nsecond $i',
      ];
      final entries = await flutterNotices(
        bundle: NoticesBundle.of(blocks),
      ).toList();
      expect(entries, hasLength(300));
      for (var i = 0; i < 300; i++) {
        expect(entries[i].packages, ['pkg$i', 'alias$i']);
        expect(entries[i].paragraphs.map((p) => p.text), [
          'text $i',
          'second $i',
        ]);
      }
    });

    test('a text with a line of dashes shorter than 80 is not split', () async {
      final entries = await flutterNotices(
        bundle: NoticesBundle.of(['p\n\nbefore\n${'-' * 79}\nafter']),
      ).toList();
      expect(entries, hasLength(1));
    });

    test(
      'a block with no blank line is all package names, with no text',
      () async {
        final entries = await flutterNotices(
          bundle: NoticesBundle.of(['only names']),
        ).toList();
        expect(entries.single.packages, isEmpty);
      },
    );

    test('non-ASCII text survives', () async {
      final entries = await flutterNotices(
        bundle: NoticesBundle.of(['p\n\nCopyright © 2020 Jürgen — 日本語']),
      ).toList();
      expect(
        entries.single.paragraphs.single.text,
        'Copyright © 2020 Jürgen — 日本語',
      );
    });
  });

  group('empty and garbled NOTICES.Z', () {
    test('an empty NOTICES.Z (gzip of nothing) gives no crash', () async {
      final entries = await flutterNotices(
        bundle: NoticesBundle.of(['']),
      ).toList();
      expect(entries.every((e) => e.packages.isEmpty), isTrue);
    });

    test('a zero-byte NOTICES.Z reads as one empty notice, like Flutter\'s '
        'own parser', () async {
      final entries = await flutterNotices(
        bundle: NoticesBundle(const []),
      ).toList();
      expect(entries.every((e) => e.packages.isEmpty), isTrue);
      expect(entries.expand((e) => e.paragraphs), isEmpty);
    });

    // BUG-T1 (M1.9a round 6): these two used to expect the decode error on
    // the stream. That error made the licence page show only the error text
    // and hid Kusunga's own notices, so a NOTICES.Z that cannot be read now
    // gives no notices and no error.
    test('bytes that are not gzip give no notices and no error', () async {
      final s = flutterNotices(
        bundle: NoticesBundle(utf8.encode('not gzip at all')),
      );
      expect(await s.toList(), isEmpty);
    });

    test('a gzip file cut in half does not crash (Dart returns what it could '
        'read)', () async {
      final good = gzip.encode(utf8.encode('a\n\n${'x' * 5000}'));
      final entries = await flutterNotices(
        bundle: NoticesBundle(good.sublist(0, good.length ~/ 2)),
      ).toList();
      expect(entries.length, lessThanOrEqualTo(1));
    });

    test(
      'gzip of bytes that are not UTF-8 gives no notices and no error',
      () async {
        final s = flutterNotices(
          bundle: NoticesBundle(
            gzip.encode([0xff, 0xfe, 0xfa, 0x0a, 0x0a, 0xc3]),
          ),
        );
        expect(await s.toList(), isEmpty);
      },
    );
  });

  group('the licence page with a broken NOTICES.Z', () {
    Future<void> openPage(WidgetTester tester, NoticesBundle notices) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      registerLicences(bundle: _DiskBundle());
      LicenseRegistry.addLicense(() => flutterNotices(bundle: notices));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LicensePage(applicationName: 'Kusunga'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a good NOTICES.Z: Kusunga is listed, the duplicate is not', (
      tester,
    ) async {
      final gpl = await _gpl();
      await openPage(
        tester,
        NoticesBundle.of(['kusunga\n\n$gpl', 'zlib\n\nz'], gpl),
      );
      expect(find.text('Kusunga'), findsWidgets);
      expect(find.text('kusunga'), findsNothing);
      expect(find.text('zlib'), findsOneWidget);
    });

    testWidgets('a garbled NOTICES.Z: the page opens without an uncaught '
        'error (record: what it shows)', (tester) async {
      await openPage(tester, NoticesBundle(utf8.encode('garbage')));
      // In a debug build Flutter reports the failure while decoding; that is
      // the only exception allowed.
      final e = tester.takeException();
      expect(e, anyOf(isNull, isA<FormatException>(), isA<FlutterError>()));
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('a garbled NOTICES.Z still lists Kusunga and its notices', (
      tester,
    ) async {
      await openPage(tester, NoticesBundle(utf8.encode('garbage')));
      tester.takeException();
      // The page is the user's only place to find the GPL and the SQLite
      // notices (GPLv3 5(d)): a broken Flutter collection must not hide them.
      // 'Kusunga' alone would also match the page header, so the two package
      // rows of the notices are checked as well (R13).
      expect(find.text('Kusunga'), findsWidgets);
      expect(find.text('SQLite'), findsOneWidget);
      expect(find.text('SQLite3 Multiple Ciphers'), findsOneWidget);
    });
  });
}

Future<String> _gpl() async => File('LICENSE').readAsStringSync();

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(File(key).readAsBytesSync()));
}
