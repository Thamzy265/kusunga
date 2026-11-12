// M1.8 tester: the timing branches of Delete everything's key delete
// (lead ruling B on T5, 2026-11-12): the delete times out, the key is read
// again, and the result depends on what the keychain says. Fakes only: a key
// store whose delete and read are controlled here, never the real keychain.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/data_eraser.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _t = Duration(milliseconds: 200);

/// A key store where each call can answer now, late, with an error, or never.
class _Keys implements KeyStore {
  String? stored = _key;
  int deleteCalls = 0;
  int readCalls = 0;
  int writeCalls = 0;
  final deleteGate = Completer<void>();
  final readGate = Completer<String?>();

  /// How each call behaves. delete: 'now', 'throw', 'hang'. read: 'now',
  /// 'throw', 'hang', 'gone' (answers null although delete is still out).
  String deleteMode = 'hang';
  String readMode = 'now';

  @override
  Future<void> delete() async {
    deleteCalls++;
    switch (deleteMode) {
      case 'now':
        stored = null;
      case 'throw':
        throw StateError('refused');
      default:
        await deleteGate.future; // completes or fails when the test says
        stored = null;
    }
  }

  @override
  Future<String?> read() async {
    readCalls++;
    switch (readMode) {
      case 'throw':
        throw StateError('unreachable');
      case 'hang':
        return readGate.future;
      case 'gone':
        return null;
      default:
        return stored;
    }
  }

  @override
  Future<void> write(String keyHex) async {
    writeCalls++;
    stored = keyHex;
  }
}

