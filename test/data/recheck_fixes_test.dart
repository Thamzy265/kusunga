// M1.8 tester, re-check of the fixes T1-T9 (lead rulings of 2026-11-12):
// the export temp file (T7), import text and time rules (T1, T2, T3, T9 and
// the 24 h rule), the import preview (T4) and links as data folders (T8).
// Real SQLite files and temp folders only.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/data_eraser.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/data/your_data_service.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _day = Duration.millisecondsPerDay;
// The service's clock for checkImportTimes.
final _serviceNow = DateTime.utc(2026, 11, 12, 9, 30);
final _nowMs = _serviceNow.millisecondsSinceEpoch;

Map<String, Object?> _file({
  Object? snippets = const <Object?>[],
  Object? history,
  Object? settings,
  Object? apps,
  Object? exportedAt = '2026-11-12T09:30:00Z',
}) => {
  'format': 'kusunga-export',
  'version': 1,
  'exported_at': exportedAt,
  'snippets': snippets,
  'history': ?history,
  'settings': ?settings,
  'ignored_apps': ?apps,
};

Map<String, Object?> _clip(
  String content, {
  Object? created = '2026-11-01T10:00:00Z',
  Object? last = '2026-11-02T10:00:00Z',
}) => {
  'content': content,
  'kind': 'text',
  'created_at': created,
  'last_copied_at': last,
};

Map<String, Object?> _snip(String name, {String? content}) => {
  'name': name,
  'content': content ?? 'content of $name',
  'type': 'other',
  'shortcut': null,
  'position': 0,
};

ExportBundle _decode(Object? json) =>
    decodeImport(utf8.encode(jsonEncode(json)));

