// Tester probes for the M1.4 privacy rule (design note, "Observability" and
// "Top 3 qualities"): no name, content or type in any log, and only codes
// from the closed list, with `pasteSource` carrying 0 (history) or 1
// (snippet). The real file log and the real unified-log mirror are used, with
// failures made to carry the sensitive text in their own messages.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/log/unified_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:kusunga/snippets/sqlite_snippet_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';
import 'qa_support.dart';

const _name = 'SENT-NAME-4821-Mum';
const _content = 'SENT-CONTENT-7733 07700 900123 https://example.com/x';
const _fail = 'SENT-IN-DB-ERROR-9911';

/// The codes this feature may write (design note, "Observability") plus the
/// existing ones a snippet path can reach.
const _allowedHere = {
  'snippetSaveFailed',
  'snippetDeleteFailed',
  'snippetMoveFailed',
  'snippetCapReached',
  'snippetsUnavailable',
  'pasteSource',
  'readFailed',
  'pasteFocusTimeout',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File file;
  late DeferredErrorLog log;
  late List<MethodCall> unified;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_snip_priv_');
    file = File('${dir.path}/kusunga.log');
    unified = [];
    const channel = MethodChannel('test/snippet-diag');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          unified.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    log = DeferredErrorLog(mirror: ChannelUnifiedLog(channel: channel))
      ..attach(FileErrorLog(file));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  SnippetService make(SnippetStore store, {bool editable = true}) =>
      SnippetService(
        store: store,
        log: log,
        editable: editable,
        writeClipboard: (_) async => true,
      );

  /// A snippets table on a plain in-memory SQLite, with triggers that make
  /// every write fail with a message that holds sensitive text.
  ({SqliteSnippetStore store, void Function() breakWrites}) sqliteStore() {
    final db = sqlite3.openInMemory();
    for (final sql in kMigrations[2].statements) {
      db.execute(sql);
    }
    // Version 4's shortcut column and index (the rest needs `settings`).
    for (final sql in kMigrations[3].statements.take(2)) {
      db.execute(sql);
    }
    return (
      store: SqliteSnippetStore(db),
      breakWrites: () {
        for (final op in ['INSERT', 'UPDATE', 'DELETE']) {
          db.execute(
            'CREATE TRIGGER fail_$op BEFORE $op ON snippets '
            "BEGIN SELECT RAISE(ABORT, '$_fail $_name $_content'); END",
          );
        }
      },
    );
  }

  void expectCleanLogs(String why) {
    final text = file.existsSync() ? file.readAsStringSync() : '';
    for (final secret in [
      _name,
      _content,
      _fail,
      'SENT-',
      '07700',
      'example.com',
      'Mum',
    ]) {
      expect(text, isNot(contains(secret)), reason: '$why: file log');
    }
    final codes = LogCode.values.map((c) => c.name).toSet();
    final line = RegExp(r'^\d{4}-\d\d-\d\dT[\d:.]+Z ([A-Za-z]+)( -?\d+)?$');
    for (final l in text.split('\n').where((l) => l.isNotEmpty)) {
      final m = line.firstMatch(l);
      expect(m, isNotNull, reason: '$why: "$l" is not "time code [number]"');
      expect(codes, contains(m!.group(1)), reason: '$why: $l');
    }
    for (final call in unified) {
      expect(call.method, 'log');
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      expect(args.keys.toSet(), {'code', 'detail'}, reason: why);
      expect(codes, contains(args['code']), reason: why);
      expect(args['detail'] is int?, isTrue, reason: '$why: ${args['detail']}');
      expect('${call.arguments}', isNot(contains('SENT-')), reason: why);
    }
  }

  List<String> codesInFile() => [
    for (final l in file.existsSync() ? file.readAsLinesSync() : <String>[])
      l.split(' ')[1],
  ];

  test('every failing write logs a code and the SQLite number, never the '
      'message that holds the name and the text', () {
    final s = sqliteStore();
    final service = make(s.store);
    final saved = service.save(
      name: _name,
      content: _content,
      type: SnippetType.phone,
    );
    final other = service.save(
      name: '$_name 2',
      content: _content,
      type: SnippetType.email,
    );
    s.breakWrites();
    expect(
      service
          .save(name: _name, content: _content, type: SnippetType.link)
          .outcome,
      SnippetSave.failed,
    );
    expect(
      service
          .save(
            id: saved.id,
            name: _name,
            content: _content,
            type: SnippetType.address,
          )
          .outcome,
      SnippetSave.failed,
    );
    expect(service.move(other.id!, 0), isFalse);
    expect(service.delete(saved.id!).failed, isTrue);
    expect(
      service.undo(
        SnippetRecord(
          name: _name,
          content: _content,
          type: SnippetType.other,
          position: 0,
          createdAt: 1,
          updatedAt: 1,
        ),
      ),
      isFalse,
    );
    expect(codesInFile(), [
      'snippetSaveFailed',
      'snippetSaveFailed',
      'snippetMoveFailed',
      'snippetDeleteFailed',
      'snippetSaveFailed',
    ]);
    // The number is the SQLite code, nothing else.
    for (final l in file.readAsLinesSync()) {
      expect(l.split(' ').length, 3, reason: l);
      expect(int.tryParse(l.split(' ')[2]), isNotNull, reason: l);
    }
    expectCleanLogs('failing writes');
  });

  test('cap, memory-only, read error, copy: only codes', () async {
    final capped = MemorySnippetStore();
    for (var i = 0; i < SnippetStore.maxCount; i++) {
      capped.insert(
        name: '$_name $i',
        content: _content,
        type: SnippetType.other,
        nowMs: i,
      );
    }
    final full = make(capped);
    expect(
      full
          .save(name: _name, content: _content, type: SnippetType.other)
          .outcome,
      SnippetSave.capReached,
    );

    final off = make(MemorySnippetStore(), editable: false);
    expect(
      off.save(name: _name, content: _content, type: SnippetType.other).outcome,
      SnippetSave.unavailable,
    );

    final flaky = ContentReadFailsStore();
    final f = make(flaky);
    final id = f
        .save(name: _name, content: _content, type: SnippetType.phone)
        .id!;
    flaky.failContentReads = true;
    expect(f.textOf(id), isNull);
    expect(await f.copy(id), isFalse);

    expect(
      codesInFile().toSet(),
      everyElement(isIn(_allowedHere)),
      reason: codesInFile().toString(),
    );
    expect(
      codesInFile(),
      containsAll(['snippetCapReached', 'snippetsUnavailable', 'readFailed']),
    );
    expectCleanLogs('cap, unavailable, read error');
  });

  group('pasteSource', () {
    late FakePickerPort port;
    late HistoryService history;
    late FakeClipboardSource source;
    late PickerController c;

    setUp(() async {
      port = FakePickerPort();
      source = FakeClipboardSource();
      history = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: log,
        snippetStore: MemorySnippetStore(),
      )..start();
      addTearDown(history.dispose);
      c = PickerController(port: port, log: log, isMac: true);
      addTearDown(c.dispose);
      await c.start();
      await c.attach(history);
      port.press();
    });

    test('carries 0 for history and 1 for a snippet, once per paste, and '
        'never the text', () async {
      source.copy(_content);
      final snippet = history.snippets
          .save(name: _name, content: _content, type: SnippetType.phone)
          .id!;
      await c.pasteItem(history.items.single.id);
      port.press();
      await c.pasteSnippet(snippet);
      port.press();
      await c.pasteSnippet(snippet);
      final lines = file
          .readAsLinesSync()
          .where((l) => l.contains('pasteSource'))
          .map((l) => l.split(' ').sublist(1).join(' '))
          .toList();
      expect(lines, ['pasteSource 0', 'pasteSource 1', 'pasteSource 1']);
      expectCleanLogs('paste');
    });

    test('a paste of something that is gone, or one that is refused while '
        'another runs, logs nothing about its source', () async {
      final before = codesInFile().length;
      await c.pasteSnippet(31337);
      await c.pasteItem(31337);
      expect(
        codesInFile().skip(before).where((c) => c == 'pasteSource'),
        isEmpty,
      );
    });

    test('a failed paste still logs only the source number and the '
        'existing paste codes', () async {
      final id = history.snippets
          .save(name: _name, content: _content, type: SnippetType.phone)
          .id!;
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await c.pasteSnippet(id);
      expect(
        codesInFile().toSet(),
        everyElement(isIn(_allowedHere)),
        reason: codesInFile().toString(),
      );
      expectCleanLogs('paste that only copies');
    });
  });

  test(
    'the closed list has the six M1.4 codes by name, and none is named after content',
    () {
      final names = LogCode.values.map((c) => c.name).toSet();
      expect(
        names,
        containsAll([
          'snippetSaveFailed',
          'snippetDeleteFailed',
          'snippetMoveFailed',
          'snippetCapReached',
          'snippetsUnavailable',
          'pasteSource',
        ]),
      );
      // Nothing named after a name, content or type was added.
      for (final n in names) {
        expect(
          n,
          isNot(
            matches(RegExp('name|content|text|type', caseSensitive: false)),
          ),
          reason: n,
        );
      }
    },
  );
}
