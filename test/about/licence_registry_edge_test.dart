// M1.9a tester: the licence registry against its sources (AC1, AC7). LICENSE
// is shipped byte for byte, and every part and licence listed in
// docs/licences.md is in the SQLite3 Multiple Ciphers notice, per part.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/licences.dart';

/// Rows of the "what it bundles" table in docs/licences.md: (name cell,
/// licence cell).
List<(String, String)> bundledRows() {
  final doc = File('docs/licences.md').readAsStringSync();
  final section = doc
      .split('## SQLite3 Multiple Ciphers 2.5.0: what it bundles')
      .last
      .split('\n## Flags')
      .first;
  return [
    for (final l in section.split('\n'))
      if (l.startsWith('| ') &&
          !l.startsWith('| Component') &&
          !l.startsWith('|---'))
        (l.split('|')[1].trim(), l.split('|')[2].trim()),
  ];
}

/// The notice split into one block per "* part" bullet.
List<String> noticeBlocks(String text) => [
  for (final b in text.split(RegExp(r'\n(?=\* )')))
    if (b.startsWith('* ')) b.trim(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assets', () {
    test('LICENSE is bundled byte for byte', () async {
      final bundled = (await rootBundle.load(
        kusungaLicenceAsset,
      )).buffer.asUint8List();
      expect(bundled, File('LICENSE').readAsBytesSync());
    });

    test('LICENSE is the GPL version 3 text, whole', () {
      final gpl = File('LICENSE').readAsStringSync();
      expect(gpl, contains('GNU GENERAL PUBLIC LICENSE'));
      expect(gpl, contains('Version 3, 29 June 2007'));
      expect(gpl, contains('TERMS AND CONDITIONS'));
      expect(gpl, contains('END OF TERMS AND CONDITIONS'));
      expect(gpl, contains('How to Apply These Terms to Your New Programs'));
      // Section 5(d) is the one the in-app notice exists for.
      expect(gpl, contains('d) If the work has interactive user interfaces'));
    });

    for (final asset in [sqlite3mcNoticesAsset, sqliteNoticeAsset]) {
      test('$asset is bundled, readable UTF-8 and not empty', () async {
        final text = await rootBundle.loadString(asset);
        expect(text.trim(), isNotEmpty);
        expect(text, isNot(contains('�')));
        expect(text, File(asset).readAsStringSync());
      });
    }
  });

  group('registry', () {
    late List<LicenseEntry> entries;
    setUpAll(() async {
      LicenseRegistry.reset();
      registerLicences();
      entries = await LicenseRegistry.licenses.toList();
    });
    tearDownAll(LicenseRegistry.reset);

    String text(String package) => [
      for (final e in entries.where((e) => e.packages.contains(package)))
        for (final p in e.paragraphs) p.text,
    ].join('\n');

    test(
      'exactly the three notices, Kusunga first, each under its own name',
      () {
        expect(
          [for (final e in entries) e.packages],
          [
            ['Kusunga'],
            ['Kusunga', 'SQLite3 Multiple Ciphers'],
            ['Kusunga', 'SQLite'],
          ],
        );
      },
    );

    test('the Kusunga package leads to all three notices', () {
      final kusunga = entries.where((e) => e.packages.contains('Kusunga'));
      expect(kusunga, hasLength(3));
      final all = [
        for (final e in kusunga)
          for (final p in e.paragraphs) p.text,
      ].join('\n');
      expect(all, contains('Version 3, 29 June 2007'));
      expect(all, contains('SQLite3 Multiple Ciphers 2.5.0'));
      expect(all, contains('May you do good and not evil.'));
    });

    test('the first entry holds every line of LICENSE, in order', () {
      String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
      final gpl = squash(File('LICENSE').readAsStringSync());
      expect(
        squash([for (final p in entries.first.paragraphs) p.text].join('\n')),
        gpl,
      );
    });

    test('each part in docs/licences.md has its own block, in table order', () {
      final rows = bundledRows();
      final blocks = noticeBlocks(
        File(sqlite3mcNoticesAsset).readAsStringSync(),
      );
      expect(blocks, hasLength(rows.length));
      for (var i = 0; i < rows.length; i++) {
        final name = rows[i].$1;
        expect(blocks[i], startsWith('* $name'), reason: 'row $i');
      }
    });

    test('each part names the licences docs/licences.md gives it', () {
      final rows = bundledRows();
      final blocks = noticeBlocks(
        File(sqlite3mcNoticesAsset).readAsStringSync(),
      );
      final spdx = RegExp(
        r'CC0-1\.0|Apache-2\.0|BSD-3-Clause|LGPL-3\.0-or-later WITH '
        r'WxWindows-exception-3\.1|MIT|[Pp]ublic domain',
      );
      var checked = 0;
      for (var i = 0; i < rows.length; i++) {
        for (final m in spdx.allMatches(rows[i].$2)) {
          checked++;
          expect(
            blocks[i],
            contains(m.group(0)!),
            reason: '${rows[i].$1}: licence ${m.group(0)}',
          );
        }
      }
      expect(checked, greaterThan(18), reason: 'table parse found too little');
    });

    test('every source file named in the parts table is in the notice', () {
      final names = <String>{};
      for (final (cell, _) in bundledRows()) {
        for (final m in RegExp(r'[A-Za-z0-9_]+\.[ch]\b').allMatches(cell)) {
          names.add(m.group(0)!);
        }
      }
      // A parse that finds almost nothing would pass; pin a floor.
      expect(names.length, greaterThan(30));
      final notice = text('SQLite3 Multiple Ciphers');
      for (final n in names) {
        expect(notice, contains(n), reason: n);
      }
    });

    test('versions match the dependency table in docs/licences.md', () {
      final doc = File('docs/licences.md').readAsStringSync();
      final mc = RegExp(
        r'\| SQLite3 Multiple Ciphers \| ([\d.]+) \|',
      ).firstMatch(doc)!.group(1)!;
      final sqlite = RegExp(
        r'\| SQLite \| ([\d.]+) \|',
      ).firstMatch(doc)!.group(1)!;
      expect(text('SQLite3 Multiple Ciphers'), contains(mc));
      expect(text('SQLite'), contains(sqlite));
    });

    test('the SQLite notice is the public-domain blessing, in full', () {
      final t = text('SQLite');
      for (final line in [
        'May you do good and not evil.',
        'May you find forgiveness for yourself and forgive others.',
        'May you share freely, never taking more than you give.',
      ]) {
        expect(t, contains(line));
      }
    });

    test('the legalese is the GPL interactive notice, version 3 only', () {
      expect(licenceLegalese, contains('version 3 only'));
      expect(licenceLegalese, contains('ABSOLUTELY NO WARRANTY'));
      expect(licenceLegalese, isNot(contains('any later version')));
      expect(licenceLegalese, startsWith('Copyright (C) 2026 William Nasoni'));
    });
  });

  group('failure paths', () {
    tearDown(LicenseRegistry.reset);

    test('licences are read when asked for, not at registration', () async {
      LicenseRegistry.reset();
      final bundle = _CountingBundle();
      registerLicences(bundle: bundle);
      expect(bundle.loads, isEmpty);
      await LicenseRegistry.licenses.toList();
      expect(bundle.loads, [
        kusungaLicenceAsset,
        sqlite3mcNoticesAsset,
        sqliteNoticeAsset,
      ]);
    });

    test('the sources never use the network', () {
      final src =
          File('lib/about/licences.dart').readAsStringSync() +
          File('lib/about/about_section.dart').readAsStringSync() +
          File('lib/about/build_info.dart').readAsStringSync();
      for (final bad in ['http.get', 'HttpClient', 'launchUrl', 'dart:io']) {
        expect(src, isNot(contains(bad)), reason: bad);
      }
    });
  });
}

class _CountingBundle extends CachingAssetBundle {
  final loads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode('text of $key')),
    );
  }
}