Matcher get _rejected => throwsA(isA<ImportRejected>());

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_tester_rc_'));
  tearDown(() {
    // Folders a test made unreadable must be openable again to be removed.
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
    }
    dir.deleteSync(recursive: true);
  });

  group('T7: the export temp file', () {
    test('the name has 128 random bits in 32 hex digits, and differs each '
        'time', () {
      final a = exportTempPath('/x/out.json');
      final b = exportTempPath('/x/out.json');
      expect(a, matches(RegExp(r'^/x/out\.json\.kusunga-tmp-[0-9a-f]{32}$')));
      expect(a, isNot(b));
      expect(
        exportTempPath('/x/out.json', Random(1)),
        exportTempPath('/x/out.json', Random(1)),
        reason: 'only the injected random decides it',
      );
    });

    test('a link planted at the exact temp name is not written through: the '
        'export still succeeds, the link target is untouched', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final path = p.join(dir.path, 'out.json');
      Link(exportTempPath(path, Random(7))).createSync(victim.path);
      writeExportFile(path, utf8.encode('{"ok":1}'), random: Random(7));
      expect(victim.readAsStringSync(), 'keep');
      expect(File(path).readAsStringSync(), '{"ok":1}');
      expect(
        FileSystemEntity.isLinkSync(exportTempPath(path, Random(7))),
        isTrue,
        reason: 'a link is never followed and never removed',
      );
    }, skip: Platform.isWindows);

    test('a regular file planted at the exact temp name is not written '
        'into or kept: the export is complete and exact', () {
      final path = p.join(dir.path, 'out.json');
      File(exportTempPath(path, Random(3))).writeAsStringSync('planted junk');
      writeExportFile(path, utf8.encode('{"ok":1}'), random: Random(3));
      expect(File(path).readAsStringSync(), '{"ok":1}');
    });

    test(
      'leftovers of earlier exports to this name go; nothing else does',
      () {
        final path = p.join(dir.path, 'my (1)+x[2].json');
        final outside = File(p.join(dir.path, 'outside.txt'))
          ..writeAsStringSync('precious');
        final hex = 'a' * 32;
        final goes = [
          '$path.kusunga-tmp',
          '$path.kusunga-tmp-$hex',
          '$path.kusunga-tmp-${'0123456789abcdef' * 2}',
        ];
        final stays = <String>[
          '$path.kusunga-tmp-${'a' * 31}', // not Kusunga's length
          '$path.kusunga-tmp-${'F' * 32}', // not lower-case hex
          '$path.kusunga-tmp-$hex.bak',
          '$path.kusunga-tmpx',
          '${p.join(dir.path, 'other.json')}.kusunga-tmp-$hex', // another export
          p.join(dir.path, 'unrelated.txt'),
        ];
        for (final f in [...goes, ...stays]) {
          File(f).writeAsStringSync('x');
        }
        File(path).writeAsStringSync('the user\'s earlier export');
        Directory('$path.kusunga-tmp-${'b' * 32}').createSync();
        Link('$path.kusunga-tmp-${'c' * 32}').createSync(outside.path);
        Link(
          '$path.kusunga-tmp-${'d' * 32}',
        ).createSync(p.join(dir.path, 'nowhere'));

        writeExportFile(path, utf8.encode('new'));

        expect(File(path).readAsStringSync(), 'new');
        for (final f in goes) {
          expect(File(f).existsSync(), isFalse, reason: f);
        }
        for (final f in stays) {
          expect(File(f).existsSync(), isTrue, reason: f);
        }
        expect(Directory('$path.kusunga-tmp-${'b' * 32}').existsSync(), isTrue);
        expect(Link('$path.kusunga-tmp-${'c' * 32}').existsSync(), isTrue);
        expect(Link('$path.kusunga-tmp-${'d' * 32}').existsSync(), isTrue);
        expect(outside.readAsStringSync(), 'precious');
      },
      skip: Platform.isWindows,
    );

    test('a leftover that is a hard link: its name goes, the other name and '
        'its content stay', () {
      final outside = File(p.join(dir.path, 'outside.txt'))
        ..writeAsStringSync('precious');
      final path = p.join(dir.path, 'out.json');
      final leftover = '$path.kusunga-tmp-${'e' * 32}';
      expect(Process.runSync('ln', [outside.path, leftover]).exitCode, 0);
      writeExportFile(path, utf8.encode('new'));
      expect(File(leftover).existsSync(), isFalse);
      expect(outside.readAsStringSync(), 'precious');
    }, skip: Platform.isWindows);

    test('only the picked name is tidied: the temp names of other picked '
        'files stay, and the picked file itself is never a leftover', () {
      final path = p.join(dir.path, 'out.json');
      File(path).writeAsStringSync('mine');
      File('$path.json').writeAsStringSync('other');
      writeExportFile(p.join(dir.path, 'second.json'), utf8.encode('x'));
      expect(File(path).readAsStringSync(), 'mine');
      expect(File('$path.json').readAsStringSync(), 'other');
    });

    test('a 4 MB export is written whole, over a longer old file', () {
      final path = p.join(dir.path, 'out.json');
      File(path).writeAsBytesSync(List.filled(6 * 1024 * 1024, 0x41));
      final bytes = List.generate(4 * 1024 * 1024, (i) => i & 0xFF);
      writeExportFile(path, bytes);
      expect(File(path).readAsBytesSync(), bytes);
      expect(dir.listSync().map((e) => p.basename(e.path)), [
        'out.json',
      ], reason: 'no temp file left');
    });

    test('the target is a folder: the export fails, the folder and its '
        'content stay, no temp file is left', () {
      final target = Directory(p.join(dir.path, 'out.json'))..createSync();
      File(p.join(target.path, 'inside.txt')).writeAsStringSync('i');
      expect(
        () => writeExportFile(target.path, utf8.encode('x')),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(p.join(target.path, 'inside.txt')).existsSync(), isTrue);
      expect(dir.listSync().map((e) => p.basename(e.path)), ['out.json']);
    });

    test('a folder that can be written but not listed (leftover clean-up '
        'cannot run) still exports', () {
      final sub = Directory(p.join(dir.path, 'drop'))..createSync();
      Process.runSync('chmod', ['300', sub.path]); // write, no read
      final path = p.join(sub.path, 'out.json');
      writeExportFile(path, utf8.encode('ok'));
      Process.runSync('chmod', ['700', sub.path]);
      expect(File(path).readAsStringSync(), 'ok');
    }, skip: Platform.isWindows);

    test('the sandbox case: no temp file can be made, the picked file is '
        'written directly; a link at the picked path is refused, not '
        'followed, and not removed', () {
      final sub = Directory(p.join(dir.path, 'ro'))..createSync();
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final plain = File(p.join(sub.path, 'plain.json'))
        ..writeAsStringSync('old');
      Link(p.join(sub.path, 'link.json')).createSync(victim.path);
      Process.runSync('chmod', ['500', sub.path]); // no new files
      writeExportFile(plain.path, utf8.encode('direct'));
      expect(plain.readAsStringSync(), 'direct');
      expect(
        () => writeExportFile(p.join(sub.path, 'link.json'), utf8.encode('x')),
        throwsA(isA<FileSystemException>()),
      );
      expect(victim.readAsStringSync(), 'keep');
      expect(Link(p.join(sub.path, 'link.json')).existsSync(), isTrue);
    }, skip: Platform.isWindows);
  });

  group('T2, T1, T3, T9: what an import now refuses', () {
    test('half a character is refused anywhere text is read, and whole '
        'pairs still pass', () {
      const lone = ['\\ud800', '\\udc00', '\\ude00\\ud83d', 'x\\ud83d'];
      for (final l in lone) {
        for (final build in <String Function(String)>[
          (t) => '"snippets":[{"name":"A$t","content":"c","type":"other"}]',
          (t) => '"snippets":[{"name":"A","content":"c$t","type":"other"}]',
          (t) =>
              '"snippets":[],"history":[{"content":"h$t","kind":"text",'
              '"created_at":"2026-11-01T10:00:00Z",'
              '"last_copied_at":"2026-11-02T10:00:00Z"}]',
          (t) =>
              '"snippets":[],"ignored_apps":[{"app_id":"a$t","display_name":"n"}]',
          (t) =>
              '"snippets":[],"ignored_apps":[{"app_id":"a","display_name":"n$t"}]',
        ]) {
          final text = '{"format":"kusunga-export","version":1,${build(l)}}';
          expect(
            () => decodeImport(utf8.encode(text)),
            _rejected,
            reason: text,
          );
        }
      }
      final ok = decodeImport(
        utf8.encode(
          '{"format":"kusunga-export","version":1,"snippets":[{"name":'
          '"\\ud83d\\ude00","content":"\\ud83d\\ude80","type":"other"}]}',
        ),
      );
      expect(ok.snippets.single.name, '😀');
    });

    test('blank history text is refused in every form of white space; '
        'text with spaces around it is kept as it is', () {
      for (final blank in [' ', '\n', '\t', '\r\n', ' ', '  \n  ']) {
        expect(
          () => _decode(_file(history: [_clip(blank)])),
          _rejected,
          reason: jsonEncode(blank),
        );
      }
      final b = _decode(_file(history: [_clip('  padded \n')]));
      expect(b.history!.single.content, '  padded \n');
    });

    test('typed_shortcuts_on: only the whole numbers 0 and 1', () {
      for (final raw in [
        '1.0',
        '0.0',
        '1e0',
        '0.5',
        'true',
        '"1"',
        '2',
        '-1',
      ]) {
        expect(
          () => decodeImport(
            utf8.encode(
              '{"format":"kusunga-export","version":1,"snippets":[],'
              '"settings":{"typed_shortcuts_on":$raw}}',
            ),
          ),
          _rejected,
          reason: raw,
        );
      }
      for (final (raw, on) in [('0', false), ('1', true)]) {
        final b = decodeImport(
          utf8.encode(
            '{"format":"kusunga-export","version":1,"snippets":[],'
            '"settings":{"typed_shortcuts_on":$raw}}',
          ),
        );
        expect(b.settings!.typedShortcutsOn, on);
      }
    });

    test('times: only UTC, in the form Kusunga writes', () {
      for (final good in [
        '2026-11-12T09:30:00Z',
        '2026-11-12T09:30:00.1Z',
        '2026-11-12T09:30:00.123Z',
        '2026-11-12T09:30:00.123456Z',
        '2024-02-29T00:00:00Z',
        '0001-01-01T00:00:00.000Z',
      ]) {
        expect(
          _decode(_file(history: [_clip('h', last: good)])).history,
          hasLength(1),
          reason: good,
        );
      }
      for (final bad in [
        '2026-11-12T09:30:00',
        '2026-11-12T09:30:00+00:00',
        '2026-11-12T10:30:00+01:00',
        '2026-11-12T09:30:00-05:00',
        '2026-11-12t09:30:00z',
        '2026-11-12 09:30:00Z',
        '2026-11-12T09:30:00.1234567Z',
        '2026-11-12T09:30Z',
        '2026-11-12Z',
        '2026-11-12',
        '20261112T093000Z',
        '2026-11-12T24:00:00Z',
        '2026-11-12T23:59:60Z',
        '2026-11-12T09:60:00Z',
        '2026-13-01T00:00:00Z',
        '2026-00-10T00:00:00Z',
        '2026-11-00T00:00:00Z',
        '2026-11-31T00:00:00Z',
        '2026-02-29T00:00:00Z',
        '2100-02-29T00:00:00Z',
        '2026-11-12T09:30:00Z\n',
        ' 2026-11-12T09:30:00Z',
        '2026-11-12T09:30:00Z ',
        '２０２６-11-12T09:30:00Z', // full-width digits
        '+2026-11-12T09:30:00Z',
        '-0001-01-01T00:00:00Z',
      ]) {
        expect(
          () => _decode(_file(history: [_clip('h', last: bad)])),
          _rejected,
          reason: jsonEncode(bad),
        );
        expect(
          () => _decode(_file(history: [_clip('h', created: bad)])),
          _rejected,
          reason: jsonEncode(bad),
        );
      }
    });

    test('exported_at is held to the same rule, or may be missing', () {
      expect(_decode(_file(exportedAt: null)).snippets, isEmpty);
      expect(
        () => _decode(_file(exportedAt: '2026-02-30T00:00:00Z')),
        _rejected,
      );
      expect(
        () => _decode(_file(exportedAt: '2026-11-12T09:30:00+01:00')),
        _rejected,
      );
      expect(() => _decode(_file(exportedAt: 5)), _rejected);
      expect(
        _decode(_file(exportedAt: '9999-12-31T23:59:59Z')).snippets,
        isEmpty,
      );
    });

    test('what Kusunga writes is always read back: every millisecond form, '
        'at the oldest and newest times', () {
      for (final ms in [
        -62135596800000, // 0001-01-01
        0,
        1,
        999,
        1700000000123,
        1700000000000,
        253402300799999, // 9999-12-31T23:59:59.999
      ]) {
        final text = encodeExport(
          ExportBundle(
            snippets: const [],
            history: [
              ExportHistoryItem(
                content: 'h',
                kind: ClipKind.text,
                createdAt: ms,
                lastCopiedAt: ms,
              ),
            ],
          ),
          exportedAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        );
        final back = decodeImport(utf8.encode(text));
        expect(back.history!.single.lastCopiedAt, ms, reason: '$ms');
      }
    });

    test('a local-time export (exportedAt given in local time) is written '
        'in UTC with a Z', () {
      final text = encodeExport(
        const ExportBundle(snippets: []),
        exportedAt: DateTime(2026, 11, 12, 9, 30),
      );
      expect(jsonDecode(text)['exported_at'], endsWith('Z'));
      expect(decodeImport(utf8.encode(text)).snippets, isEmpty);
    });
  });

  group('the lead\'s time rules, in checkImportTimes', () {
    ExportBundle bundle(int created, int last) => ExportBundle(
      snippets: const [],
      history: [
        ExportHistoryItem(
          content: 'h',
          kind: ClipKind.text,
          createdAt: created,
          lastCopiedAt: last,
        ),
      ],
    );
    final limit = _nowMs + _day;

    test('exactly 24 h ahead is fine; one millisecond more refuses the '
        'whole file, for either time', () {
      expect(
        checkImportTimes(bundle(limit, limit), nowMs: _nowMs).history,
        hasLength(1),
      );
      expect(
        () => checkImportTimes(bundle(0, limit + 1), nowMs: _nowMs),
        _rejected,
      );
      expect(
        () => checkImportTimes(bundle(limit + 1, limit + 1), nowMs: _nowMs),
        _rejected,
      );
      expect(
        () => checkImportTimes(bundle(limit + 1, 0), nowMs: _nowMs),
        _rejected,
        reason: 'a creation far ahead, even with an old last copy',
      );
    });

    test('one future item among many refuses the file and the reason is '
        'badItem', () {
      final items = [
        for (var i = 0; i < 50; i++)
          ExportHistoryItem(
            content: 'h$i',
            kind: ClipKind.text,
            createdAt: _nowMs - i,
            lastCopiedAt: _nowMs - i,
          ),
        ExportHistoryItem(
          content: 'future',
          kind: ClipKind.text,
          createdAt: _nowMs,
          lastCopiedAt: _nowMs + 10 * _day,
        ),
      ];
      expect(
        () => checkImportTimes(
          ExportBundle(snippets: const [], history: items),
          nowMs: _nowMs,
        ),
        throwsA(
          isA<ImportRejected>().having(
            (e) => e.reason,
            'reason',
            ImportRejectReason.badItem,
          ),
        ),
      );
    });

    test('a last copy before its creation: the creation moves back to the '
        'last copy; equal and normal pairs are untouched; the rest of the '
        'bundle is kept', () {
      final b = checkImportTimes(
        ExportBundle(
          snippets: const [
            ExportSnippet(
              name: 'A',
              content: 'c',
              type: SnippetType.other,
              position: 3,
            ),
          ],
          history: [
            ExportHistoryItem(
              content: 'a',
              kind: ClipKind.text,
              createdAt: 100,
              lastCopiedAt: 50,
            ),
            ExportHistoryItem(
              content: 'b',
              kind: ClipKind.text,
              createdAt: 70,
              lastCopiedAt: 70,
            ),
            ExportHistoryItem(
              content: 'c',
              kind: ClipKind.text,
              createdAt: 10,
              lastCopiedAt: 90,
            ),
            ExportHistoryItem(
              content: 'd',
              kind: ClipKind.text,
              createdAt: -5,
              lastCopiedAt: -9,
            ),
          ],
          settings: const ExportSettings(historyLimit: 50),
          ignoredApps: const [IgnoredApp('com.a', 'A')],
        ),
        nowMs: _nowMs,
      );
      expect(
        [for (final h in b.history!) (h.createdAt, h.lastCopiedAt)],
        [(50, 50), (70, 70), (10, 90), (-9, -9)],
      );
      expect(b.snippets.single.position, 3);
      expect(b.settings!.historyLimit, 50);
      expect(b.ignoredApps!.single.appId, 'com.a');
    });

    test('a file with no history passes through unchanged', () {
      final b = ExportBundle(snippets: const []);
      expect(identical(checkImportTimes(b, nowMs: _nowMs), b), isTrue);
    });
  });

  group('through the service: checkImport, the confirm count and the '
      'import agree, and the check changes nothing', () {
    late FakeLog log;
    late FakeFilePort files;
    late String dbPath;
    late SqliteHistoryStore store;
    late HistoryService service;

    // History time stays at the service's day so the cut-off is real.
    int clock() => _nowMs;

    setUp(() {
      log = FakeLog();
      files = FakeFilePort();
      dbPath = p.join(dir.path, 'kusunga.db');
      store = SqliteHistoryStore.open(path: dbPath, keyHex: _key);
      service = HistoryService(
        store: store,
        source: FakeClipboardSource(),
        log: log,
        clock: clock,
        snippetStore: store.snippetStore(),
        ignoredAppStore: store.ignoredAppStore(),
      )..start();
    });
    tearDown(() async {
      await service.close();
      service.dispose();
    });

    YourDataService yd() => YourDataService(
      history: service,
      log: log,
      files: files,
      now: () => _serviceNow,
    );

    Future<ImportReady> check(Map<String, Object?> file) async {
      final path = p.join(dir.path, 'in.json');
      File(path).writeAsStringSync(jsonEncode(file));
      files.openPath = path;
      return await yd().checkImport() as ImportReady;
    }

    List<Object?> dump() {
      final db = sqlite3.open(dbPath);
      try {
        db.execute("PRAGMA hexkey = '$_key'");
        return [
          for (final t in [
            'snippets ORDER BY id',
            'clip_items ORDER BY id',
            'settings ORDER BY key',
            'ignored_apps ORDER BY app_id',
            'sqlite_sequence ORDER BY name',
          ])
            [
              for (final r in db.select(
                'SELECT * FROM ${t.startsWith('sqlite_sequence') ? t : t}',
              ))
                r.values.toList(),
            ],
        ];
      } on SqliteException {
        return [];
      } finally {
        db.close();
      }
    }

    int rows() => store.records().length;

    final ago = [for (var i = 0; i < 40; i++) _nowMs - (i + 1) * 60000];

    test('the check changes no row, no setting, no cached value, no log '
        'line about an import', () async {
      store.insertOrBump('existing', ClipKind.text, _nowMs - 5000);
      service.ignoredApps; // touch
      final before = dump();
      final limit = service.limit;
      final days = service.expiry.days;
      final apps = [for (final a in service.ignoredApps.list()) a.appId];
      final items = service.items.map((i) => i.preview).toList();
      final ready = await check(
        _file(
          snippets: [_snip('A')],
          history: [
            for (var i = 0; i < 40; i++)
              _clip('item $i', created: _iso(ago[i]), last: _iso(ago[i])),
            _clip(
              'existing',
              created: _iso(_nowMs - 9 * _day),
              last: _iso(_nowMs - 8 * _day),
            ),
          ],
          settings: {
            'history_limit': 10,
            'history_expiry_days': 1,
            'typed_shortcuts_on': 1,
            'paste_mode': 'copy_only',
          },
          apps: [
            {'app_id': 'com.vault', 'display_name': 'Vault'},
          ],
        ),
      );
      // limit 10 and the newer existing row stays: 9 of the new rows fit
      expect(ready.historyFor(applySettings: true), 9);
      // 40 new rows; the line for 'existing' merges and adds none
      expect(ready.historyFor(applySettings: false), 40);
      expect(dump(), before);
      expect(service.limit, limit);
      expect(store.limit, limit);
      expect(service.expiry.days, days);
      expect([for (final a in service.ignoredApps.list()) a.appId], apps);
      expect(service.items.map((i) => i.preview), items);
      expect(service.snippets.records(), isEmpty);
      expect(
        log.codes.where(
          (c) => const {
            LogCode.dataImported,
            LogCode.dataImportedHistory,
            LogCode.dataImportSkipped,
            LogCode.importFailed,
          }.contains(c),
        ),
        isEmpty,
      );
      // and the real import afterwards is not affected by the previews
      final done = yd().runImport(ready, applySettings: false) as ImportDone;
      expect(done.counts.historyAdded, 40);
      expect(rows(), 41);
    });

    for (final apply in [false, true]) {
      test('the confirm count equals what the import then adds '
          '(settings ${apply ? 'ticked' : 'not ticked'}): repeated lines, '
          'items already here, the limit and auto-delete', () async {
        for (var i = 0; i < 5; i++) {
          store.insertOrBump('here $i', ClipKind.text, _nowMs - (i + 1) * 1000);
        }
        final ready = await check(
          _file(
            history: [
              for (var i = 0; i < 30; i++)
                _clip('new $i', created: _iso(ago[i]), last: _iso(ago[i])),
              for (var i = 0; i < 4; i++) // the same line four times
                _clip(
                  'twice',
                  created: _iso(_nowMs - _day),
                  last: _iso(_nowMs - _day),
                ),
              for (var i = 0; i < 3; i++) // already here
                _clip(
                  'here $i',
                  created: _iso(_nowMs - 9),
                  last: _iso(_nowMs - 9),
                ),
              // older than 1 day: only too old when the file's days apply
              _clip(
                'two days old',
                created: _iso(_nowMs - 2 * _day),
                last: _iso(_nowMs - 2 * _day),
              ),
              // older than the 30 days of today: never added
              _clip(
                'ancient',
                created: _iso(_nowMs - 60 * _day),
                last: _iso(_nowMs - 60 * _day),
              ),
            ],
            settings: {'history_limit': 12, 'history_expiry_days': 1},
          ),
        );
        final expected = ready.historyFor(applySettings: apply);
        final before = rows();
        final done = yd().runImport(ready, applySettings: apply) as ImportDone;
        expect(done.counts.historyAdded, expected);
        final limit = apply ? 12 : 200;
        expect(rows(), lessThanOrEqualTo(limit));
        // Rows that are new and still there after the trim:
        final stillNew = store
            .records()
            .where(
              (r) =>
                  r.content.startsWith('new') ||
                  r.content == 'twice' ||
                  r.content == 'two days old',
            )
            .length;
        expect(stillNew, expected);
        expect(before, 5);
        expect(
          log.details[log.codes.lastIndexOf(LogCode.dataImportedHistory)],
          expected,
          reason: 'the log carries the same number',
        );
      });
    }

    test('without settings in the file the two counts are one number and '
        'the tick box changes nothing', () async {
      final ready = await check(
        _file(
          history: [_clip('a', last: _iso(_nowMs - 1000))],
          snippets: [],
        ),
      );
      expect(ready.hasSettings, isFalse);
      expect(
        ready.historyFor(applySettings: true),
        ready.historyFor(applySettings: false),
      );
    });

    test('a file whose history is all too old, or all here already, and no '
        'snippets: nothing to import', () async {
      store.insertOrBump('here', ClipKind.text, _nowMs - 1000);
      var ready = await check(
        _file(
          history: [
            _clip(
              'old',
              last: _iso(_nowMs - 90 * _day),
              created: _iso(_nowMs - 91 * _day),
            ),
          ],
        ),
      );
      expect(ready.isEmpty, isTrue);
      ready = await check(
        _file(
          history: [
            _clip(
              'here',
              last: _iso(_nowMs - 500),
              created: _iso(_nowMs - 500),
            ),
          ],
        ),
      );
      expect(ready.isEmpty, isTrue);
    });

    test('a file that is empty without its settings but has history with '
        'them is not "nothing to import"', () async {
      final ready = await check(
        _file(
          history: [
            _clip(
              'old',
              last: _iso(_nowMs - 60 * _day),
              created: _iso(_nowMs - 61 * _day),
            ),
          ],
          settings: {'history_expiry_days': 0},
        ),
      );
      expect(ready.historyFor(applySettings: false), 0);
      expect(ready.historyFor(applySettings: true), 1);
      expect(ready.isEmpty, isFalse);
    });

    test('a file that cannot be applied (over the 1,000 snippets): the '
        'count falls back to file lines, and the import fails and changes '
        'nothing', () async {
      for (var i = 0; i < 999; i++) {
        store.snippetStore().insert(
          name: 's$i',
          content: 'c$i',
          type: SnippetType.other,
          nowMs: 1,
        );
      }
      final before = dump();
      final ready = await check(
        _file(
          snippets: [_snip('new one'), _snip('new two')],
          history: [_clip('a', last: _iso(_nowMs - 1000))],
        ),
      );
      expect(ready.history, 1);
      expect(dump(), before);
      expect(
        yd().runImport(ready, applySettings: false),
        isA<ImportFailedResult>(),
      );
      expect(dump(), before);
    });

    test('a time more than a day ahead refuses the file with importRejected '
        '7 and changes nothing', () async {
      final before = dump();
      files.openPath = p.join(dir.path, 'future.json');
      File(files.openPath!).writeAsStringSync(
        jsonEncode(
          _file(
            history: [
              _clip('f', last: _iso(_nowMs + 2 * _day), created: _iso(_nowMs)),
            ],
          ),
        ),
      );
      expect(await yd().checkImport(), isA<ImportRefused>());
      expect(dump(), before);
      final i = log.codes.indexOf(LogCode.importRejected);
      expect(log.details[i], 7);
    });

    test('a last copy before its creation is stored with the creation set '
        'back, and a second import of the file changes nothing', () async {
      final last = _nowMs - 3 * _day;
      final ready = await check(
        _file(
          history: [
            _clip('odd', created: _iso(_nowMs - _day), last: _iso(last)),
          ],
        ),
      );
      yd().runImport(ready, applySettings: false);
      final r = store.records().single;
      expect(r.createdAt, last);
      expect(r.lastCopiedAt, last);
      final after = dump();
      yd().runImport(ready, applySettings: false);
      expect(dump(), after);
    });
  });

  group('T8: a data or profile folder that is a link', () {
    late FakeLog log;
    late FakeKeyStore keys;
    late FakeClipboardSource source;

    setUp(() {
      log = FakeLog();
      keys = FakeKeyStore(stored: _key);
      source = FakeClipboardSource();
    });

    HistoryService openIn(Directory d) {
      final store = SqliteHistoryStore.open(
        path: p.join(d.path, 'kusunga.db'),
        keyHex: _key,
      );
      final s = HistoryService(
        store: store,
        source: source,
        log: log,
        snippetStore: store.snippetStore(),
        ignoredAppStore: store.ignoredAppStore(),
      )..start();
      addTearDown(s.dispose);
      return s;
    }

    DataEraser eraser(EraseTarget t) => DataEraser(
      target: t,
      log: log,
      stopFileLog: () {},
      turnOffLogin: () async {},
    );

    test('the default data folder is a link: the key goes, nothing in the '
        'folder it points to is deleted, and the result says 1 file is '
        'left', () async {
      final real = Directory(p.join(dir.path, 'real'))..createSync();
      final h = openIn(real);
      File(p.join(real.path, 'kusunga.log')).writeAsStringSync('log');
      final link = Link(p.join(dir.path, 'support'))..createSync(real.path);
      final r = await eraser(
        DefaultEraseTarget(
          keys: keys,
          folder: () async => Directory(link.path),
        ),
      ).run(h);
      expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      expect(keys.stored, isNull, reason: 'the key is still deleted');
      expect(File(p.join(real.path, 'kusunga.db')).existsSync(), isTrue);
      expect(File(p.join(real.path, 'kusunga.log')).readAsStringSync(), 'log');
      expect(link.existsSync(), isTrue);
      expect(log.codes, contains(LogCode.deleteFileFailed));
    }, skip: Platform.isWindows);

    test('a dangling link as the folder: counted, nothing created or '
        'followed', () async {
      final h = openIn(Directory(dir.path)..createSync());
      final link = Link(p.join(dir.path, 'profiles-gone'))
        ..createSync(p.join(dir.path, 'nowhere'));
      final r = await eraser(
        ProfileEraseTarget(folder: () async => Directory(link.path)),
      ).run(h);
      expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      expect(Directory(p.join(dir.path, 'nowhere')).existsSync(), isFalse);
    }, skip: Platform.isWindows);

    test('a profile folder that is a link: its target and the key stay; '
        'one thing is counted as not removed', () async {
      final real = Directory(p.join(dir.path, 'real'))..createSync();
      final keep = File(p.join(real.path, 'keep.txt'))..writeAsStringSync('k');
      final h = openIn(real);
      final link = Link(p.join(dir.path, 'qa'))..createSync(real.path);
      final r = await eraser(
        ProfileEraseTarget(folder: () async => Directory(link.path)),
      ).run(h);
      expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      expect(keep.readAsStringSync(), 'k');
      expect(keys.deletes, 0);
      expect(link.existsSync(), isTrue);
    }, skip: Platform.isWindows);

    test('a data folder that does not exist: nothing to remove, not '
        'counted', () async {
      final h = openIn(Directory(dir.path));
      final r = await eraser(
        DefaultEraseTarget(
          keys: keys,
          folder: () async => Directory(p.join(dir.path, 'never-made')),
        ),
      ).run(h);
      expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
    });

    test('a data folder that can\'t be listed: counted as 1, with the OS '
        'number logged', () async {
      final h = openIn(Directory(dir.path));
      final locked = Directory(p.join(dir.path, 'locked'))..createSync();
      Process.runSync('chmod', ['000', locked.path]);
      final r = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => locked),
      ).run(h);
      Process.runSync('chmod', ['700', locked.path]);
      expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      final i = log.codes.indexOf(LogCode.deleteFileFailed);
      expect(log.details[i], isNotNull);
    }, skip: Platform.isWindows);
  });
}
