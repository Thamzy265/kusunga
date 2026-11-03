import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/picker/picker_search.dart';

ClipItem item(int id, String text, {ClipKind kind = ClipKind.text}) => ClipItem(
  id: id,
  kind: kind,
  preview: previewOf(text),
  isTruncated: text.length > ClipItem.previewLength,
  createdAt: id,
  lastCopiedAt: id,
);

List<int> ids(List<ClipItem> items) => [for (final i in items) i.id];

void main() {
  late PickerSearch search;
  setUp(() => search = PickerSearch());

  test('an empty query keeps every item in order', () {
    final items = [item(3, 'c'), item(2, 'b'), item(1, 'a')];
    expect(ids(search.filter(items, '')), [3, 2, 1]);
  });

  test('matches anywhere in the text, ignoring case', () {
    final items = [
      item(3, 'Call me on 07700 900123'),
      item(2, 'https://Example.com/path'),
      item(1, 'Meeting notes'),
    ];
    expect(ids(search.filter(items, 'EXAMPLE')), [2]);
    expect(ids(search.filter(items, 'me')), [3, 1]);
    expect(ids(search.filter(items, '900')), [3]);
    expect(ids(search.filter(items, 'zzz')), isEmpty);
  });

  test('line breaks and runs of spaces count as one space', () {
    final items = [item(1, 'agenda for\n  Thursday')];
    expect(ids(search.filter(items, 'for thursday')), [1]);
    expect(ids(search.filter(items, 'for   thursday')), [1]);
  });

  test('text beyond the 2,000 character preview is not searched', () {
    final items = [item(1, '${'a' * 2000}needle')];
    expect(search.filter(items, 'needle'), isEmpty);
  });

  test('a new copy shows up and a deleted one goes', () {
    var items = [item(1, 'apple')];
    expect(ids(search.filter(items, 'app')), [1]);
    items = [item(2, 'apple pie'), ...items];
    expect(ids(search.filter(items, 'app')), [2, 1]);
    items = [item(2, 'apple pie')];
    expect(ids(search.filter(items, 'app')), [2]);
  });

  test('typing more letters gives the same result as searching afresh', () {
    final rnd = Random(7);
    String word() => String.fromCharCodes(
      List.generate(1 + rnd.nextInt(6), (_) => 97 + rnd.nextInt(4)),
    );
    final items = [
      for (var i = 0; i < 300; i++)
        item(i, List.generate(6, (_) => word()).join(' ')),
    ];
    for (var round = 0; round < 40; round++) {
      final q = word() + word();
      final incremental = PickerSearch();
      for (var n = 1; n <= q.length; n++) {
        incremental.filter(items, q.substring(0, n));
      }
      final naive = PickerSearch().filter(items, q);
      expect(ids(incremental.filter(items, q)), ids(naive), reason: q);
      expect(ids(naive), [
        for (final i in items)
          if (PickerSearch.display(
            i.preview,
          ).toLowerCase().contains(PickerSearch.normaliseQuery(q)))
            i.id,
      ]);
    }
  });

  test('deleting letters widens the result again', () {
    final items = [item(2, 'abc'), item(1, 'abd')];
    expect(ids(search.filter(items, 'abd')), [1]);
    expect(ids(search.filter(items, 'ab')), [2, 1]);
  });

  test('control and invisible characters are shown, so can be searched', () {
    final items = [item(1, 'a\u202Eb')];
    expect(PickerSearch.display(items.single.preview), contains('[U+202E]'));
  });

  group('match ranges for highlighting', () {
    test('finds every occurrence, ignoring case', () {
      expect(PickerSearch.ranges('Banana bandana', 'ban'), [(0, 3), (7, 10)]);
    });

    test('no query or no match gives no ranges', () {
      expect(PickerSearch.ranges('abc', ''), isEmpty);
      expect(PickerSearch.ranges('abc', 'x'), isEmpty);
    });

    test('does not overlap matches', () {
      expect(PickerSearch.ranges('aaaa', 'aa'), [(0, 2), (2, 4)]);
    });

    test('odd letters never give a range outside the text', () {
      for (final text in [
        'İstanbul',
        'ẞtraße',
        'ΣΑΣ',
        'ǅ',
        '\u{1F600} smile',
      ]) {
        for (final (a, b) in PickerSearch.ranges(text, 'i')) {
          expect(a, inInclusiveRange(0, text.length));
          expect(b, inInclusiveRange(a, text.length));
        }
      }
      expect(search.filter([item(1, 'İstanbul')], 'stan').length, 1);
    });
  });

  test('5,000 items of 2,000 characters: under 50 ms a keystroke', () {
    final rnd = Random(1);
    final items = [
      for (var i = 0; i < 5000; i++)
        item(
          5000 - i,
          String.fromCharCodes(
            List.generate(2000, (_) => 97 + rnd.nextInt(26)),
          ),
        ),
    ];
    // First use builds the index for the list (done when the picker opens,
    // before the first key is typed).
    search.filter(items, '');
    // Each query is a fresh search: a worst case, the previous result cannot
    // be reused.
    final worst = <int>[];
    for (final q in ['qz', 'abc', 'zzzz', 'mnop', 'x', 'kq']) {
      final fresh = PickerSearch()..filter(items, '');
      final sw = Stopwatch()..start();
      fresh.filter(items, q);
      worst.add(sw.elapsedMilliseconds);
    }
    expect(worst.reduce(max), lessThan(50), reason: 'ms per keystroke: $worst');
  });
}
