import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/channel_clipboard_source.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/sqlite_snippet_store.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_wiring_');
    log = FakeLog();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<OpenedHistory> open(
    FakeKeyStore keys, {
    List<Migration> migrations = kMigrations,
  }) => openHistory(
    keys: keys,
    directory: dir.path,
    log: log,
    random: Random(1),
    today: () => DateTime(2026, 11, 4),
    migrations: migrations,
  );

  group('openHistory gives the snippets the same file', () {
    test('a working store: snippets in the encrypted file', () async {
      final opened = await open(FakeKeyStore(stored: _key));
      expect(opened.snippets, isA<SqliteSnippetStore>());
      opened.snippets.insert(
        name: 'A',
        content: 'kept',
        type: SnippetType.other,
        nowMs: 1,
      );
      opened.store.close();
      final again = await open(FakeKeyStore(stored: _key));
      expect(again.snippets.list().single.name, 'A');
      again.store.close();
    });

    test('memory only: snippets in memory', () async {
      final opened = await open(FakeKeyStore()..readError = 'no keychain');
      expect(opened.notices, {HistoryNotice.memoryOnly});
      expect(opened.snippets, isA<MemorySnippetStore>());
    });

    test('incompatible (newer file): snippets in memory', () async {
      final newer = await open(
        FakeKeyStore(stored: _key),
        migrations: [
          ...kMigrations,
          Migration(version: kMigrations.length + 1, statements: const []),
        ],
      );
      newer.store.close();
      final opened = await open(FakeKeyStore(stored: _key));
      expect(opened.notices, {HistoryNotice.incompatible});
      expect(opened.snippets, isA<MemorySnippetStore>());
    });
  });

  test('a backup that cannot be written (TB-1): memory only with its own '
      'notice (F1), its own log code, the v2 file left as it is', () async {
    final v2 = await open(
      FakeKeyStore(stored: _key),
      migrations: kMigrations.sublist(0, 2),
    );
    v2.store.insertOrBump('kept', ClipKind.text, 1);
    v2.store.close();
    final path = '${dir.path}/kusunga.db';
    final before = File(path).readAsBytesSync();
    Directory('$path.bak').createSync(); // the copy cannot be written
    final opened = await open(FakeKeyStore(stored: _key));
    expect(opened.store, isA<MemoryHistoryStore>());
    expect(opened.snippets, isA<MemorySnippetStore>());
    expect(opened.notices, {HistoryNotice.backupFailed});
    expect(log.codes, contains(LogCode.migrationBackupFailed));
    expect(log.codes, isNot(contains(LogCode.storeUnreadable)));
    expect(File(path).readAsBytesSync(), before);
    expect(Directory('$path.bak').existsSync(), isTrue, reason: 'not ours');
  });

  test('a backup that was already there and cannot be overwritten is kept '
      '(F7)', () async {
    final v2 = await open(
      FakeKeyStore(stored: _key),
      migrations: kMigrations.sublist(0, 2),
    );
    v2.store.close();
    final path = '${dir.path}/kusunga.db';
    final old = File('$path.bak')..writeAsStringSync('an earlier copy');
    await Process.run('chmod', ['0444', old.path]);
    addTearDown(() => Process.runSync('chmod', ['0644', old.path]));
    final opened = await open(FakeKeyStore(stored: _key));
    expect(opened.notices, {HistoryNotice.backupFailed});
    expect(old.existsSync(), isTrue, reason: 'not made by this attempt');
    expect(old.readAsStringSync(), 'an earlier copy');
  }, skip: Platform.isWindows ? 'chmod' : false);

  group('HistoryService.snippets', () {
    HistoryService make(Set<HistoryNotice> notices) => HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: log,
      notices: notices,
      snippetStore: MemorySnippetStore(),
    );

    test('editable when history is kept', () {
      final h = make({});
      expect(h.snippets.canEdit, isTrue);
      expect(h.snippets.banners, isEmpty);
    });

    test('off with the banner when memory only or incompatible', () {
      for (final n in [HistoryNotice.memoryOnly, HistoryNotice.incompatible]) {
        final h = make({n});
        expect(h.snippets.canEdit, isFalse, reason: '$n');
        expect(h.snippets.banners, {SnippetBanner.unavailable});
      }
      expect(log.codes, [
        LogCode.snippetsUnavailable,
        LogCode.snippetsUnavailable,
      ]);
    });

    test('a read error on the history file does not stop snippets', () {
      final h = make({HistoryNotice.readError});
      expect(h.snippets.canEdit, isTrue);
    });

    test('closing the history stops snippet changes', () async {
      final h = make({});
      await h.close();
      expect(h.snippets.canEdit, isFalse);
    });

    test('Copy writes through the source as an own change', () async {
      final source = FakeClipboardSource();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: log,
        snippetStore: MemorySnippetStore(),
      );
      final id = h.snippets
          .save(name: 'A', content: 'mine', type: SnippetType.other)
          .id!;
      expect(await h.snippets.copy(id), isTrue);
      expect(source.ownWrites, ['mine']);
    });
  });

  group('ChannelClipboardSource.writeOwn', () {
    const methods = MethodChannel('com.wnasoni.kusunga/clipboard');
    final messenger = binding.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(methods, null));

    test('asks native to write and remember its own change', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return true;
      });
      expect(await ChannelClipboardSource().writeOwn('text'), isTrue);
      expect(calls.single.method, 'writeOwn');
      expect(calls.single.arguments, {'text': 'text'});
    });

    test('a native failure or a wrong answer is false', () async {
      messenger.setMockMethodCallHandler(methods, (call) async {
        throw PlatformException(code: 'x');
      });
      expect(await ChannelClipboardSource().writeOwn('t'), isFalse);
      messenger.setMockMethodCallHandler(methods, (call) async => 'yes');
      expect(await ChannelClipboardSource().writeOwn('t'), isFalse);
    });
  });
}
