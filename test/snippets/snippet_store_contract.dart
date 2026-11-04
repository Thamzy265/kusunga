import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_store.dart';

/// Behaviour every [SnippetStore] must have, whatever it keeps data in.
void runSnippetStoreContract(String name, SnippetStore Function() create) {
  group('$name snippet contract', () {
    late SnippetStore store;
    var now = 1000;
    int tick() => now += 10;

    int add(String name, [String? content, SnippetType? type]) => store.insert(
      name: name,
      content: content ?? 'content of $name',
      type: type ?? SnippetType.other,
      nowMs: tick(),
    );

    List<String> names() => store.list().map((s) => s.name).toList();
    List<int> positions() => store.list().map((s) => s.position).toList();

    setUp(() {
      now = 1000;
      store = create();
    });
    tearDown(() => store.close());

    test('starts empty', () {
      expect(store.count, 0);
      expect(store.list(), isEmpty);
    });

    test('a new snippet goes at the end, in the order the user made', () {
      add('My mobile', '07700 900123', SnippetType.phone);
      add('Work email', 'will@example.com', SnippetType.email);
      final items = store.list();
      expect(names(), ['My mobile', 'Work email']);
      expect(positions(), [0, 1]);
      expect(items.first.type, SnippetType.phone);
      expect(items.first.preview, '07700 900123');
      expect(items.first.createdAt, items.first.updatedAt);
      expect(store.count, 2);
    });

    test('names and content may repeat', () {
      add('Work email', 'a@example.com');
      add('Work email', 'a@example.com');
      expect(store.count, 2);
    });

    test(
      'contentOf returns the whole text; a long one has a short preview',
      () {
        final long = 'x' * (ClipItem.previewLength + 50);
        final id = add('Long', long);
        final item = store.list().single;
        expect(item.isTruncated, isTrue);
        expect(item.preview.length, ClipItem.previewLength);
        expect(store.contentOf(id), long);
        expect(store.contentOf(999999), isNull);
      },
    );

    test('keeps NUL, RTL marks and emoji exactly', () {
      const odd = 'a\u0000b\u202Ec 🙂\n2nd line';
      final id = add('Odd', odd);
      expect(store.contentOf(id), odd);
      expect(store.list().single.preview, odd);
    });

    test('takes 1 MiB of content and refuses one byte more', () {
      final max = 'a' * ClipItem.maxContentLength;
      final id = add('Max', max);
      expect(store.contentOf(id)!.length, ClipItem.maxContentLength);
      expect(() => add('Over', '$maxé'), throwsArgumentError);
      expect(() => add('Empty', ''), throwsArgumentError);
    });

    test('refuses an empty, multi-line or over-100-character name', () {
      expect(() => add(''), throwsArgumentError);
      expect(() => add('two\nlines'), throwsArgumentError);
      expect(() => add('n' * 101), throwsArgumentError);
      // 100 characters, counted as characters (an emoji is one).
      add('🙂' * 100);
      expect(store.count, 1);
    });

    test('update changes name, content and type and keeps the position', () {
      add('A');
      final id = add('B');
      add('C');
      now = 5000;
      expect(
        store.update(
          id,
          name: 'B2',
          content: 'new',
          type: SnippetType.link,
          nowMs: now,
        ),
        isTrue,
      );
      final b = store.list()[1];
      expect(b.name, 'B2');
      expect(b.type, SnippetType.link);
      expect(store.contentOf(id), 'new');
      expect(b.updatedAt, 5000);
      expect(b.createdAt, lessThan(5000));
      expect(names(), ['A', 'B2', 'C']);
      expect(
        store.update(
          424242,
          name: 'x',
          content: 'x',
          type: SnippetType.other,
          nowMs: now,
        ),
        isFalse,
      );
      expect(
        () => store.update(
          id,
          name: '',
          content: 'x',
          type: SnippetType.other,
          nowMs: now,
        ),
        throwsArgumentError,
      );
    });

    test('move renumbers 0..n-1 in the new order', () {
      final a = add('A');
      add('B');
      final c = add('C');
      add('D');
      expect(store.move(c, 0), isTrue);
      expect(names(), ['C', 'A', 'B', 'D']);
      expect(positions(), [0, 1, 2, 3]);
      expect(store.move(a, 3), isTrue);
      expect(names(), ['C', 'B', 'D', 'A']);
      expect(positions(), [0, 1, 2, 3]);
      // Past the ends is clamped; a missing id moves nothing.
      expect(store.move(a, 99), isTrue);
      expect(names(), ['C', 'B', 'D', 'A']);
      expect(store.move(777, 0), isFalse);
    });

    test('delete returns the snippet and closes the gap', () {
      add('A');
      final b = add('B', 'bee', SnippetType.address);
      add('C');
      final record = store.delete(b)!;
      expect(record.name, 'B');
      expect(record.content, 'bee');
      expect(record.type, SnippetType.address);
      expect(record.position, 1);
      expect(names(), ['A', 'C']);
      expect(positions(), [0, 1]);
      expect(store.delete(b), isNull);
    });

    test('restore puts a deleted snippet back where it was (Undo)', () {
      add('A');
      final b = add('B', 'bee');
      add('C');
      final created = store.list()[1].createdAt;
      final record = store.delete(b)!;
      store.restore(record);
      expect(names(), ['A', 'B', 'C']);
      expect(positions(), [0, 1, 2]);
      final back = store.list()[1];
      expect(back.createdAt, created);
      expect(store.contentOf(back.id), 'bee');
    });

    test('restore at a position past the end goes last', () {
      add('A');
      final c = add('C');
      final record = store.delete(c)!;
      store.delete(store.list().single.id);
      store.restore(record);
      expect(names(), ['C']);
      expect(positions(), [0]);
    });

    test('at most 1,000 snippets', () {
      for (var i = 0; i < SnippetStore.maxCount; i++) {
        add('s$i', 'c$i');
      }
      expect(store.count, SnippetStore.maxCount);
      expect(() => add('one more'), throwsA(isA<SnippetCapReached>()));
      expect(store.count, SnippetStore.maxCount);
      // Undo of a delete is refused at the cap too.
      final record = store.delete(store.list().first.id)!;
      add('fills the gap');
      expect(() => store.restore(record), throwsA(isA<SnippetCapReached>()));
      expect(store.count, SnippetStore.maxCount);
    });
  });
}
