// Shortcuts in both snippet stores, and both ignored-app stores: the same
// behaviour whatever keeps the data.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_shortcut.dart';
import 'package:kusunga/snippets/snippet_store.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

SqliteHistoryStore _openSqlite() {
  final dir = Directory.systemTemp.createTempSync('kusunga_sc_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final history = SqliteHistoryStore.open(
    path: '${dir.path}/kusunga.db',
    keyHex: _key,
  );
  addTearDown(history.close);
  return history;
}

void main() {
  _snippetContract('memory', MemorySnippetStore.new);
  _snippetContract('sqlite', () => _openSqlite().snippetStore());
  _ignoredContract('memory', MemoryIgnoredAppStore.new);
  _ignoredContract('sqlite', () => _openSqlite().ignoredAppStore());
}

void _snippetContract(String name, SnippetStore Function() create) {
  group('$name snippet store: shortcuts', () {
    late SnippetStore store;
    setUp(() => store = create());

    int add(String name, String? shortcut) => store.insert(
      name: name,
      content: 'content of $name',
      type: SnippetType.other,
      nowMs: 1,
      shortcut: shortcut,
    );

    test('a snippet keeps its shortcut, or none', () {
      add('Work email', ';email');
      add('No code', null);
      expect(store.list().map((s) => s.shortcut), [';email', null]);
    });

    test('update sets, changes and removes the shortcut', () {
      final id = add('Work email', null);
      bool update(String? shortcut) => store.update(
        id,
        name: 'Work email',
        content: 'x',
        type: SnippetType.email,
        nowMs: 2,
        shortcut: shortcut,
      );
      expect(update(';em'), isTrue);
      expect(store.list().single.shortcut, ';em');
      expect(update(';work'), isTrue);
      expect(store.list().single.shortcut, ';work');
      expect(update(null), isTrue);
      expect(store.list().single.shortcut, isNull);
    });

    test('a snippet may keep its own shortcut on update', () {
      final id = add('Work email', ';email');
      expect(
        store.update(
          id,
          name: 'Renamed',
          content: 'x',
          type: SnippetType.other,
          nowMs: 2,
          shortcut: ';email',
        ),
        isTrue,
      );
      expect(store.list().single.shortcut, ';email');
    });

    test('a clash is refused in the save itself and nothing changes', () {
      final a = add('Work email', ';email');
      for (final clash in [
        (';email', ShortcutClashKind.same),
        (';emailx', ShortcutClashKind.otherIsStart),
        (';em', ShortcutClashKind.newIsStart),
      ]) {
        expect(
          () => add('Other', clash.$1),
          throwsA(
            isA<ShortcutTaken>()
                .having((e) => e.clash.kind, 'kind', clash.$2)
                .having((e) => e.clash.otherId, 'otherId', a)
                .having((e) => e.clash.otherName, 'otherName', 'Work email'),
          ),
        );
      }
      final b = add('Mobile', ';mob');
      expect(
        () => store.update(
          b,
          name: 'Mobile',
          content: 'x',
          type: SnippetType.other,
          nowMs: 3,
          shortcut: ';e',
        ),
        throwsA(isA<ShortcutTaken>()),
      );
      expect(store.list().map((s) => s.shortcut), [';email', ';mob']);
      expect(store.count, 2);
    });

    test('a bad shortcut is an ArgumentError', () {
      expect(() => add('x', 'e'), throwsArgumentError);
      expect(() => add('x', '; e'), throwsArgumentError);
      expect(store.count, 0);
    });

    test('delete then Undo puts the shortcut back', () {
      final id = add('Work email', ';email');
      final record = store.delete(id)!;
      expect(record.shortcut, ';email');
      store.restore(record);
      expect(store.list().single.shortcut, ';email');
    });

    test('Undo after the shortcut was taken meanwhile keeps the snippet '
        'without its shortcut', () {
      final id = add('Work email', ';email');
      final record = store.delete(id)!;
      add('New', ';em');
      store.restore(record);
      final restored = store.list().firstWhere((s) => s.name == 'Work email');
      expect(restored.shortcut, isNull);
      expect(store.count, 2);
    });

    test('the shortcut table lists every snippet that has one', () {
      final a = add('Work email', ';email');
      add('None', null);
      final c = add('Mobile', ';mob');
      expect(store.shortcuts(), [
        (id: a, name: 'Work email', shortcut: ';email'),
        (id: c, name: 'Mobile', shortcut: ';mob'),
      ]);
    });
  });
}

void _ignoredContract(String name, IgnoredAppStore Function() create) {
  group('$name ignored-app store', () {
    late IgnoredAppStore store;
    setUp(() => store = create());

    List<String> ids() => store.list().map((a) => a.appId).toList();

    test('starts with the preset list', () {
      expect(ids(), presetIgnoredApps.map((a) => a.appId));
      expect(store.list().every((a) => a.preset), isTrue);
    });

    test('add puts an app at the end; the same app twice is refused', () {
      expect(
        store.add(const IgnoredApp('com.example.bank', 'My Bank')),
        isTrue,
      );
      expect(ids().last, 'com.example.bank');
      expect(store.list().last.preset, isFalse);
      expect(store.add(const IgnoredApp('com.example.bank', 'Again')), isFalse);
      expect(
        store.list().where((a) => a.appId == 'com.example.bank').length,
        1,
      );
    });

    test('remove returns the app for Undo; add puts it back', () {
      final removed = store.remove('com.1password.1password')!;
      expect(removed.displayName, '1Password');
      expect(removed.preset, isTrue);
      expect(ids(), isNot(contains('com.1password.1password')));
      expect(store.remove('com.1password.1password'), isNull);
      store.add(removed);
      expect(ids(), contains('com.1password.1password'));
      expect(
        store.list().firstWhere((a) => a.appId == removed.appId).preset,
        isTrue,
      );
    });

    test('restorePresets adds back only the presets that are missing', () {
      store.remove('com.1password.1password');
      store.remove('bitwarden.exe');
      store.add(const IgnoredApp('com.example.bank', 'My Bank'));
      store.restorePresets();
      expect(ids().toSet(), {
        ...presetIgnoredApps.map((a) => a.appId),
        'com.example.bank',
      });
      expect(ids().length, presetIgnoredApps.length + 1);
    });

    test('a bad row is an ArgumentError', () {
      expect(() => store.add(const IgnoredApp('', 'x')), throwsArgumentError);
      expect(() => store.add(IgnoredApp('a', 'n' * 101)), throwsArgumentError);
      expect(() => store.add(const IgnoredApp('a', '')), throwsArgumentError);
    });
  });
}
