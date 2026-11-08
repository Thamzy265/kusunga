// Tester probes for the schema v2 -> v3 step (design note, "Data",
// "Migration", "Failure plan" and the abuse case "I lose snippets in a failed
// update"), tried on real encrypted files:
//  - a big, real-looking v2 history comes through with every column equal;
//  - a migration that fails, or is cut off, leaves the v2 file readable;
//  - a file from a newer build is left byte for byte as it was.
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late String path;
  late FakeLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_snip_mig_');
    path = '${dir.path}/kusunga.db';
    log = FakeLog();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<OpenedHistory> open({List<Migration> migrations = kMigrations}) =>
      openHistory(
        keys: FakeKeyStore(stored: _key),
        directory: dir.path,
        log: log,
        random: Random(1),
        today: () => DateTime(2026, 11, 4),
        migrations: migrations,
      );

  Database raw() => sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");

  int version() {
    final db = raw();
    final v = db.select('PRAGMA user_version').single.values.single as int;
    db.close();
    return v;
  }

  List<String> files() =>
      dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  String sha(String file) =>
      sha256.convert(File(file).readAsBytesSync()).toString();

  List<List<Object?>> allRows(String table) {
    final db = raw();
    final rows = [
      for (final r in db.select('SELECT * FROM $table ORDER BY 1'))
        r.values.toList(),
    ];
    db.close();
    return rows;
  }

  final v2Only = kMigrations.sublist(0, 2);

  /// A history that looks like a long-time user's: thousands of items of all
  /// shapes (short words, emails, links, multi-line code, CJK, emoji, RTL
  /// text, NUL, a 1 MiB item), repeated copies, and the user's settings.
  /// Shapes follow what M1.2 stores (`ClipKind` text or link, one row per
  /// distinct text, bumped when copied again).
  Map<int, String> buildRealisticV2({int items = 5000}) {
    final store = SqliteHistoryStore.open(
      path: path,
      keyHex: _key,
      migrations: v2Only,
    );
    store.setLimit(5000);
    store.writeSetting('picker_shortcut', 'ctrl+alt+k');
    store.writeSetting('paste_mode', 'copy_only');
    final random = Random(1104);
    const words = ['alpha', 'invoice', 'meeting', 'password-reset', 'tracking'];
    String text(int i) {
      switch (i % 9) {
        case 0:
          return '${words[i % 5]} $i';
        case 1:
          return 'person$i@example.co.uk';
        case 2:
          return 'https://example.com/path/$i?utm_source=a&id=${random.nextInt(1 << 30)}';
        case 3:
          return 'void f$i() {\n  print("héllo");\n\treturn;\n}\n' *
              (1 + i % 7);
        case 4:
          return '日本語のテキスト $i';
        case 5:
          return 'emoji \u{1F600}\u{1F469}\u{200D}\u{1F4BB} $i';
        case 6:
          return '\u{202E}evil rtl $i\u{202C}';
        case 7:
          return 'with a NUL \u0000 in it $i';
        default:
          return 'x' * (200 + random.nextInt(5000)) + '$i';
      }
    }

    final texts = <int, String>{};
    for (var i = 0; i < items; i++) {
      final t = text(i);
      final id = store.insertOrBump(
        t,
        t.startsWith('http') ? ClipKind.link : ClipKind.text,
        1000 + i,
      );
      texts[id] = t;
      // The user copies something old again: it moves to the top.
      if (i % 11 == 0 && i > 20) {
        final again = texts.values.elementAt(random.nextInt(texts.length));
        store.insertOrBump(again, ClipKind.text, 1000 + i);
      }
    }
    final big = 'B' * ClipItem.maxContentLength;
    texts[store.insertOrBump(big, ClipKind.text, 99999)] = big;
    store.close();
    return texts;
  }

  group('v2 to v3 with a large, real-looking history', () {
    test('every row of every table comes through equal; only the snippets '
        'table is new; the backup is gone; the file is intact', () {
      buildRealisticV2();
      expect(version(), 2);
      final itemsBefore = allRows('clip_items');
      final settingsBefore = allRows('settings');
      final db = raw();
      final schemaBefore = <String, String?>{
        for (final r in db.select(
          "SELECT name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
        ))
          r['name'] as String: r['sql'] as String?,
      };
      db.close();
      expect(itemsBefore.length, greaterThan(4900));

      final sw = Stopwatch()..start();
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      sw.stop();
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 20)),
        reason: 'a one-off start-up step, even for a big file',
      );
      expect(version(), 3);
      expect(allRows('clip_items'), itemsBefore);
      expect(allRows('settings'), settingsBefore);
      expect(store.limit, 5000);
      expect(store.readSetting('picker_shortcut'), 'ctrl+alt+k');
      // The history API still reads the whole text of every item.
      for (final item in store.list().take(50)) {
        expect(store.contentOf(item.id), isNotNull);
      }
      expect(store.contentOf(store.list().first.id)!.length, 1048576);
      expect(store.snippetStore().count, 0);
      store.close();

      final after = raw();
      final schemaAfter = <String, String?>{
        for (final r in after.select(
          "SELECT name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
        ))
          r['name'] as String: r['sql'] as String?,
      };
      expect(after.select('PRAGMA quick_check').single.values.single, 'ok');
      after.close();
      // Expand only: all the v2 objects are unchanged, and only the snippets
      // table and its index were added.
      expect(
        schemaAfter.keys.where((k) => !schemaBefore.containsKey(k)).toSet(),
        {'idx_snippets_position', 'snippets'},
      );
      schemaBefore.forEach((name, sql) => expect(schemaAfter[name], sql));
      expect(files(), ['kusunga.db']);
    });

    test('after the step, snippets work and history Clear and limit changes '
        'leave them alone', () {
      buildRealisticV2(items: 600);
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final snippets = store.snippetStore();
      for (var i = 0; i < 25; i++) {
        snippets.insert(
          name: 'Snippet $i',
          content: 'saved $i',
          type: SnippetType.other,
          nowMs: i,
        );
      }
      store.setLimit(10);
      expect(store.count, 10);
      store.clear();
      expect(store.count, 0);
      expect(snippets.count, 25);
      store.close();
      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(again.snippetStore().count, 25);
      expect(again.snippetStore().list().map((s) => s.name), [
        for (var i = 0; i < 25; i++) 'Snippet $i',
      ]);
      again.close();
    });
  });

  group('an interrupted or failed migration', () {
    test('a v3 step that fails: the v2 file is untouched and readable, the '
        'backup is kept, snippets run in memory, and the next start with a '
        'good build migrates fine', () async {
      buildRealisticV2(items: 300);
      final rows = allRows('clip_items');
      final bad = Migration(
        version: 3,
        statements: [
          ...kMigrations[2].statements,
          'INSERT INTO snippets (id) VALUES (1)', // NOT NULL: fails
        ],
      );
      final opened = await open(migrations: [...v2Only, bad]);
      expect(opened.notices, {HistoryNotice.incompatible});
      expect(opened.snippets, isA<MemorySnippetStore>());
      expect(log.codes, contains(LogCode.storeIncompatible));
      opened.store.close();
      expect(files(), ['kusunga.db', 'kusunga.db.bak']);
      expect(version(), 2, reason: 'rolled back, not half-migrated');
      expect(allRows('clip_items'), rows);
      final db = raw();
      expect(
        db.select("SELECT name FROM sqlite_master WHERE name = 'snippets'"),
        isEmpty,
        reason: 'the table of the failed step is gone too',
      );
      db.close();

      final good = await open();
      expect(good.notices, isEmpty);
      expect(version(), 3);
      expect(allRows('clip_items'), rows);
      expect(files(), ['kusunga.db'], reason: 'the backup goes on success');
      good.store.close();
    });

    test('cut off right after the backup is made (process killed): the v2 '
        'file is intact and the next start finishes the job', () async {
      buildRealisticV2(items: 300);
      final rows = allRows('clip_items');
      final killed = Migration(
        version: 3,
        statements: kMigrations[2].statements,
        onRun: () => throw const FileSystemException('killed here'),
      );
      expect(
        () => SqliteHistoryStore.open(
          path: path,
          keyHex: _key,
          migrations: [...v2Only, killed],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(version(), 2);
      expect(files(), ['kusunga.db', 'kusunga.db.bak']);
      expect(sha('$path.bak'), sha(path));
      expect(allRows('clip_items'), rows);

      final good = await open();
      expect(good.notices, isEmpty);
      expect(version(), 3);
      expect(allRows('clip_items'), rows);
      expect(files(), ['kusunga.db']);
      good.store.close();
    });

    test('a half-written backup left by an earlier crash is replaced, not '
        'trusted', () async {
      buildRealisticV2(items: 100);
      File('$path.bak').writeAsBytesSync(List.filled(5000, 7));
      final opened = await open();
      expect(opened.notices, isEmpty);
      expect(version(), 3);
      expect(files(), ['kusunga.db']);
      opened.store.close();
    });

    test('the backup cannot be written: the v2 file is not called '
        '"unreadable", moved aside and replaced by an empty history', () async {
      // Repro (TB-1). The step needs a copy first. If that copy fails (disk
      // full, folder rights, a folder in the way), nothing is wrong with the
      // history file itself. It must stay in place and be used (or run in
      // memory with the "incompatible" notice, as a failed step does), never
      // moved aside while the user is given a new empty history.
      final rows = (() {
        buildRealisticV2(items: 100);
        return allRows('clip_items');
      })();
      Directory('$path.bak').createSync(); // makes the backup write fail
      final opened = await open();
      opened.store.close();
      expect(
        files().where((f) => f.contains('unreadable')),
        isEmpty,
        reason: 'a good file was moved aside: ${files()}',
      );
      expect(File(path).existsSync(), isTrue);
      expect(version(), 2);
      expect(allRows('clip_items'), rows);
    });
  });

  group('a file from a newer build is never touched', () {
    Future<void> makeNewerFile({int version = 9}) async {
      final opened = await open();
      opened.snippets.insert(
        name: 'Mine',
        content: 'My secret snippet',
        type: SnippetType.other,
        nowMs: 1,
      );
      opened.store.insertOrBump('some history', ClipKind.text, 2);
      opened.store.close();
      final db = raw()..execute('PRAGMA user_version = $version');
      db.close();
    }

    test('opening it changes no byte, adds no file (backup, journal, WAL), '
        'and snippets are off with the banner', () async {
      await makeNewerFile();
      final before = sha(path);
      final listing = files();
      expect(listing, ['kusunga.db']);

      final opened = await open();
      expect(opened.notices, {HistoryNotice.incompatible});
      expect(opened.snippets, isA<MemorySnippetStore>());
      expect(opened.snippets.count, 0);
      expect(log.codes, contains(LogCode.storeIncompatible));

      final service = HistoryService(
        store: opened.store,
        notices: opened.notices,
        source: FakeClipboardSource(),
        log: log,
        snippetStore: opened.snippets,
      )..start();
      expect(service.snippets.canEdit, isFalse);
      expect(service.snippets.banners, {SnippetBanner.unavailable});
      expect(log.codes, contains(LogCode.snippetsUnavailable));
      // Every change is refused, so nothing can be typed and lost.
      expect(
        service.snippets
            .save(name: 'x', content: 'y', type: SnippetType.other)
            .outcome,
        SnippetSave.unavailable,
      );
      // Use it for a while, quit.
      service.clear();
      service.dispose();
      expect(files(), listing);
      expect(sha(path), before);
    });

    test('a file one version ahead of this build is left alone as well, and '
        'the old data is still all there for the newer build', () async {
      await makeNewerFile(version: 4);
      final before = sha(path);
      final opened = await open();
      expect(opened.notices, {HistoryNotice.incompatible});
      opened.store.close();
      expect(sha(path), before);
      // The newer build (here: this one, once the version is put back).
      final db = raw()..execute('PRAGMA user_version = 3');
      db.close();
      final back = await open();
      expect(back.notices, isEmpty);
      expect(back.snippets.list().single.name, 'Mine');
      expect(
        back.snippets.contentOf(back.snippets.list().single.id),
        'My secret snippet',
      );
      expect(back.store.list().single.preview, 'some history');
      back.store.close();
    });
  });

  group('a file that cannot be read with the key', () {
    test('is moved aside whole, with its snippets, never deleted by the '
        'start-up', () async {
      final first = await open();
      first.snippets.insert(
        name: 'Mine',
        content: 'kept for later',
        type: SnippetType.phone,
        nowMs: 1,
      );
      first.store.close();
      final bytes = File(path).readAsBytesSync();

      final other = await openHistory(
        keys: FakeKeyStore(stored: 'e' * 64),
        directory: dir.path,
        log: log,
        random: Random(1),
        today: () => DateTime(2026, 11, 4),
      );
      expect(other.notices, {HistoryNotice.readError});
      expect(other.snippets.count, 0);
      other.store.close();
      final aside = files().where((f) => f.contains('unreadable')).single;
      expect(File('${dir.path}/$aside').readAsBytesSync(), bytes);
      // With the right key the moved-aside file still has the snippet.
      final db = sqlite3.open('${dir.path}/$aside')
        ..execute("PRAGMA hexkey = '$_key'");
      expect(db.select('SELECT name FROM snippets').single['name'], 'Mine');
      db.close();
    });
  });
}
