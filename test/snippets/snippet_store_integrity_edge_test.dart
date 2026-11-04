// Tester probes for M1.4 data integrity (design note, "Data" and "Top 3
// qualities"): the order the user set is exactly the order kept, whatever
// mix of moves, deletes, Undos, edits and inserts came before, on the memory
// store and on the encrypted file.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:sqlite3/sqlite3.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

typedef _Make = SnippetStore Function(Directory dir);

final _factories = <String, _Make>{
  'memory': (_) => MemorySnippetStore(),
  'encrypted file': (dir) {
    final history = SqliteHistoryStore.open(
      path: '${dir.path}/kusunga.db',
      keyHex: _key,
    );
    addTearDown(history.close);
    return history.snippetStore();
  },
};

void main() {
  for (final entry in _factories.entries) {
    group('${entry.key} store: order integrity', () {
      late Directory dir;
      late SnippetStore store;
      var now = 1000;

      setUp(() {
        dir = Directory.systemTemp.createTempSync('kusunga_snip_int_');
        store = entry.value(dir);
        now = 1000;
      });
      tearDown(() {
        store.close();
        dir.deleteSync(recursive: true);
      });

      int add(String name, [String? content]) => store.insert(
        name: name,
        content: content ?? 'content of $name',
        type: SnippetType.other,
        nowMs: now += 10,
      );

      List<String> names() => store.list().map((s) => s.name).toList();
      List<int> positions() => store.list().map((s) => s.position).toList();

      void expectDense() {
        expect(
          positions(),
          List.generate(store.count, (i) => i),
          reason: 'positions are exactly 0..n-1',
        );
      }

      test('moves at the ends: clamped, never lost, never reordered', () {
        final a = add('A');
        final b = add('B');
        final c = add('C');
        // First item up past the top, last item down past the bottom.
        expect(store.move(a, -1), isTrue);
        expect(store.move(a, -1000), isTrue);
        expect(names(), ['A', 'B', 'C']);
        expect(store.move(c, 3), isTrue);
        expect(store.move(c, 1 << 30), isTrue);
        expect(names(), ['A', 'B', 'C']);
        // Top to bottom, then bottom to top.
        store.move(a, 2);
        expect(names(), ['B', 'C', 'A']);
        store.move(a, 0);
        expect(names(), ['A', 'B', 'C']);
        // To where it already is.
        store.move(b, 1);
        expect(names(), ['A', 'B', 'C']);
        expectDense();
      });

      test('one snippet alone, and a missing id, change nothing', () {
        final only = add('Only');
        expect(store.move(only, 0), isTrue);
        expect(store.move(only, 5), isTrue);
        expect(store.move(only + 1000, 0), isFalse);
        expect(names(), ['Only']);
        expectDense();
        store.delete(only);
        expect(store.move(only, 0), isFalse);
        expect(store.count, 0);
      });

      test('a move changes only the order: not text, type or times', () {
        final a = add('A', 'alpha');
        add('B', 'beta');
        final before = store.list().firstWhere((s) => s.id == a);
        store.move(a, 1);
        final after = store.list().firstWhere((s) => s.id == a);
        expect(after.position, 1);
        expect(after.name, before.name);
        expect(after.type, before.type);
        expect(after.createdAt, before.createdAt);
        expect(after.updatedAt, before.updatedAt);
        expect(store.contentOf(a), 'alpha');
      });

      test('rapid moves of one snippet up and down end where they should', () {
        final ids = [for (var i = 0; i < 12; i++) add('s$i')];
        final moved = ids[5];
        final model = [...ids];
        for (var i = 0; i < 300; i++) {
          final to = i.isEven ? 11 : 0;
          model.remove(moved);
          model.insert(to, moved);
          expect(store.move(moved, to), isTrue);
        }
        expect(store.list().map((s) => s.id), model);
        expectDense();
        // Single steps, like the Move up / Move down button held down.
        for (var i = 0; i < 40; i++) {
          final from = store.list().indexWhere((s) => s.id == moved);
          final to = (from + (i < 20 ? -1 : 1)).clamp(0, 11);
          model
            ..remove(moved)
            ..insert(to, moved);
          store.move(moved, to);
        }
        expect(store.list().map((s) => s.id), model);
        expectDense();
      });

      test('Undo after other changes puts it back at its old place, clamped, '
          'and the rest keeps the order the user set', () {
        add('A');
        final b = add('B');
        final c = add('C');
        add('D');
        final recordB = store.delete(b)!;
        expect(recordB.position, 1);
        // Other changes before Undo: a new snippet, a move, an edit, and a
        // delete.
        add('E');
        store.move(c, 3);
        store.update(
          c,
          name: 'C2',
          content: 'new',
          type: SnippetType.link,
          nowMs: 5000,
        );
        expect(names(), ['A', 'D', 'E', 'C2']);
        store.restore(recordB);
        expect(names(), ['A', 'B', 'D', 'E', 'C2']);
        expectDense();
        // The last one is removed, then Undo of something that was last:
        // it goes last, not past the end.
        final last = store.list().last.id;
        final recordLast = store.delete(last)!;
        store.delete(store.list().last.id);
        store.delete(store.list().last.id);
        store.restore(recordLast);
        expect(names().last, 'C2');
        expectDense();
      });

      test('the same record put back twice makes two snippets, both with a '
          'place', () {
        add('A');
        final b = add('B');
        final record = store.delete(b)!;
        store.restore(record);
        store.restore(record);
        expect(names(), ['A', 'B', 'B']);
        expectDense();
        expect(store.list().map((s) => s.id).toSet().length, 3);
      });

      test('at 1,000: every kind of change except adding still works, and a '
          'refused Undo or add leaves list and order exactly as they were', () {
        for (var i = 0; i < SnippetStore.maxCount; i++) {
          add('s$i', 'c$i');
        }
        final snapshot = store.list().map((s) => s.id).toList();
        // Edit, move and delete are allowed at the cap.
        final mid = snapshot[500];
        expect(
          store.update(
            mid,
            name: 'edited',
            content: 'edited',
            type: SnippetType.phone,
            nowMs: 9,
          ),
          isTrue,
        );
        expect(store.move(mid, 0), isTrue);
        expect(store.move(mid, 500), isTrue);
        expect(store.list().map((s) => s.id), snapshot);
        // Refused add.
        expect(() => add('too many'), throwsA(isA<SnippetCapReached>()));
        expect(store.list().map((s) => s.id), snapshot);
        // Delete one, something else takes the free place, then Undo.
        final record = store.delete(snapshot[10])!;
        final after = store.list().map((s) => s.id).toList();
        add('takes the place');
        final full = store.list().map((s) => s.id).toList();
        expect(full.length, SnippetStore.maxCount);
        expect(() => store.restore(record), throwsA(isA<SnippetCapReached>()));
        expect(store.list().map((s) => s.id), full);
        expect(after.length, SnippetStore.maxCount - 1);
        expectDense();
        // A failed Undo is not partly applied: it can succeed later.
        store.delete(full.last);
        store.restore(record);
        expect(store.count, SnippetStore.maxCount);
        expect(names()[10], 's10');
        expectDense();
      });

      test('a record that the checks would refuse never gets in', () {
        add('A');
        final bad = SnippetRecord(
          name: 'x' * 101,
          content: 'ok',
          type: SnippetType.other,
          position: 0,
          createdAt: 1,
          updatedAt: 1,
        );
        expect(() => store.restore(bad), throwsA(isA<ArgumentError>()));
        final multi = SnippetRecord(
          name: 'two\nlines',
          content: 'ok',
          type: SnippetType.other,
          position: 0,
          createdAt: 1,
          updatedAt: 1,
        );
        expect(() => store.restore(multi), throwsA(isA<ArgumentError>()));
        final empty = SnippetRecord(
          name: 'ok',
          content: '',
          type: SnippetType.other,
          position: 0,
          createdAt: 1,
          updatedAt: 1,
        );
        expect(() => store.restore(empty), throwsA(isA<ArgumentError>()));
        expect(names(), ['A']);
        expectDense();
      });

      test('random operations match a simple model, with 0..n-1 positions '
          'after every step', () {
        final random = Random(20261104);
        final model = <int>[]; // ids in order
        final content = <int, String>{};
        final records = <SnippetRecord>[];
        for (var step = 0; step < 700; step++) {
          switch (random.nextInt(6)) {
            case 0:
            case 1:
              if (model.length >= SnippetStore.maxCount) break;
              final text = 'c$step ${'x' * random.nextInt(50)}';
              final id = add('n$step', text);
              model.add(id);
              content[id] = text;
            case 2:
              if (model.isEmpty) break;
              final id = model[random.nextInt(model.length)];
              final to = random.nextInt(model.length + 6) - 3;
              final i = model.indexOf(id);
              final next = List.of(model)..removeAt(i);
              next.insert(to.clamp(0, next.length), id);
              model
                ..clear()
                ..addAll(next);
              expect(store.move(id, to), isTrue);
            case 3:
              if (model.isEmpty) break;
              final id = model[random.nextInt(model.length)];
              final record = store.delete(id)!;
              expect(record.position, model.indexOf(id));
              model.remove(id);
              content.remove(id);
              records.add(record);
            case 4:
              if (records.isEmpty || model.length >= SnippetStore.maxCount) {
                break;
              }
              final record = records.removeAt(random.nextInt(records.length));
              store.restore(record);
              final at = record.position.clamp(0, model.length);
              // The restored row is the one in the list that is not in the
              // model yet.
              final id = store
                  .list()
                  .map((s) => s.id)
                  .firstWhere((i) => !model.contains(i));
              model.insert(at, id);
              content[id] = record.content;
            case 5:
              if (model.isEmpty) break;
              final id = model[random.nextInt(model.length)];
              final text = 'edited $step';
              expect(
                store.update(
                  id,
                  name: 'e$step',
                  content: text,
                  type: SnippetType.values[random.nextInt(5)],
                  nowMs: now += 10,
                ),
                isTrue,
              );
              content[id] = text;
          }
          expect(
            store.list().map((s) => s.id).toList(),
            model,
            reason: 'step $step',
          );
          expect(positions(), List.generate(model.length, (i) => i));
        }
        for (final id in model) {
          expect(store.contentOf(id), content[id]);
        }
      });
    });
  }

  group('encrypted file: the order survives a restart and is repaired', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kusunga_snip_int2_');
      path = '${dir.path}/kusunga.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('moves, delete and Undo are still there after close and reopen', () {
      var history = SqliteHistoryStore.open(path: path, keyHex: _key);
      var store = history.snippetStore();
      final ids = [
        for (var i = 0; i < 8; i++)
          store.insert(
            name: 's$i',
            content: 'c$i',
            type: SnippetType.other,
            nowMs: i,
          ),
      ];
      store.move(ids[0], 7);
      store.move(ids[6], 1);
      final record = store.delete(ids[3])!;
      store.restore(record);
      final expected = [for (final s in store.list()) s.name];
      history.close();

      history = SqliteHistoryStore.open(path: path, keyHex: _key);
      store = history.snippetStore();
      expect([for (final s in store.list()) s.name], expected);
      expect(store.list().map((s) => s.position), List.generate(8, (i) => i));
      history.close();
    });

    test('gaps and ties in position (a hand-edited or older file) read in a '
        'stable order and the next move makes them 0..n-1 again', () {
      final history = SqliteHistoryStore.open(path: path, keyHex: _key);
      final store = history.snippetStore();
      final a = store.insert(
        name: 'A',
        content: 'a',
        type: SnippetType.other,
        nowMs: 1,
      );
      final b = store.insert(
        name: 'B',
        content: 'b',
        type: SnippetType.other,
        nowMs: 2,
      );
      final c = store.insert(
        name: 'C',
        content: 'c',
        type: SnippetType.other,
        nowMs: 3,
      );
      history.close();
      final raw = sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");
      raw.execute('UPDATE snippets SET position = 9 WHERE id = $a');
      raw.execute('UPDATE snippets SET position = 4 WHERE id = $b');
      raw.execute('UPDATE snippets SET position = 4 WHERE id = $c');
      raw.close();

      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      final s = again.snippetStore();
      // Ties break by id, so the order is the same on every start.
      expect(s.list().map((x) => x.name), ['B', 'C', 'A']);
      expect(s.list().map((x) => x.name), ['B', 'C', 'A']);
      s.move(c, 0);
      expect(s.list().map((x) => x.name), ['C', 'B', 'A']);
      expect(s.list().map((x) => x.position), [0, 1, 2]);
      again.close();
    });
  });
}
