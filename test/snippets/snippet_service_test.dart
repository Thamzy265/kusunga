import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_store.dart';

import '../support/fakes.dart';

/// A store whose calls fail on demand, like a full disk.
class FlakySnippetStore extends MemorySnippetStore {
  bool failWrites = false;
  bool failReads = false;
  bool capped = false;

  void _check() {
    if (failWrites) throw StateError('disk full');
  }

  @override
  List<SnippetItem> list() {
    if (failReads) throw StateError('read');
    return super.list();
  }

  @override
  int insert({
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
    String? shortcut,
  }) {
    _check();
    if (capped) throw SnippetCapReached();
    return super.insert(
      name: name,
      content: content,
      type: type,
      nowMs: nowMs,
      shortcut: shortcut,
    );
  }

  @override
  bool update(
    int id, {
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
    String? shortcut,
  }) {
    _check();
    return super.update(
      id,
      name: name,
      content: content,
      type: type,
      nowMs: nowMs,
      shortcut: shortcut,
    );
  }

  @override
  bool move(int id, int toIndex) {
    _check();
    return super.move(id, toIndex);
  }

  @override
  SnippetRecord? delete(int id) {
    _check();
    return super.delete(id);
  }

  @override
  void restore(SnippetRecord record) {
    _check();
    super.restore(record);
  }
}

