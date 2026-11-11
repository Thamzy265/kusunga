import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_store.dart';

/// Behaviour every [HistoryStore] must have, whatever it keeps data in.
void runStoreContract(String name, HistoryStore Function() create) {
  group('$name contract', () {
    late HistoryStore store;
    var now = 1000;
    int tick() => now += 10;

    setUp(() {
      now = 1000;
      store = create();
    });
    tearDown(() => store.close());

    test('lists newest first with kind', () {
      store.insertOrBump('one', ClipKind.text, tick());
      store.insertOrBump('https://example.com', ClipKind.link, tick());

      final items = store.list();
      expect(items.map((i) => i.preview), ['https://example.com', 'one']);
      expect(items.first.kind, ClipKind.link);
      expect(items.last.kind, ClipKind.text);
      expect(store.count, 2);
    });

    test(
      'copying the same text again moves it to the top, not a duplicate',
      () {
        store.insertOrBump('a', ClipKind.text, tick());
        final created = store.list().single.createdAt;
        store.insertOrBump('b', ClipKind.text, tick());
        store.insertOrBump('a', ClipKind.text, tick());

        final items = store.list();
        expect(items.map((i) => i.preview), ['a', 'b']);
        expect(items.first.createdAt, created);
        expect(items.first.lastCopiedAt, greaterThan(items.last.lastCopiedAt));
      },
    );

    test('text that differs only in whitespace is a different item', () {
      store.insertOrBump('a', ClipKind.text, tick());
      store.insertOrBump('a ', ClipKind.text, tick());
      expect(store.count, 2);
    });

    test('two copies in the same millisecond keep their order', () {
      store.insertOrBump('first', ClipKind.text, 5000);
      store.insertOrBump('second', ClipKind.text, 5000);
      store.insertOrBump('first', ClipKind.text, 5000);
      expect(store.list().map((i) => i.preview), ['first', 'second']);
    });

    test('keeps only the newest N items; the oldest goes first', () {
      store.setLimit(10);
      for (var i = 0; i < 12; i++) {
        store.insertOrBump('item $i', ClipKind.text, tick());
      }
      final items = store.list();
      expect(items.length, 10);
      expect(items.first.preview, 'item 11');
      expect(items.last.preview, 'item 2');
    });

    test('a bumped old item survives the trim', () {
      store.setLimit(10);
      for (var i = 0; i < 10; i++) {
        store.insertOrBump('item $i', ClipKind.text, tick());
      }
      store.insertOrBump('item 0', ClipKind.text, tick());
      store.insertOrBump('new', ClipKind.text, tick());
      final texts = store.list().map((i) => i.preview).toList();
      expect(texts, contains('item 0'));
      expect(texts, isNot(contains('item 1')));
      expect(texts.length, 10);
    });

    test('the limit defaults to 200 and accepts 10 to 5000 only', () {
      expect(store.limit, 200);
      store.setLimit(5000);
      expect(store.limit, 5000);
      store.setLimit(10);
      expect(store.limit, 10);
      expect(() => store.setLimit(9), throwsArgumentError);
      expect(() => store.setLimit(5001), throwsArgumentError);
      expect(store.limit, 10);
    });

    test(
      'lowering the limit removes the oldest items and reports the cost',
      () {
        for (var i = 0; i < 15; i++) {
          store.insertOrBump('item $i', ClipKind.text, tick());
        }
        expect(store.countRemovedBy(10), 5);
        expect(store.countRemovedBy(50), 0);
        store.setLimit(10);
        expect(store.count, 10);
        expect(store.list().last.preview, 'item 5');
      },
    );

    test('delete returns the item so it can be restored in place', () {
      store.insertOrBump('a', ClipKind.text, tick());
      store.insertOrBump('b', ClipKind.text, tick());
      store.insertOrBump('c', ClipKind.text, tick());
      final b = store.list()[1];

      final removed = store.delete(b.id)!;
      expect(removed.content, 'b');
      expect(store.list().map((i) => i.preview), ['c', 'a']);

      store.restore(removed);
      expect(store.list().map((i) => i.preview), ['c', 'b', 'a']);
    });

    test('delete of an unknown id returns null', () {
      expect(store.delete(424242), isNull);
    });

    test('restoring into a full history still holds the limit', () {
      store.setLimit(10);
      for (var i = 0; i < 10; i++) {
        store.insertOrBump('item $i', ClipKind.text, tick());
      }
      final removed = store.delete(store.list().first.id)!;
      store.insertOrBump('fresh', ClipKind.text, tick());
      store.restore(removed);
      expect(store.count, 10);
    });

    test('clear removes everything and returns how many', () {
      store.insertOrBump('a', ClipKind.text, tick());
      store.insertOrBump('b', ClipKind.text, tick());
      expect(store.clear(), 2);
      expect(store.list(), isEmpty);
      expect(store.count, 0);
      expect(store.limit, 200, reason: 'clearing keeps the setting');
    });

    test('long text: the list holds a preview, contentOf the whole text', () {
      final long = 'x' * 50000;
      store.insertOrBump(long, ClipKind.text, tick());
      final item = store.list().single;
      expect(item.preview.length, ClipItem.previewLength);
      expect(item.isTruncated, isTrue);
      expect(store.contentOf(item.id), long);
    });

    test('keeps odd text exactly: quotes, NUL-free control chars, emoji', () {
      const odd =
          "it's \"quoted\"; DROP TABLE clip_items;--\u202E \u{1F600}\n\t";
      store.insertOrBump(odd, ClipKind.text, tick());
      expect(store.contentOf(store.list().single.id), odd);
    });

    test('rejects empty text and text over 1 MB', () {
      expect(
        () => store.insertOrBump('', ClipKind.text, tick()),
        throwsArgumentError,
      );
      expect(
        () => store.insertOrBump(
          'x' * (ClipItem.maxContentLength + 1),
          ClipKind.text,
          tick(),
        ),
        throwsArgumentError,
      );
      expect(store.count, 0);
    });

    test('bumpIfPresent moves saved text to the top and says so', () {
      store.insertOrBump('a', ClipKind.text, tick());
      store.insertOrBump('b', ClipKind.link, tick());
      final created = store.list().last.createdAt;

      expect(store.bumpIfPresent('a', tick()), isTrue);
      final items = store.list();
      expect(items.map((i) => i.preview), ['a', 'b']);
      expect(items.first.createdAt, created);
      expect(items.last.kind, ClipKind.link, reason: 'kind is not changed');
      expect(store.count, 2);
    });

    test('bumpIfPresent adds nothing for text that is not saved', () {
      store.insertOrBump('a', ClipKind.text, tick());
      expect(store.bumpIfPresent('unknown', tick()), isFalse);
      expect(store.bumpIfPresent('', tick()), isFalse);
      expect(store.list().map((i) => i.preview), ['a']);
    });

    test('bumpIfPresent in the same millisecond keeps the order strict', () {
      store.insertOrBump('first', ClipKind.text, 5000);
      store.insertOrBump('second', ClipKind.text, 5000);
      expect(store.bumpIfPresent('first', 5000), isTrue);
      expect(store.list().map((i) => i.preview), ['first', 'second']);
    });

    test('bumpIfPresent finds long text by its whole content', () {
      final long = 'x' * 50000;
      store.insertOrBump(long, ClipKind.text, tick());
      store.insertOrBump('other', ClipKind.text, tick());
      expect(store.bumpIfPresent(long, tick()), isTrue);
      expect(store.list().first.isTruncated, isTrue);
    });

    test('settings: unset is null; a written value is read back', () {
      expect(store.readSetting('picker_shortcut'), isNull);
      expect(store.readSetting('paste_mode'), isNull);
      store.writeSetting('picker_shortcut', 'shift+meta+v');
      store.writeSetting('paste_mode', 'copy_only');
      expect(store.readSetting('picker_shortcut'), 'shift+meta+v');
      expect(store.readSetting('paste_mode'), 'copy_only');
      store.writeSetting('paste_mode', 'auto');
      expect(store.readSetting('paste_mode'), 'auto');
    });

    test('settings: only the known keys, with short non-empty values', () {
      expect(() => store.writeSetting('other', 'x'), throwsArgumentError);
      expect(() => store.readSetting('other'), throwsArgumentError);
      expect(() => store.writeSetting('paste_mode', ''), throwsArgumentError);
      expect(
        () => store.writeSetting('paste_mode', 'x' * 65),
        throwsArgumentError,
      );
      expect(store.readSetting('paste_mode'), isNull);
    });

    test('clearing the history keeps the picker settings', () {
      store.writeSetting('picker_shortcut', 'ctrl+alt+k');
      store.insertOrBump('a', ClipKind.text, tick());
      store.clear();
      expect(store.readSetting('picker_shortcut'), 'ctrl+alt+k');
    });

    test('accepts text of exactly 1 MB', () {
      store.insertOrBump(
        'x' * ClipItem.maxContentLength,
        ClipKind.text,
        tick(),
      );
      expect(store.count, 1);
    });

    // M1.7 auto-delete (docs/design/settings-and-expiry.md, "Auto-delete").
    group('auto-delete', () {
      void seed() {
        store.insertOrBump('old', ClipKind.text, 100);
        store.insertOrBump('middle', ClipKind.text, 200);
        store.insertOrBump('new', ClipKind.text, 300);
      }

      test('listSince leaves out items last copied before the cutoff (R1); '
          'the cutoff itself is kept', () {
        seed();
        expect(store.listSince(200).map((i) => i.preview), ['new', 'middle']);
        expect(store.listSince(0).length, 3);
        expect(store.listSince(301), isEmpty);
      });

      test('copying an old item again keeps it (D2 A: last copy counts)', () {
        seed();
        store.insertOrBump('old', ClipKind.text, 400);
        expect(store.listSince(250).map((i) => i.preview), ['old', 'new']);
      });

      test('countOlderThan counts only items before the cutoff, from an '
          'optional lower bound', () {
        seed();
        expect(store.countOlderThan(250), 2);
        expect(store.countOlderThan(250, notBefore: 150), 1);
        expect(store.countOlderThan(100), 0);
      });

      test('deleteOlderThan removes them and says how many', () {
        seed();
        expect(store.deleteOlderThan(250), 2);
        expect(store.list().map((i) => i.preview), ['new']);
        expect(store.deleteOlderThan(250), 0);
      });

      test('setExpiryDays saves the setting and deletes in one step', () {
        seed();
        expect(store.setExpiryDays(7, deleteBefore: 150), 1);
        expect(store.readSetting(historyExpirySetting), '7');
        expect(store.list().map((i) => i.preview), ['new', 'middle']);
      });

      test('setExpiryDays without a cutoff deletes nothing', () {
        seed();
        expect(store.setExpiryDays(0), 0);
        expect(store.readSetting(historyExpirySetting), '0');
        expect(store.count, 3);
      });

      test('setExpiryDays accepts only 0, 1, 7 and 30', () {
        for (final bad in [-1, 2, 14, 31, 365]) {
          expect(() => store.setExpiryDays(bad), throwsArgumentError);
        }
        expect(store.readSetting(historyExpirySetting), isNot('2'));
      });

      test('the limit still applies after a delete', () {
        store.setLimit(10);
        for (var i = 0; i < 12; i++) {
          store.insertOrBump('item $i', ClipKind.text, 1000 + i);
        }
        expect(store.deleteOlderThan(1005), 3);
        expect(store.count, 7);
      });
    });
  });
}
