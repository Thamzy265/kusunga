// Tester (M1.2): property tests for the limit and dedupe rules, run on both
// stores with the same random sequences against a tiny reference model.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_prop_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final makers = <String, HistoryStore Function()>{
    'MemoryHistoryStore': MemoryHistoryStore.new,
    'SqliteHistoryStore': () =>
        SqliteHistoryStore.open(path: '${dir.path}/k.db', keyHex: _key),
  };

  for (final MapEntry(key: name, value: create) in makers.entries) {
    group(name, () {
      late HistoryStore store;
      setUp(() => store = create());
      tearDown(() => store.close());

      for (final seed in [1, 2, 3, 4, 5, 6]) {
        test('random copies, limit changes, deletes and clears (seed $seed): '
            'never more than N, no duplicates, newest copy first', () {
          final random = Random(seed);
          // Few distinct texts, so duplicates and bumps are common.
          final pool = [
            for (var i = 0; i < 40; i++) 'text $i',
            'https://example.com/$seed',
            ' padded ',
            '\u{1F600}',
          ];
          final model = <String>[]; // newest first
          var limit = HistoryStore.defaultLimit;
          var now = 10000;

          void check(String step) {
            final items = store.list();
            final texts = [for (final i in items) store.contentOf(i.id)!];
            expect(texts, model, reason: step);
            expect(store.count, model.length, reason: step);
            expect(store.count, lessThanOrEqualTo(store.limit), reason: step);
            expect(texts.toSet().length, texts.length, reason: 'dup: $step');
            for (var i = 1; i < items.length; i++) {
              expect(
                items[i - 1].lastCopiedAt,
                greaterThan(items[i].lastCopiedAt),
                reason: 'times must strictly fall down the list: $step',
              );
            }
          }

          for (var step = 0; step < 300; step++) {
            final roll = random.nextInt(100);
            final label = 'step $step roll $roll';
            if (roll < 70) {
              final text = pool[random.nextInt(pool.length)];
              // The clock may stand still or even go backwards.
              now += random.nextInt(7) - 2;
              store.insertOrBump(text, ClipKind.text, now);
              model
                ..remove(text)
                ..insert(0, text);
              if (model.length > limit) model.removeRange(limit, model.length);
            } else if (roll < 80) {
              limit = [10, 11, 15, 25, 40, 200, 5000][random.nextInt(7)];
              final expectedRemoved = max(0, model.length - limit);
              expect(
                store.countRemovedBy(limit),
                expectedRemoved,
                reason: label,
              );
              store.setLimit(limit);
              if (model.length > limit) model.removeRange(limit, model.length);
            } else if (roll < 90 && model.isNotEmpty) {
              final items = store.list();
              final victim = items[random.nextInt(items.length)];
              final record = store.delete(victim.id)!;
              model.remove(record.content);
              check('after delete: $label');
              // Undo straight away: the item comes back where it was.
              store.restore(record);
              model.insert(
                items.indexWhere((i) => i.id == victim.id).clamp(0, 99999),
                record.content,
              );
            } else if (roll < 92) {
              store.clear();
              model.clear();
            } else {
              // Bad limits are refused and change nothing.
              final bad = [9, 5001, 0, -1, 1 << 40][random.nextInt(5)];
              expect(() => store.setLimit(bad), throwsArgumentError);
              expect(() => store.countRemovedBy(bad), throwsArgumentError);
            }
            expect(store.limit, limit, reason: label);
            check(label);
          }
        });
      }

      test('limit boundaries: 9 and 5,001 are refused; 10 and 5,000 work', () {
        for (final bad in [9, 5001, 0, -1, -10, 1 << 62, -(1 << 62)]) {
          expect(
            () => store.setLimit(bad),
            throwsArgumentError,
            reason: '$bad',
          );
          expect(store.limit, 200, reason: 'a refused limit changes nothing');
        }
        for (final good in [10, 5000]) {
          store.setLimit(good);
          expect(store.limit, good);
        }
      });

      test('a limit of 10 keeps exactly the newest ten of 500 copies', () {
        store.setLimit(10);
        for (var i = 0; i < 500; i++) {
          store.insertOrBump('copy $i', ClipKind.text, 1000 + i);
        }
        expect(store.count, 10);
        expect(store.list().first.preview, 'copy 499');
        expect(store.list().last.preview, 'copy 490');
      });

      test('lowering then raising the limit does not bring items back', () {
        for (var i = 0; i < 30; i++) {
          store.insertOrBump('copy $i', ClipKind.text, 1000 + i);
        }
        store.setLimit(10);
        store.setLimit(200);
        expect(store.count, 10);
      });

      test('the same text copied 1,000 times is one item', () {
        for (var i = 0; i < 1000; i++) {
          store.insertOrBump('same', ClipKind.text, 5);
        }
        expect(store.count, 1);
      });

      test('the clock going backwards still puts the newest copy on top', () {
        store.insertOrBump('late', ClipKind.text, 9000);
        store.insertOrBump('early', ClipKind.text, 1000);
        store.insertOrBump('earlier', ClipKind.text, 10);
        expect(store.list().map((i) => i.preview), [
          'earlier',
          'early',
          'late',
        ]);
      });

      test('a link copied again as text-looking input keeps one item', () {
        store.insertOrBump('https://example.com', ClipKind.link, 1);
        store.insertOrBump('https://example.com', ClipKind.text, 2);
        expect(store.count, 1);
      });

      test('Undo after a newer copy of the same text keeps one item and the '
          'newer time', () {
        // Bug repro (BUG-6, memory store): Undo puts the old record back at
        // its old time and drops the newer copy's time, so the item the
        // user just copied again sinks below older items.
        store.insertOrBump('a', ClipKind.text, 100);
        final id = store.list().single.id;
        final record = store.delete(id)!;
        store.insertOrBump('b', ClipKind.text, 150);
        store.insertOrBump('a', ClipKind.text, 200); // copied again
        store.restore(record);

        final items = store.list();
        expect(items.map((i) => i.preview), ['a', 'b']);
        expect(items.first.lastCopiedAt, 200);
        expect(items.first.createdAt, 100, reason: 'keeps the first time');
      });

      test('Undo of an item deleted from a full history holds the limit and '
          'has no duplicates', () {
        store.setLimit(10);
        for (var i = 0; i < 10; i++) {
          store.insertOrBump('item $i', ClipKind.text, 100 + i);
        }
        final record = store.delete(store.list()[3].id)!;
        for (var i = 0; i < 5; i++) {
          store.insertOrBump('new $i', ClipKind.text, 500 + i);
        }
        store.restore(record);
        final texts = store.list().map((i) => i.preview).toList();
        expect(texts.length, lessThanOrEqualTo(10));
        expect(texts.toSet().length, texts.length);
      });

      test('deleting an id twice, or after clear, returns null', () {
        final id = store.insertOrBump('x', ClipKind.text, 1);
        expect(store.delete(id), isNotNull);
        expect(store.delete(id), isNull);
        store.insertOrBump('y', ClipKind.text, 2);
        final yid = store.list().single.id;
        store.clear();
        expect(store.delete(yid), isNull);
      });

      test('contentOf an unknown id is null', () {
        expect(store.contentOf(-5), isNull);
        expect(store.contentOf(99999), isNull);
      });
    });
  }

  test('the limit and the trim survive a close and reopen on disk', () {
    final a = SqliteHistoryStore.open(path: '${dir.path}/r.db', keyHex: _key);
    for (var i = 0; i < 40; i++) {
      a.insertOrBump('copy $i', ClipKind.text, 1000 + i);
    }
    a.setLimit(10);
    a.close();

    final b = SqliteHistoryStore.open(path: '${dir.path}/r.db', keyHex: _key);
    expect(b.limit, 10);
    expect(b.count, 10);
    expect(b.list().first.preview, 'copy 39');
    b.close();
  });

  test('a refused limit is not saved to disk', () {
    final a = SqliteHistoryStore.open(path: '${dir.path}/r.db', keyHex: _key);
    expect(() => a.setLimit(5001), throwsArgumentError);
    a.close();
    final b = SqliteHistoryStore.open(path: '${dir.path}/r.db', keyHex: _key);
    expect(b.limit, 200);
    b.close();
  });
}
