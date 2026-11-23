// M1.9a round 5 (tester): the shape of assets/licences/sqlite3mc.txt. Checked
// by hand once against the v2.5.0 sources (every quoted block equals the named
// lines of the named file once comment marks are taken off; checked with a
// script outside the repo). These tests keep the shape from drifting.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final notice = File('assets/licences/sqlite3mc.txt').readAsStringSync();
  final header = RegExp(
    r'^  Text of (\S+?), lines (\d+) to (\d+)',
    multiLine: true,
  );

  /// The text under one "Text of ..." line, up to the next block or part.
  Map<String, String> blocks() {
    final lines = notice.split('\n');
    final out = <String, String>{};
    String? key;
    final buf = <String>[];
    void flush() {
      if (key != null) out[key] = buf.join('\n');
      buf.clear();
    }

    for (final l in lines) {
      final m = header.firstMatch(l);
      if (m != null) {
        flush();
        key = '${m.group(1)} ${m.group(2)}-${m.group(3)}';
      } else if (l.startsWith('* ')) {
        flush();
        key = null;
      } else if (key != null) {
        buf.add(l);
      }
    }
    flush();
    return out;
  }

  test('there are 22 quoted blocks, each with a valid line range', () {
    final all = header.allMatches(notice).toList();
    expect(all, hasLength(22));
    for (final m in all) {
      final a = int.parse(m.group(2)!);
      final b = int.parse(m.group(3)!);
      expect(a, greaterThanOrEqualTo(1), reason: m.group(1));
      expect(b, greaterThanOrEqualTo(a), reason: m.group(1));
    }
  });

  test('a block never has more lines of text than its range names', () {
    for (final e in blocks().entries) {
      final m = RegExp(r' (\d+)-(\d+)$').firstMatch(e.key)!;
      final span = int.parse(m.group(2)!) - int.parse(m.group(1)!) + 1;
      final text = e.value
          .split('\n')
          .where((l) => l.trim().isNotEmpty && !l.startsWith('  The texts'))
          .length;
      expect(text, lessThanOrEqualTo(span), reason: e.key);
    }
  });

  test('no quoted line starts with a comment mark', () {
    final mark = RegExp(r'^\s*(/\*|\*/|\*\*|//|\* )');
    for (final e in blocks().entries) {
      for (final l in e.value.split('\n')) {
        // The SQLite blessing keeps its own "*" bullets in sqlite.txt, not here.
        expect(mark.hasMatch(l), isFalse, reason: '${e.key}: $l');
      }
    }
  });

  test('the quoted text has no tab, no carriage return and no trailing '
      'spaces', () {
    for (final e in blocks().entries) {
      for (final l in e.value.split('\n')) {
        expect(l, isNot(contains('\t')), reason: e.key);
        expect(l, isNot(contains('\r')), reason: e.key);
        expect(l, equals(l.trimRight()), reason: '${e.key}: "$l"');
      }
    }
  });

  test('every block is under its own part, which names its licence', () {
    final parts = notice.split(RegExp(r'^\* ', multiLine: true)).skip(1);
    for (final part in parts) {
      if (!part.contains('Text of ')) continue;
      expect(part, contains('Licence:'), reason: part.split('\n').first);
    }
  });

  test('the file is plain text: no tab, no carriage return, ends with one '
      'new line', () {
    expect(notice, isNot(contains('\t')));
    expect(notice, isNot(contains('\r')));
    expect(notice.endsWith('\n'), isTrue);
    expect(notice.endsWith('\n\n'), isFalse);
  });

  test('the MIT licence text appears twice and no other part invents one', () {
    expect(
      'Permission is hereby granted, free of charge'.allMatches(notice),
      hasLength(2),
    );
  });
}