void main() {
  late Directory dir;
  late FakeLog log;
  late FakeClipboardSource source;
  late List<String> steps;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_tester_keys_');
    log = FakeLog();
    source = FakeClipboardSource();
    steps = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryService open() {
    final store = SqliteHistoryStore.open(
      path: p.join(dir.path, 'kusunga.db'),
      keyHex: _key,
    );
    final h = HistoryService(
      store: store,
      source: source,
      log: log,
      snippetStore: store.snippetStore(),
      ignoredAppStore: store.ignoredAppStore(),
    )..start();
    addTearDown(h.dispose);
    return h;
  }

  DataEraser eraser(_Keys keys) => DataEraser(
    target: DefaultEraseTarget(keys: keys, folder: () async => dir),
    log: log,
    stopFileLog: () => steps.add('stopFileLog'),
    turnOffLogin: () async => steps.add('loginOff'),
    keyTimeout: _t,
  );

  bool dbExists() => File(p.join(dir.path, 'kusunga.db')).existsSync();

  test('answers in time: gone, no re-read', () async {
    final keys = _Keys()..deleteMode = 'now';
    final r = await eraser(keys).run(open());
    expect(r, isA<Erased>());
    expect(keys.readCalls, 0);
    expect(dbExists(), isFalse);
  });

  test('a refusal in time: kept, nothing deleted, recording resumes, no '
      're-read', () async {
    final keys = _Keys()..deleteMode = 'throw';
    final h = open();
    final r = await eraser(keys).run(h);
    expect(r, isA<EraseFailed>().having((e) => e.stuck, 'stuck', false));
    expect(keys.readCalls, 0);
    expect(dbExists(), isTrue);
    source.copy('after');
    expect(h.items.map((i) => i.preview), ['after']);
    expect(
      log.codes.where((c) => c == LogCode.deleteEverythingFailed),
      hasLength(1),
    );
  });

  test('timed out, the re-read says the key is gone: carries on and '
      'deletes the files, though the call is still out', () async {
    final keys = _Keys()..readMode = 'gone';
    final r = await eraser(keys).run(open());
    expect(r, isA<Erased>());
    expect(dbExists(), isFalse);
    expect(steps, ['stopFileLog', 'loginOff']);
    keys.deleteGate.complete(); // the late call ends: nothing happens
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(keys.writeCalls, 0);
  });

  test('timed out, key still there, then the late call succeeds in the '
      'second wait: the success stands', () async {
    final keys = _Keys();
    final h = open();
    Timer(_t * 1.5, keys.deleteGate.complete);
    final r = await eraser(keys).run(h);
    expect(r, isA<Erased>());
    expect(keys.stored, isNull);
    expect(dbExists(), isFalse);
    expect(keys.writeCalls, 0);
    expect(
      keys.deleteCalls,
      1,
      reason: 'the same call is waited for once more',
    );
  });

  test('timed out, key still there, then the late call is refused in the '
      'second wait: "nothing deleted", recording resumes', () async {
    final keys = _Keys();
    final h = open();
    Timer(_t * 1.5, () => keys.deleteGate.completeError(StateError('no')));
    final r = await eraser(keys).run(h);
    expect(r, isA<EraseFailed>().having((e) => e.stuck, 'stuck', false));
    expect(keys.stored, _key);
    expect(dbExists(), isTrue);
    source.copy('after');
    expect(h.items.map((i) => i.preview), ['after']);
    expect(steps, isEmpty);
  });

  test('no answer at all: stuck; capture never resumes; files, key and '
      'login item untouched; a late success is not written back', () async {
    final keys = _Keys();
    final h = open();
    source.copy('before');
    final r = await eraser(keys).run(h);
    expect(r, isA<EraseFailed>().having((e) => e.stuck, 'stuck', true));
    expect(dbExists(), isTrue);
    expect(steps, isEmpty);
    expect(log.codes, isNot(contains(LogCode.deleteEverythingDone)));
    source.copy('later');
    expect(h.items.map((i) => i.preview), ['before']);
    keys.deleteGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    source.copy('even later');
    expect(h.items.map((i) => i.preview), ['before']);
    expect(keys.writeCalls, 0);
    expect(keys.deleteCalls, 1);
  });

  test('stuck is logged once, with no number', () async {
    final keys = _Keys();
    await eraser(keys).run(open());
    final i = log.codes.indexOf(LogCode.deleteEverythingFailed);
    expect(i, isNot(-1));
    expect(log.details[i], isNull);
    expect(
      log.codes.where((c) => c == LogCode.deleteEverythingFailed),
      hasLength(1),
    );
  });

  test(
    'a re-read that hangs is given up on after one time-out, then the '
    'late call is waited for once: stuck, in about three time-outs',
    () async {
      final keys = _Keys()..readMode = 'hang';
      final sw = Stopwatch()..start();
      final r = await eraser(keys).run(open());
      sw.stop();
      expect(r, isA<EraseFailed>().having((e) => e.stuck, 'stuck', true));
      expect(sw.elapsed, lessThan(_t * 6), reason: 'never waits for ever');
      expect(sw.elapsed, greaterThanOrEqualTo(_t * 2));
    },
  );

  test('a re-read that throws counts as "still there": waits once more, a '
      'late success stands', () async {
    final keys = _Keys()..readMode = 'throw';
    Timer(_t * 1.5, keys.deleteGate.complete);
    final r = await eraser(keys).run(open());
    expect(r, isA<Erased>());
  });

  test('a re-read that hangs, then the late call succeeds in the last '
      'wait: carries on', () async {
    final keys = _Keys()..readMode = 'hang';
    Timer(_t * 2.5, keys.deleteGate.complete);
    final r = await eraser(keys).run(open());
    expect(r, isA<Erased>());
    expect(dbExists(), isFalse);
  });

  test('memory only: a hanging delete is tried once and the rest goes on '
      'after one time-out, with no re-read and no stuck', () async {
    final keys = _Keys();
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      notices: {HistoryNotice.memoryOnly},
    )..start();
    addTearDown(h.dispose);
    File(p.join(dir.path, 'kusunga.db')).writeAsStringSync('x');
    source.copy('in memory');
    final sw = Stopwatch()..start();
    final r = await eraser(keys).run(h);
    expect(r, isA<Erased>());
    expect(keys.readCalls, 0);
    expect(sw.elapsed, lessThan(_t * 3));
    expect(h.items, isEmpty);
    expect(dbExists(), isFalse);
    expect(log.codes, contains(LogCode.deleteEverythingFailed));
  });

  test('memory only: a key delete that is refused still goes on', () async {
    final keys = _Keys()..deleteMode = 'throw';
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      notices: {HistoryNotice.memoryOnly},
    )..start();
    addTearDown(h.dispose);
    expect(await eraser(keys).run(h), isA<Erased>());
  });

  test('the keychain answering after the whole run was given up never '
      'brings the key or a file back', () async {
    final keys = _Keys();
    final h = open();
    await eraser(keys).run(h);
    keys.deleteGate.completeError(StateError('late refusal'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(keys.stored, _key);
    expect(keys.writeCalls, 0);
    expect(dbExists(), isTrue);
  });
}
