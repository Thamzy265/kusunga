// M1.9a round 5 (tester): edge cases of NoticeEntry's paragraph rules (B1) and
// the proof that the GPL text in LICENSE is still read the old way.
import 'dart:io';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/licences.dart';

List<String> texts(String t) => [
  for (final p in NoticeEntry(const ['x'], t).paragraphs) p.text,
];

void main() {
  group('NoticeEntry paragraph rules', () {
    test('empty and blank-only text give no paragraph', () {
      expect(texts(''), isEmpty);
      expect(texts('\n\n  \n'), isEmpty);
    });

    test('trailing spaces are cut from indented lines', () {
      expect(texts('    a   \n    b \t '), ['a\nb']);
    });

    test('a line of spaces inside an indented run is a blank line', () {
      expect(texts('    a\n   \n    b'), ['a', 'b']);
    });

    test('several blank lines between indented blocks give no empty '
        'paragraph', () {
      expect(texts('    a\n\n\n\n    b'), ['a', 'b']);
    });

    test('blank lines after an indented run, before prose, add nothing', () {
      expect(texts('    a\n\n\nprose'), ['a', 'prose']);
    });

    test('prose right after an indented run (no blank line) is its own '
        'paragraph', () {
      expect(texts('    a\n    b\nprose one\nprose two'), [
        'a\nb',
        'prose one prose two',
      ]);
    });

    test('indented lines right after prose start their own paragraph', () {
      expect(texts('prose\n    a\n    b'), ['prose', 'a\nb']);
    });

    test('the common indent is removed, deeper indent is kept', () {
      expect(texts('        a\n    b\n          c'), ['    a\nb\n      c']);
    });

    test('a tab counts as one character of indent (a tab-indented line is '
        'prose)', () {
      expect(texts('\ta\n\tb'), ['a b']);
      expect(texts('\t\t\t\ta\n\t\t\t\tb'), ['a\nb']);
    });

    test('CRLF with trailing spaces and blank lines', () {
      expect(texts('p1\r\np2\r\n\r\n    a  \r\n    b\r\n\r\n    c\r\n'), [
        'p1 p2',
        'a\nb',
        'c',
      ]);
    });

    test('every paragraph of an indented run is indented one level', () {
      final p = NoticeEntry(const ['x'], '    a\n\n    b').paragraphs.toList();
      expect(p.map((e) => e.indent), [1, 1]);
    });

    test('the packages are passed on untouched', () {
      expect(NoticeEntry(const ['a', 'b'], 'x').packages, ['a', 'b']);
    });

    test('20000 lines are read at once (no quadratic scan)', () {
      final text = [
        for (var i = 0; i < 10000; i++) ...['    line $i', ''],
      ].join('\n');
      final sw = Stopwatch()..start();
      final all = texts(text);
      expect(all, hasLength(10000));
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('the GPL text is not read by NoticeEntry', () {
    test(
      'the registry reads LICENSE like Flutter reads licence files',
      () async {
        LicenseRegistry.reset();
        addTearDown(LicenseRegistry.reset);
        registerLicences(bundle: _DiskBundle());
        final gpl = File('LICENSE').readAsStringSync();
        final entries = await LicenseRegistry.licenses.toList();
        final ours = entries.firstWhere(
          (e) => e.packages.length == 1 && e.packages.single == 'Kusunga',
          orElse: () => throw TestFailure('no Kusunga entry in the registry'),
        );
        final expected = LicenseEntryWithLineBreaks(const ['Kusunga'], gpl);
        expect(
          [for (final p in ours.paragraphs) (p.text, p.indent)],
          [for (final p in expected.paragraphs) (p.text, p.indent)],
        );
      },
    );

    test('NoticeEntry on the GPL would read it differently (the test above '
        'is not vacuous)', () {
      final gpl = File('LICENSE').readAsStringSync();
      final a = [
        for (final p in NoticeEntry(const ['K'], gpl).paragraphs) p.text,
      ];
      final b = [
        for (final p in LicenseEntryWithLineBreaks(const ['K'], gpl).paragraphs)
          p.text,
      ];
      expect(a, isNot(b));
    });
  });
}

/// The assets as the app bundles them, read from the project folder.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
