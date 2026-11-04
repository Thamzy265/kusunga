// Tester probes for M1.3 search: Unicode, odd queries, highlights, speed.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/picker/picker_search.dart';

ClipItem item(int id, String text) => ClipItem(
  id: id,
  kind: ClipKind.text,
  preview: previewOf(text),
  isTruncated: text.length > ClipItem.previewLength,
  createdAt: id,
  lastCopiedAt: id,
);

List<int> ids(List<ClipItem> items) => [for (final i in items) i.id];

void main() {
  late PickerSearch search;
  setUp(() => search = PickerSearch());

  group('case-insensitive means case-insensitive (UI spec)', () {
    test('Turkish dotted capital I: "istanbul" finds "İstanbul"', () {
      // Regression lock: Dart lower-cases İ to one unit, so this works today.
      final items = [item(1, 'İstanbul trip')];
      expect(ids(search.filter(items, 'istanbul')), [1]);
    });

    test('a row with İ still highlights a match elsewhere in the row', () {
      // Regression lock: ranges() gives up for a whole row when lower-casing
      // changes its length; that must not start to hit common letters.
      const text = 'İ foo bar';
      expect(PickerSearch.ranges(text, 'foo'), [(2, 5)]);
    });

    test(
      'German ß: "STRASSE" finds "Straße"',
      skip:
          'Deferred: Later line "Unicode-aware picker search" (lead, 2026-11-04)',
      () {
        // BUG-S1 (low): no full case folding, so ß and SS never match.
        final items = [item(1, 'Straße 5')];
        expect(ids(search.filter(items, 'STRASSE')), [1]);
      },
    );

    test(
      'accents typed composed find text copied decomposed (macOS)',
      skip:
          'Deferred: Later line "Unicode-aware picker search" (lead, 2026-11-04)',
      () {
        // BUG-S2: macOS file names are NFD; "café" typed as one code point
        // does not match "cafe" + combining acute.
        final items = [item(1, 'cafe\u0301 menu')];
        expect(ids(search.filter(items, 'caf\u00E9')), [1]);
      },
    );
  });

  group('odd queries', () {
    test('a query of only spaces behaves as an empty query', () {
      // BUG-S3: "   " is one space after normalising, so the list shrinks to
      // items that contain a space while the footer still says "N items".
      final items = [item(2, 'oneword'), item(1, 'two words')];
      expect(ids(search.filter(items, '   ')), [2, 1]);
      expect(ids(search.filter(items, '\n\t')), [2, 1]);
    });

    test('regex and glob characters are plain text', () {
      final items = [
        item(1, 'a.b'),
        item(2, 'axb'),
        item(3, r'C:\dir\(x)[1]*?'),
        item(4, '^start\$'),
      ];
      expect(ids(search.filter(items, 'a.b')), [1]);
      expect(ids(search.filter(items, '.*')), isEmpty);
      expect(ids(search.filter(items, r'\dir')), [3]);
      expect(ids(search.filter(items, '(x)[1]*?')), [3]);
      expect(ids(search.filter(items, '[')), [3]);
      expect(ids(search.filter(items, r'^start$')), [4]);
      expect(PickerSearch.ranges('a.b axb', '.'), [(1, 2)]);
    });

    test('a query longer than every item finds nothing and never throws', () {
      final items = [item(1, 'short'), item(2, 'tiny')];
      expect(search.filter(items, 'x' * 100000), isEmpty);
      expect(PickerSearch.ranges('short', 'x' * 100000), isEmpty);
    });

    test('a query as long as the whole item matches it', () {
      final items = [item(1, 'exactly this')];
      expect(ids(search.filter(items, 'EXACTLY THIS')), [1]);
    });

    test('NUL and control characters in a query do not throw', () {
      final items = [item(1, 'a\u0000b'), item(2, 'plain')];
      search.filter(items, '\u0000');
      search.filter(items, '\u202E');
      expect(search.filter(items, 'zzz\u0000'), isEmpty);
    });
  });

  group('emoji and surrogates', () {
    test('an emoji query finds the emoji', () {
      final items = [item(1, 'party 🎉 time'), item(2, 'plain')];
      expect(ids(search.filter(items, '🎉')), [1]);
    });

    test('highlight ranges for an emoji query cover whole pairs', () {
      const text = 'a🎉b🎉';
      final r = PickerSearch.ranges(text, '🎉');
      expect(r, [(1, 3), (4, 6)]);
    });

    test('a half emoji as a query never gives a range inside a pair', () {
      // BUG-S4: "\uD83C" (a lone high surrogate, e.g. from a broken IME)
      // matches inside "🎉" and the highlight would split the pair.
      const text = 'a🎉b';
      for (final r in PickerSearch.ranges(text, '\uD83C')) {
        final startsInsidePair =
            r.$1 > 0 &&
            text.codeUnitAt(r.$1) >= 0xDC00 &&
            text.codeUnitAt(r.$1) <= 0xDFFF;
        expect(startsInsidePair, isFalse, reason: 'range $r splits a pair');
      }
      expect(PickerSearch.ranges(text, '\uD83C'), isEmpty);
    });

    test('a family emoji (ZWJ sequence) is searchable as a whole', () {
      const family = '👨\u200D👩\u200D👧';
      final items = [item(1, 'my $family x')];
      expect(ids(search.filter(items, family)), [1]);
    });
  });

  group('speed (design note: 5,000 items, under 50 ms a keystroke)', () {
    final items = [
      for (var i = 0; i < 5000; i++)
        item(i, 'Item $i ${'lorem ipsum dolor sit amet ' * 70}end $i'),
    ];

    test('opening with an empty query does no per-item work', () {
      // BUG-S5: filter() builds the lower-case index even for an empty query,
      // so the picker opening with 5,000 long items does about 0.8 s of
      // work on the UI thread (JIT test run) before the first frame. An
      // empty query needs no index (150 ms budget to show the picker).
      final sw = Stopwatch()..start();
      final shown = search.filter(items, '');
      sw.stop();
      expect(shown.length, 5000);
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: '${sw.elapsedMilliseconds} ms',
      );
    });

    test('keystrokes that cannot narrow stay under 50 ms', () {
      search.filter(items, 'x'); // builds the index
      final sw = Stopwatch();
      final times = <int>[];
      // Alternating queries: none extends the one before.
      for (final q in ['zz', 'ipsum', 'q', 'dolor sit', 'amet', 'end 4999']) {
        sw
          ..reset()
          ..start();
        search.filter(items, q);
        times.add(sw.elapsedMilliseconds);
      }
      // CI runners are slower and noisy: the median must meet the 50 ms
      // target and no single run may be over 150 ms.
      times.sort();
      expect(
        times[times.length ~/ 2],
        lessThan(50),
        reason: 'median of $times',
      );
      expect(times.last, lessThan(150), reason: 'max of $times');
    });
  });
}
