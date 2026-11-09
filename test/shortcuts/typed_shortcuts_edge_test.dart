// Tester edge cases for M1.5 typed shortcuts, Dart side: the CHECK at the
// database level, the v3 -> v4 migration under failure and re-open, the D1
// clash rule at its edges (case, code points, 32 characters, stale lists),
// the service under races and failures, and the channel contract with
// malformed native messages.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/channel_typed_shortcuts_port.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_shortcut.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';
import 'fake_typed_shortcuts_port.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('database level', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('kusunga_v4_edge_');
      path = '${dir.path}/kusunga.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Database raw() => sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");

    void insert(Database db, String? shortcut) => db.execute(
      'INSERT INTO snippets (name, content, type, position, created_at, '
      'updated_at, shortcut) VALUES (?, ?, ?, 0, 1, 1, ?)',
      ['n', 'c', 'other', shortcut],
    );

    test('the CHECK counts code points: 32 emoji pass, 33 do not', () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final db = raw();
      insert(db, '😀' * 32); // 128 bytes, 64 UTF-16 units, 32 code points
      expect(() => insert(db, '😀' * 33), throwsA(isA<SqliteException>()));
      expect(() => insert(db, ''), throwsA(isA<SqliteException>()));
      expect(() => insert(db, 'a'), throwsA(isA<SqliteException>()));
      insert(db, 'a' * 32);
      expect(() => insert(db, 'b' * 33), throwsA(isA<SqliteException>()));
      db.close();
    });

    test('the index is case-sensitive: ;Email and ;email may coexist', () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final db = raw();
      insert(db, ';Email');
      insert(db, ';email');
      expect(() => insert(db, ';Email'), throwsA(isA<SqliteException>()));
      db.close();
    });

    test('the CHECK is the floor, the app layer is stricter: a no-break space '
        'or a vertical tab passes SQL but not the store', () {
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final snippets = store.snippetStore();
      for (final bad in ['a b', 'a\u000Bb', 'a b', 'a\u0085b']) {
        expect(
          () => snippets.insert(
            name: 'n',
            content: 'c',
            type: SnippetType.other,
            nowMs: 1,
            shortcut: bad,
          ),
          throwsArgumentError,
          reason: bad.codeUnits.toString(),
        );
      }
      store.close();
      final db = raw();
      insert(db, 'a b'); // a hand-edited file: SQL accepts it
      db.close();
    });

    test('a failed migration rolls back, keeps the data and the .bak', () {
      final v3 = SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: kMigrations.sublist(0, 3),
      );
      v3.writeSetting('paste_mode', 'copy');
      v3.close();
      var db = raw();
      db.execute(
        'INSERT INTO snippets (name, content, type, position, created_at, '
        "updated_at) VALUES ('Work email', 'will@example.com', 'email', 0, 1, 1)",
      );
      // Something already holds the name version 4 wants.
      db.execute('CREATE TABLE ignored_apps (x INTEGER)');
      db.close();

      expect(
        () => SqliteHistoryStore.open(path: path, keyHex: _key),
        throwsA(isA<MigrationFailed>()),
      );
      db = raw();
      expect(db.select('PRAGMA user_version').single.values.single, 3);
      expect(
        db.select('PRAGMA table_info(snippets)').map((r) => r['name']),
        isNot(contains('shortcut')),
        reason: 'ALTER TABLE was rolled back with the rest',
      );
      expect(
        db.select('SELECT name FROM snippets').single['name'],
        'Work email',
      );
      expect(
        db.select(
          "SELECT value FROM settings WHERE key = 'typed_shortcuts_on'",
        ),
        isEmpty,
      );
      db.close();
      expect(File('$path.bak').existsSync(), isTrue);
    });

    test('opening a v4 file again keeps what the user changed: no reseed, '
        'the switch and the shortcuts stay', () {
      var store = SqliteHistoryStore.open(path: path, keyHex: _key);
      store.ignoredAppStore().remove('com.bitwarden.desktop');
      store.ignoredAppStore().add(const IgnoredApp('com.example.bank', 'Bank'));
      store.writeSetting('typed_shortcuts_on', '1');
      store.snippetStore().insert(
        name: 'Work email',
        content: 'will@example.com',
        type: SnippetType.email,
        nowMs: 1,
        shortcut: ';email',
      );
      store.close();
      store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final ids = store.ignoredAppStore().list().map((a) => a.appId).toList();
      expect(ids, isNot(contains('com.bitwarden.desktop')));
      expect(ids.last, 'com.example.bank');
      expect(store.readSetting('typed_shortcuts_on'), '1');
      expect(store.snippetStore().shortcuts().single.shortcut, ';email');
      expect(File('$path.bak').existsSync(), isFalse);
      store.close();
    });

    test('a stale list cannot slip a clash past the store (two services, one '
        'file)', () {
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      SnippetService make() => SnippetService(
        store: store.snippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      );
      final a = make();
      final b = make(); // loaded before a saves
      expect(
        a
            .save(
              name: 'A',
              content: 'x',
              type: SnippetType.other,
              shortcut: ';em',
            )
            .outcome,
        SnippetSave.saved,
      );
      expect(b.shortcutIssue(';email'), isNull, reason: 'b is out of date');
      final r = b.save(
        name: 'B',
        content: 'y',
        type: SnippetType.other,
        shortcut: ';email',
      );
      expect(r.outcome, SnippetSave.shortcutTaken);
      expect(r.clash?.kind, ShortcutClashKind.otherIsStart);
      expect(store.snippetStore().shortcuts().map((s) => s.shortcut), [';em']);
      store.close();
    });
  });

  group('the clash rule (D1 A) at its edges', () {
    ShortcutClash? clash(String shortcut, List<String> others, {int? self}) =>
        findShortcutClash(shortcut, [
          for (var i = 0; i < others.length; i++)
            (id: i + 1, name: 'S$i', shortcut: others[i]),
        ], selfId: self);

    test('case-sensitive in both directions', () {
      expect(clash(';Em', [';email']), isNull);
      expect(clash(';email', [';Em']), isNull);
      expect(clash(';EMAIL', [';email']), isNull);
    });

    test('a 32-character shortcut and its 31-character start clash', () {
      final long = ';${'a' * 31}';
      final start = long.substring(0, 31);
      expect(clash(long, [start])?.kind, ShortcutClashKind.otherIsStart);
      expect(clash(start, [long])?.kind, ShortcutClashKind.newIsStart);
      expect(clash(long, [long])?.kind, ShortcutClashKind.same);
    });

    test('compared by code points: one emoji is the start of two, not half of '
        'another', () {
      expect(
        clash('😀😀', ['😀😁']),
        isNull,
        reason: 'same first unit, different emoji',
      );
      expect(clash('😀😀', ['😀'])?.kind, ShortcutClashKind.otherIsStart);
      expect(clash('😀', ['😀😀'])?.kind, ShortcutClashKind.newIsStart);
    });

    test(
      'a shortcut and the same text plus a combining mark are different',
      () {
        // Prefix by code points, so the e + acute form starts with "e".
        expect(clash('éx', ['é'])?.kind, ShortcutClashKind.otherIsStart);
        expect(clash('éx', ['é']), isNull);
      },
    );

    test('a suffix is never a clash (the matcher takes the longest)', () {
      expect(clash('email', [';email']), isNull);
      expect(clash(';email', ['email']), isNull);
    });

    test('the first clash found is reported; self is skipped', () {
      expect(clash(';em', [';email', ';emma'])?.otherId, 1);
      expect(clash(';em', [';email'], self: 1), isNull);
    });

    test('restoring a deleted snippet whose shortcut a prefix now blocks '
        'brings it back without the shortcut', () {
      final store = MemorySnippetStore();
      final svc = SnippetService(
        store: store,
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      );
      final id = svc
          .save(
            name: 'Work email',
            content: 'x',
            type: SnippetType.other,
            shortcut: ';email',
          )
          .id!;
      final record = store.delete(id)!;
      svc.save(
        name: 'Short',
        content: 'y',
        type: SnippetType.other,
        shortcut: ';em',
      );
      store.restore(record);
      expect(
        store.list().firstWhere((s) => s.name == 'Work email').shortcut,
        isNull,
      );
      expect(store.shortcuts().map((s) => s.shortcut), [';em']);
    });

    test('whitespace-only and padded shortcuts are errors, never trimmed', () {
      final svc = SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      );
      for (final bad in [' ', '  ', ' ;email', ';email ', '\t', ';e mail']) {
        final r = svc.save(
          name: 'n',
          content: 'c',
          type: SnippetType.other,
          shortcut: bad,
        );
        expect(
          r.outcome,
          SnippetSave.invalid,
          reason: bad.codeUnits.toString(),
        );
        expect(r.problems, contains(SnippetProblem.shortcutSpaces));
      }
      expect(svc.items, isEmpty);
    });

    test('the table sent to native has ids and shortcuts only', () {
      final svc = SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      );
      svc.save(
        name: 'Bank',
        content: 'GB00 SECRET 1234',
        type: SnippetType.other,
        shortcut: ';bank',
      );
      final table = svc.shortcutTable;
      expect(table.single.id, isA<int>());
      expect(table.single.shortcut, ';bank');
      // A record of exactly (id, shortcut): no name, no content.
      expect(table.single.toString(), isNot(contains('Bank')));
      expect(table.single.toString(), isNot(contains('SECRET')));
    });
  });

  group('ShortcutService under races and failures', () {
    late FakeTypedShortcutsPort port;
    late SnippetService snippets;
    late MemoryIgnoredAppStore ignored;
    late Map<String, String> settings;
    late FakeLog log;

    setUp(() {
      port = FakeTypedShortcutsPort();
      snippets = SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      );
      ignored = MemoryIgnoredAppStore();
      settings = {'typed_shortcuts_on': '0'};
      log = FakeLog();
    });

    ShortcutService make({bool isWindows = false, TypedShortcutsPort? p}) {
      final s = ShortcutService(
        port: p ?? port,
        snippets: snippets,
        ignoredApps: ignored,
        readSetting: (k) => settings[k],
        writeSetting: (k, v) {
          settings[k] = v;
          return true;
        },
        log: log,
        isWindows: isWindows,
        available: true,
      );
      addTearDown(s.dispose);
      return s;
    }

    int add(String name, String text, String code) => snippets
        .save(
          name: name,
          content: text,
          type: SnippetType.other,
          shortcut: code,
        )
        .id!;

    test('on, off, on while native is slow: the last switch wins', () async {
      final s = make();
      await s.start();
      port.holdEnable = Completer<void>();
      final first = s.setEnabled(true);
      final second = s.setEnabled(false);
      final third = s.setEnabled(true);
      port.holdEnable!.complete();
      await Future.wait([first, second, third]);
      expect(s.enabled, isTrue);
      expect(settings['typed_shortcuts_on'], '1');
      expect(s.status, TypedShortcutStatus.on);
      expect(s.busy, isFalse);
    });

    test('off while a replacement is running: nothing more is sent and the '
        'service stays usable', () async {
      final id = add('Work email', 'will@example.com', ';email');
      settings['typed_shortcuts_on'] = '1';
      final s = make();
      await s.start();
      port.match(id, 6);
      await s.setEnabled(false);
      port.match(id, 6);
      await pumpEventQueue();
      expect(
        port.replaced.length,
        1,
        reason: 'the second match came while off',
      );
      await s.setEnabled(true);
      port.match(id, 6);
      await pumpEventQueue();
      expect(port.replaced.length, 2);
    });

    test('a native replace that throws is "failed" and the next one still '
        'works', () async {
      final id = add('Work email', 'will@example.com', ';email');
      settings['typed_shortcuts_on'] = '1';
      final throwing = _ThrowingPort(port);
      final s = make(p: throwing);
      await s.start();
      throwing.failReplace = true;
      throwing.match(id, 6);
      await pumpEventQueue();
      expect(log.codes, contains(LogCode.writeFailed));
      throwing.failReplace = false;
      throwing.match(id, 6);
      await pumpEventQueue();
      expect(log.codes, contains(LogCode.shortcutFired));
    });

    test('setEnabled that throws: failed when turning on, off when turning '
        'off; the switch keeps its saved value', () async {
      final throwing = _ThrowingPort(port)..failEnable = true;
      final s = make(p: throwing);
      await s.start();
      await s.setEnabled(true);
      expect(s.status, TypedShortcutStatus.failed);
      expect(settings['typed_shortcuts_on'], '1');
      expect(s.enabled, isTrue, reason: 'the user can retry by off and on');
      await s.setEnabled(false);
      expect(s.status, TypedShortcutStatus.off);
      expect(s.busy, isFalse);
    });

    test('a match for a snippet deleted a moment ago does nothing', () async {
      final id = add('Work email', 'will@example.com', ';email');
      settings['typed_shortcuts_on'] = '1';
      final s = make();
      await s.start();
      snippets.delete(id);
      port.match(id, 6);
      await pumpEventQueue();
      expect(port.replaced, isEmpty);
    });

    test(
      'a match for a snippet whose text changed sends the new text',
      () async {
        final id = add('Work email', 'old@example.com', ';email');
        settings['typed_shortcuts_on'] = '1';
        final s = make();
        await s.start();
        snippets.save(
          id: id,
          name: 'Work email',
          content: 'new@example.com',
          type: SnippetType.email,
          shortcut: ';email',
        );
        port.match(id, 6);
        await pumpEventQueue();
        expect(port.replaced.single, (6, 'new@example.com'));
      },
    );

    test('events after dispose are ignored and nothing throws', () async {
      final id = add('Work email', 'will@example.com', ';email');
      settings['typed_shortcuts_on'] = '1';
      final s = make();
      await s.start();
      s.dispose();
      port.match(id, 6);
      port.statusChanged(TypedShortcutStatus.stopped);
      await pumpEventQueue();
      expect(port.replaced, isEmpty);
      expect(await s.setEnabled(true), isNull);
    });

    test('snippet changes after dispose do not reach native', () async {
      final s = make();
      await s.start();
      final sent = port.tables.length;
      s.dispose();
      add('Work email', 'x', ';email');
      expect(port.tables.length, sent);
    });

    test(
      'a long or emoji app name is cut to 100 characters, not rejected',
      () async {
        final s = make();
        await s.start();
        expect(
          s.addApp(RunningApp(appId: 'com.example.a', name: 'x' * 150)),
          isTrue,
        );
        expect(
          s.addApp(RunningApp(appId: 'com.example.b', name: '😀' * 101)),
          isTrue,
        );
        expect(
          s.addApp(RunningApp(appId: 'com.example.c', name: '😀' * 100)),
          isTrue,
        );
        final byId = {for (final a in s.ignoredApps) a.appId: a.displayName};
        expect(byId['com.example.a']!.runes.length, 100);
        expect(byId['com.example.b']!.runes.length, 100);
        expect(byId['com.example.c']!.runes.length, 100);
      },
    );

    test(
      'adding an app that is already listed leaves the list as it is',
      () async {
        final s = make();
        await s.start();
        final before = s.ignoredApps.length;
        s.addApp(
          const RunningApp(appId: 'com.1password.1password', name: '1Password'),
        );
        expect(s.ignoredApps.length, before);
      },
    );

    test(
      'Undo after Remove and re-add of the same app does not duplicate it',
      () async {
        final s = make();
        await s.start();
        final removed = s.removeApp('com.bitwarden.desktop')!;
        s.addApp(
          const RunningApp(appId: 'com.bitwarden.desktop', name: 'Bitwarden'),
        );
        s.undoRemove(removed);
        expect(
          s.ignoredApps.where((a) => a.appId == 'com.bitwarden.desktop').length,
          1,
        );
      },
    );

    test('Windows keeps only .exe ids in what native gets, even if the file '
        'holds Mac ids', () async {
      final s = make(isWindows: true);
      await s.start();
      expect(port.ignoredSent.first, everyElement(endsWith('.exe')));
      expect(port.ignoredSent.first, isNotEmpty);
    });

    test('no log line holds a shortcut, a name or snippet text across the '
        'whole flow', () async {
      final id = add('Bank', 'GB00 SECRET 1234', ';bank');
      settings['typed_shortcuts_on'] = '1';
      final s = make();
      await s.start();
      port.apps = const [
        RunningApp(appId: 'com.example.bank', name: 'My Bank'),
      ];
      s.addApp(port.apps.single);
      port.match(id, 5);
      port.replaceAnswer = ReplaceOutcome.copied;
      port.match(id, 5);
      await pumpEventQueue();
      s.removeApp('com.example.bank');
      for (final d in log.details) {
        expect(
          d is int || d == null,
          isTrue,
          reason: 'details are numbers: $d',
        );
      }
      expect(log.codes.map((c) => c.name).join(' '), isNot(contains('bank')));
    });
  });

  group('channel contract with malformed native messages', () {
    const channel = MethodChannel('com.wnasoni.kusunga/shortcuts');
    const codec = StandardMethodCodec();
    final messenger = binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    Object? Function(MethodCall call) answer = (_) => null;

    setUp(() {
      calls.clear();
      answer = (_) => null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final result = answer(call);
        if (result is Exception) throw result;
        return result;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> fromNative(String method, Object? args) =>
        messenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

    test('matched: wrong types, negative, float, extra keys, a list', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      final events = <TypedShortcutEvent>[];
      p.events.listen(events.add);
      for (final bad in <Object?>[
        {'snippetId': 7.0, 'deleteCount': 6},
        {'snippetId': 7, 'deleteCount': 6.0},
        {'snippetId': 7, 'deleteCount': -1},
        {'snippetId': null, 'deleteCount': 6},
        {'snippetId': 7},
        {'deleteCount': 6},
        [7, 6],
        'matched',
        42,
      ]) {
        await fromNative('matched', bad);
      }
      expect(events, isEmpty);
      // Extra keys (a typed text, say) are never read or passed on.
      await fromNative('matched', {
        'snippetId': 7,
        'deleteCount': 32,
        'matchId': 9,
        'text': 'hunter2',
        'typed': ';email',
      });
      final m = events.single as ShortcutMatched;
      expect((m.snippetId, m.deleteCount), (7, 32));
      expect(m.toString(), isNot(contains('hunter2')));
    });

    test('an unknown native method and a null status are ignored', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      final events = <TypedShortcutEvent>[];
      p.events.listen(events.add);
      await fromNative('typedKey', {'text': 'a'});
      await fromNative('statusChanged', {'status': null});
      await fromNative('statusChanged', null);
      await fromNative('statusChanged', {'status': 'ON'});
      expect(events, isEmpty);
    });

    test('every status name round-trips and nothing else does', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      final events = <TypedShortcutEvent>[];
      p.events.listen(events.add);
      for (final s in TypedShortcutStatus.values) {
        await fromNative('statusChanged', {'status': s.name});
      }
      expect([
        for (final e in events) (e as ShortcutStatusChanged).status,
      ], TypedShortcutStatus.values);
    });

    test(
      'replace: unknown or missing answers and exceptions are "failed"',
      () async {
        final p = ChannelTypedShortcutsPort(channel: channel);
        for (final a in <Object?>[null, 'Replaced', 7, true, 'ok']) {
          answer = (_) => a;
          expect(
            await p.replace(1, 3, 'x'),
            ReplaceOutcome.failed,
            reason: '$a',
          );
        }
        answer = (_) => PlatformException(code: 'x');
        expect(await p.replace(1, 3, 'x'), ReplaceOutcome.failed);
        answer = (_) => MissingPluginException();
        expect(await p.replace(1, 3, 'x'), ReplaceOutcome.failed);
        for (final name in ['replaced', 'cancelled', 'copied', 'failed']) {
          answer = (_) => name;
          expect((await p.replace(1, 3, 'x')).name, name);
        }
      },
    );

    test('status and setEnabled with a bad answer: off, or failed when asked '
        'to turn on', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      answer = (_) => 'nonsense';
      expect(await p.status(), TypedShortcutStatus.off);
      expect(await p.setEnabled(true), TypedShortcutStatus.failed);
      expect(await p.setEnabled(false), TypedShortcutStatus.off);
      answer = (_) => PlatformException(code: 'x');
      expect(await p.setEnabled(true), TypedShortcutStatus.failed);
    });

    test('runningApps: a non-list, wrong row types and a bad icon', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      answer = (_) => 'apps';
      expect(await p.runningApps(), isEmpty);
      answer = (_) => [
        7,
        null,
        {'appId': 1, 'name': 'x'},
        {'appId': 'a.b', 'name': 2},
        {'appId': '', 'name': 'x'},
        {'appId': 'a.b', 'name': ''},
        {'appId': 'a.good', 'name': 'Good', 'icon': 'not bytes'},
      ];
      final apps = await p.runningApps();
      expect(apps.map((a) => a.appId), ['a.good']);
      expect(apps.single.icon, isNull);
    });

    test('requestListenAccess is true only for true', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      for (final a in <Object?>[null, 1, 'true', false]) {
        answer = (_) => a;
        expect(await p.requestListenAccess(), isFalse, reason: '$a');
      }
      answer = (_) => true;
      expect(await p.requestListenAccess(), isTrue);
    });

    test('setTable sends every shortcut exactly as typed: no trimming, no '
        'lower-casing, emoji intact', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      await p.setTable([(id: 1, shortcut: ';Email'), (id: 2, shortcut: '😀é')]);
      final args = calls.single.arguments as Map;
      expect(args.keys, {'entries'});
      expect(args['entries'], [
        {'id': 1, 'shortcut': ';Email'},
        {'id': 2, 'shortcut': '😀é'},
      ]);
    });
  });
}

/// Wraps the fake and throws on demand.
class _ThrowingPort implements TypedShortcutsPort {
  _ThrowingPort(this.inner);
  final FakeTypedShortcutsPort inner;
  bool failReplace = false;
  bool failEnable = false;

  void match(int id, int n) => inner.match(id, n);

  @override
  Stream<TypedShortcutEvent> get events => inner.events;
  @override
  Future<void> setTable(List<({int id, String shortcut})> e) =>
      inner.setTable(e);
  @override
  Future<void> setIgnored(List<String> ids) => inner.setIgnored(ids);
  @override
  Future<TypedShortcutStatus> setEnabled(bool on) async {
    if (failEnable) throw StateError('native');
    return inner.setEnabled(on);
  }

  @override
  Future<TypedShortcutStatus> status() => inner.status();
  @override
  Future<ReplaceOutcome> replace(int matchId, int n, String text) async {
    if (failReplace) throw StateError('native');
    return inner.replace(matchId, n, text);
  }

  @override
  Future<List<RunningApp>> runningApps() => inner.runningApps();
  @override
  Future<bool> requestListenAccess() => inner.requestListenAccess();
  @override
  Future<void> openInputMonitoringSettings() =>
      inner.openInputMonitoringSettings();
}