void main() {
  late FlakySnippetStore store;
  late FakeLog log;
  late List<String> written;
  var now = 1000;

  SnippetService make({bool editable = true, bool writeOk = true}) =>
      SnippetService(
        store: store,
        log: log,
        editable: editable,
        clock: () => now += 10,
        writeClipboard: (text) async {
          written.add(text);
          return writeOk;
        },
      );

  setUp(() {
    store = FlakySnippetStore();
    log = FakeLog();
    written = [];
    now = 1000;
  });

  test('loads what is saved, in order', () {
    store.insert(name: 'A', content: 'a', type: SnippetType.other, nowMs: 1);
    store.insert(name: 'B', content: 'b', type: SnippetType.other, nowMs: 2);
    final s = make();
    expect(s.items.map((i) => i.name), ['A', 'B']);
    expect(s.canEdit, isTrue);
    expect(s.banners, isEmpty);
  });

  test('save creates a snippet with the name made one line', () {
    final s = make();
    var notified = 0;
    s.addListener(() => notified++);
    final r = s.save(
      name: '  My\nmobile ',
      content: '07700 900123',
      type: SnippetType.phone,
    );
    expect(r.outcome, SnippetSave.saved);
    expect(r.id, isNotNull);
    expect(s.items.single.name, 'My mobile');
    expect(s.items.single.type, SnippetType.phone);
    expect(s.textOf(r.id!), '07700 900123');
    expect(notified, greaterThan(0));
  });

  test('save with an id edits that snippet', () {
    final s = make();
    final id = s.save(name: 'A', content: 'a', type: SnippetType.other).id!;
    final r = s.save(
      id: id,
      name: 'A2',
      content: 'changed',
      type: SnippetType.email,
    );
    expect(r.outcome, SnippetSave.saved);
    expect(r.id, id);
    expect(s.items.single.name, 'A2');
    expect(s.textOf(id), 'changed');
  });

  test('invalid fields are refused with every problem and nothing saved', () {
    final s = make();
    final r = s.save(name: ' ', content: '', type: SnippetType.other);
    expect(r.outcome, SnippetSave.invalid);
    expect(r.problems, {SnippetProblem.emptyName, SnippetProblem.emptyContent});
    expect(s.items, isEmpty);
    expect(log.codes, isEmpty);
  });

  test('a failed save logs snippetSaveFailed, keeps nothing half-saved', () {
    final s = make();
    store.failWrites = true;
    final r = s.save(name: 'A', content: 'a', type: SnippetType.other);
    expect(r.outcome, SnippetSave.failed);
    expect(s.items, isEmpty);
    expect(log.codes, [LogCode.snippetSaveFailed]);
  });

  test('at 1,000 snippets a new one is refused and logged', () {
    final s = make();
    store.capped = true;
    final r = s.save(name: 'A', content: 'a', type: SnippetType.other);
    expect(r.outcome, SnippetSave.capReached);
    expect(log.codes, [LogCode.snippetCapReached]);
  });

  test('atCap is true at 1,000 snippets; editing one is still allowed', () {
    for (var i = 0; i < SnippetStore.maxCount; i++) {
      store.insert(
        name: 's$i',
        content: 'c',
        type: SnippetType.other,
        nowMs: i,
      );
    }
    final s = make();
    expect(s.atCap, isTrue);
    expect(s.canCreate, isFalse);
    final r = s.save(name: 'x', content: 'x', type: SnippetType.other);
    expect(r.outcome, SnippetSave.capReached);
    expect(
      s
          .save(
            id: s.items.first.id,
            name: 'edited',
            content: 'c',
            type: SnippetType.other,
          )
          .outcome,
      SnippetSave.saved,
    );
  });

  test('move renumbers; a failed move keeps the old order and logs', () {
    final s = make();
    for (final n in ['A', 'B', 'C']) {
      s.save(name: n, content: n, type: SnippetType.other);
    }
    final c = s.items.last.id;
    expect(s.move(c, 0), isTrue);
    expect(s.items.map((i) => i.name), ['C', 'A', 'B']);
    store.failWrites = true;
    expect(s.move(c, 2), isFalse);
    expect(s.items.map((i) => i.name), ['C', 'A', 'B']);
    expect(log.codes, [LogCode.snippetMoveFailed]);
  });

  test('delete then undo puts it back; a failed delete keeps the row', () {
    final s = make();
    for (final n in ['A', 'B', 'C']) {
      s.save(name: n, content: n, type: SnippetType.other);
    }
    final b = s.items[1].id;
    final deleted = s.delete(b);
    expect(deleted.failed, isFalse);
    expect(s.items.map((i) => i.name), ['A', 'C']);
    expect(s.undo(deleted.record!), isTrue);
    expect(s.items.map((i) => i.name), ['A', 'B', 'C']);

    store.failWrites = true;
    final failed = s.delete(s.items.first.id);
    expect(failed.failed, isTrue);
    expect(failed.record, isNull);
    expect(s.items.length, 3);
    expect(log.codes, [LogCode.snippetDeleteFailed]);
  });

  test('a read that fails shows the read banner; Try again clears it', () {
    store.failReads = true;
    final s = make();
    expect(s.banners, {SnippetBanner.readError});
    expect(log.codes, [LogCode.readFailed]);
    store.failReads = false;
    s.reload();
    expect(s.banners, isEmpty);
  });

  test('memory-only or incompatible: editing is off, the banner shows, '
      'loaded snippets still copy', () async {
    store.insert(name: 'A', content: 'kept', type: SnippetType.other, nowMs: 1);
    final s = make(editable: false);
    expect(s.canEdit, isFalse);
    expect(s.canCreate, isFalse);
    expect(s.banners, {SnippetBanner.unavailable});
    expect(log.codes, [LogCode.snippetsUnavailable]);
    final r = s.save(name: 'B', content: 'b', type: SnippetType.other);
    expect(r.outcome, SnippetSave.unavailable);
    expect(store.count, 1);
    expect(s.move(s.items.first.id, 0), isFalse);
    expect(s.delete(s.items.first.id).record, isNull);
    expect(await s.copy(s.items.first.id), isTrue);
    expect(written, ['kept']);
  });

  test('copy writes the whole text through the own-change writer', () async {
    final s = make(writeOk: false);
    final id = s.save(name: 'A', content: 'whole', type: SnippetType.other).id!;
    expect(await s.copy(id), isFalse);
    expect(written, ['whole']);
    expect(await s.copy(999), isFalse);
  });

  test('no name, content or type ever reaches the log', () {
    final s = make();
    store.failWrites = true;
    s.save(name: 'Secret name', content: 'secret', type: SnippetType.phone);
    s.move(1, 0);
    s.delete(1);
    expect(log.details.whereType<int>(), isEmpty);
  });

  test('after close nothing is changed', () {
    final s = make();
    s.close();
    expect(
      s.save(name: 'A', content: 'a', type: SnippetType.other).outcome,
      SnippetSave.unavailable,
    );
    expect(s.items, isEmpty);
  });
}
