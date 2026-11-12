// M1.8 Delete everything (docs/design/your-data.md, "Delete all history and
// Delete everything"; lead rulings G3 and on the order, 2026-11-12). Key
// deletion is tested through fakes only: never the real keychain.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/data_eraser.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/data_profile.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

/// Records what reached the store, to prove nothing was written late.
class _Spy extends FlakyStore {
  _Spy(super.inner);
  final saved = <String>[];

  @override
  int insertOrBump(String content, ClipKind kind, int nowMs) {
    saved.add(content);
    return super.insertOrBump(content, kind, nowMs);
  }
}

void main() {
  late Directory base;
  late Directory folder;
  late FakeClipboardSource source;
  late FakeLog log;
  late FakeKeyStore keys;
  late List<String> steps;
  var now = 1000;

  setUp(() {
    base = Directory.systemTemp.createTempSync('kusunga_erase_');
    folder = base;
    source = FakeClipboardSource();
    log = FakeLog();
    keys = FakeKeyStore(stored: _key);
    steps = [];
  });
  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  ({HistoryService service, _Spy store}) open(Directory dir) {
    final sqlite = SqliteHistoryStore.open(
      path: p.join(dir.path, 'kusunga.db'),
      keyHex: _key,
    );
    final spy = _Spy(sqlite);
    final service = HistoryService(
      store: spy,
      source: source,
      log: log,
      clock: () => now += 10,
      snippetStore: sqlite.snippetStore(),
      ignoredAppStore: sqlite.ignoredAppStore(),
    )..start();
    addTearDown(service.dispose);
    return (service: service, store: spy);
  }

  void touch(Directory dir, List<String> names) {
    for (final n in names) {
      File(p.join(dir.path, n)).writeAsStringSync('x');
    }
  }

  List<String> names(Directory dir) =>
      [for (final e in dir.listSync(followLinks: false)) p.basename(e.path)]
        ..sort();

  DataEraser eraser(
    EraseTarget target, {
    Future<void> Function()? loginOff,
    void Function(FileSystemEntity e)? deleteEntity,
    Duration keyTimeout = const Duration(seconds: 30),
  }) => DataEraser(
    target: target,
    log: log,
    stopFileLog: () => steps.add('stopFileLog'),
    turnOffLogin: () async {
      steps.add('loginOff');
      await loginOff?.call();
    },
    deleteEntity: deleteEntity,
    keyTimeout: keyTimeout,
  );

  group('the default data', () {
    test('key first, then close, then every Kusunga file; nothing else; '
        'launch at login off (D6 A)', () async {
      final h = open(folder);
      source.copy('secret');
      touch(folder, [
        'kusunga.db.bak',
        'kusunga.db.unreadable-2026-11-01',
        'kusunga.db.unreadable-2026-11-01-2',
        'kusunga.log',
        'kusunga.log.1',
        'other-app.txt',
      ]);
      Directory(
        p.join(folder.path, 'profiles', 'qa'),
      ).createSync(recursive: true);
      keys.onDelete = () {
        steps.add('key');
        expect(File(p.join(folder.path, 'kusunga.db')).existsSync(), isTrue);
      };
      final result = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
      ).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      expect(keys.stored, isNull);
      expect(names(folder), ['other-app.txt', 'profiles']);
      expect(steps, ['key', 'stopFileLog', 'loginOff']);
      expect(log.codes, contains(LogCode.deleteEverythingDone));
    });

    test('no copy is written between the key delete and the close', () async {
      final h = open(folder);
      source.copy('before');
      keys.onDelete = () => source.copy('between');
      await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
      ).run(h.service);
      expect(h.store.saved, ['before']);
    });

    test('a failed key delete deletes nothing, logs its number, and '
        'recording carries on', () async {
      final h = open(folder);
      touch(folder, ['kusunga.log', 'kusunga.db.bak']);
      final before = names(folder);
      keys.deleteError = PlatformException(
        code: 'x',
        message: 'Code: -25244, Message: denied',
      );
      final result = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
      ).run(h.service);
      expect(result, isA<EraseFailed>());
      expect(keys.stored, _key);
      expect(names(folder), before);
      expect(steps, isEmpty, reason: 'no log stop, no login change');
      final i = log.codes.indexOf(LogCode.deleteEverythingFailed);
      expect(log.details[i], -25244);
      expect(log.codes, isNot(contains(LogCode.deleteEverythingDone)));
      source.copy('after');
      expect(h.service.items.map((i) => i.preview), ['after']);
    });

    test('a key delete that never answers counts as failed', () async {
      final h = open(folder);
      final hang = Completer<void>();
      final slow = _HangingKeys(hang.future);
      final result = await eraser(
        DefaultEraseTarget(keys: slow, folder: () async => folder),
        keyTimeout: const Duration(milliseconds: 20),
      ).run(h.service);
      expect(result, isA<EraseFailed>());
      expect(File(p.join(folder.path, 'kusunga.db')).existsSync(), isTrue);
    });

    test('a file that will not go after the key is gone: the rest go, the '
        'count says so, its number is logged', () async {
      final h = open(folder);
      touch(folder, ['kusunga.log', 'kusunga.log.1']);
      final result = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
        deleteEntity: (e) {
          if (p.basename(e.path) == 'kusunga.log') {
            throw const FileSystemException('busy', '', OSError('busy', 16));
          }
          e.deleteSync();
        },
      ).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      expect(names(folder), ['kusunga.log']);
      final i = log.codes.indexOf(LogCode.deleteFileFailed);
      expect(log.details[i], 16);
      expect(steps, contains('loginOff'), reason: 'carries on');
    });

    test(
      'a link named like a Kusunga file is removed, never followed',
      () async {
        final h = open(folder);
        final outside = Directory.systemTemp.createTempSync('kusunga_outside_');
        addTearDown(() => outside.deleteSync(recursive: true));
        final target = File(p.join(outside.path, 'keep.txt'))
          ..writeAsStringSync('k');
        Link(p.join(folder.path, 'kusunga.log.1')).createSync(target.path);
        await eraser(
          DefaultEraseTarget(keys: keys, folder: () async => folder),
        ).run(h.service);
        expect(target.existsSync(), isTrue);
        expect(names(folder), isEmpty);
      },
    );

    test('a data folder that is itself a link is never followed: the key '
        'still goes, nothing where it points is deleted, and it counts as '
        'not removed (T8)', () async {
      final real = Directory(p.join(base.path, 'real'))..createSync();
      final h = open(real);
      final link = Link(p.join(base.path, 'data'))..createSync(real.path);
      final result = await eraser(
        DefaultEraseTarget(
          keys: keys,
          folder: () async => Directory(link.path),
        ),
      ).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      expect(keys.stored, isNull);
      expect(File(p.join(real.path, 'kusunga.db')).existsSync(), isTrue);
      expect(link.existsSync(), isTrue);
      expect(log.codes, contains(LogCode.deleteFileFailed));
    });

    test('a data folder that can\'t be listed after the key is gone counts as '
        'not removed, with its number logged (T6)', () async {
      final data = Directory(p.join(base.path, 'data'))..createSync();
      final h = open(data);
      Process.runSync('chmod', ['000', data.path]);
      addTearDown(() => Process.runSync('chmod', ['755', data.path]));
      final result = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => data),
      ).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      expect(keys.stored, isNull);
      final i = log.codes.indexOf(LogCode.deleteFileFailed);
      expect(log.details[i], 13, reason: 'EACCES');
      expect(steps, contains('loginOff'), reason: 'carries on');
    }, skip: Platform.isWindows ? 'chmod needs a POSIX system' : false);

    test('a data folder that is not there has nothing left in it', () async {
      final h = open(Directory(p.join(base.path, 'session'))..createSync());
      final result = await eraser(
        DefaultEraseTarget(
          keys: keys,
          folder: () async => Directory(p.join(base.path, 'missing')),
        ),
      ).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      expect(log.codes, isNot(contains(LogCode.deleteFileFailed)));
    });

    test('a failed launch-at-login change never stops the quit', () async {
      final h = open(folder);
      final result = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
        loginOff: () async => throw StateError('os'),
      ).run(h.service);
      expect(result, isA<Erased>());
    });
  });

  group('a debug data profile', () {
    test('deletes only the profile folder; the shared key and launch at '
        'login are left alone (brief; lead ruling G3)', () async {
      touch(base, ['kusunga.db', 'kusunga.log']);
      final profile = Directory(p.join(base.path, 'profiles', 'qa'))
        ..createSync(recursive: true);
      final h = open(profile);
      touch(profile, ['kusunga.log', 'kusunga.db.bak']);
      final result = await eraser(
        ProfileEraseTarget(folder: () async => profile),
      ).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      expect(profile.existsSync(), isFalse);
      expect(names(base), ['kusunga.db', 'kusunga.log', 'profiles']);
      expect(keys.deletes, 0);
      expect(keys.stored, _key);
      expect(steps, ['stopFileLog'], reason: 'no login item change');
    });

    test('a profile folder that is itself a link, to a folder or to '
        'nothing: never followed, the link stays, and it counts as not '
        'removed (T8)', () async {
      final outside = Directory(p.join(base.path, 'outside'))..createSync();
      final keep = File(p.join(outside.path, 'kusunga.db'))
        ..writeAsStringSync('k');
      Directory(p.join(base.path, 'profiles')).createSync();
      final h = open(Directory(p.join(base.path, 'session'))..createSync());
      for (final target in [outside.path, p.join(base.path, 'gone')]) {
        log.codes.clear();
        final profile = Link(p.join(base.path, 'profiles', 'qa'))
          ..createSync(target);
        final result = await eraser(
          ProfileEraseTarget(folder: () async => Directory(profile.path)),
        ).run(h.service);
        expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
        expect(keep.readAsStringSync(), 'k');
        expect(profile.existsSync(), isTrue);
        expect(log.codes, contains(LogCode.deleteFileFailed));
        profile.deleteSync();
      }
    });

    test('a profile folder that can\'t be listed counts as not removed '
        '(T6)', () async {
      final h = open(Directory(p.join(base.path, 'session'))..createSync());
      final result = await eraser(
        ProfileEraseTarget(
          folder: () async => throw const FileSystemException(
            'denied',
            '',
            OSError('denied', 13),
          ),
        ),
      ).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 1));
      final i = log.codes.indexOf(LogCode.deleteFileFailed);
      expect(log.details[i], 13);
    });

    test('a rejected profile (memory only): nothing deleted anywhere, no '
        'key', () async {
      touch(base, ['kusunga.db', 'kusunga.log']);
      final service = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: log,
        notices: {HistoryNotice.memoryOnly},
      )..start();
      addTearDown(service.dispose);
      source.copy('in memory');
      final result = await eraser(const NoDataEraseTarget()).run(service);
      expect(result, isA<Erased>());
      expect(names(base), ['kusunga.db', 'kusunga.log']);
      expect(keys.deletes, 0);
      expect(service.items, isEmpty);
      expect(steps, ['stopFileLog']);
    });
  });

  group('a key delete that times out (T5): never record again while it '
      'might still complete', () {
    const limit = Duration(milliseconds: 20);

    DataEraser late(_LateKeys k) => eraser(
      DefaultEraseTarget(keys: k, folder: () async => folder),
      keyTimeout: limit,
    );

    test('the key is gone when read again: the deletion carries on', () async {
      final h = open(folder);
      final k = _LateKeys()..removedEarly = true;
      final result = await late(k).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      expect(k.reads, 1);
      expect(names(folder), isEmpty);
      expect(steps, ['stopFileLog', 'loginOff']);
      expect(log.codes, isNot(contains(LogCode.deleteEverythingFailed)));
    });

    test('still there, then the call succeeds while it is waited for: the '
        'deletion carries on', () async {
      final h = open(folder);
      final k = _LateKeys();
      k.onRead = () => Timer(Duration.zero, k.answer.complete);
      final result = await late(k).run(h.service);
      expect(result, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      expect(k.stored, isNull);
      expect(names(folder), isEmpty);
    });

    test('still there, then the call is refused: "Nothing was deleted", and '
        'recording resumes only after that answer', () async {
      final h = open(folder);
      source.copy('before');
      final k = _LateKeys();
      k.onRead = () {
        source.copy('while waiting');
        Timer(
          Duration.zero,
          () => k.answer.completeError(
            PlatformException(code: 'x', message: 'Code: -25244, Message: no'),
          ),
        );
      };
      final result = await late(k).run(h.service);
      expect(result, isA<EraseFailed>().having((e) => e.stuck, 'stuck', false));
      expect(k.stored, _key);
      expect(File(p.join(folder.path, 'kusunga.db')).existsSync(), isTrue);
      expect(steps, isEmpty);
      expect(
        log.codes.where((c) => c == LogCode.deleteEverythingFailed),
        hasLength(1),
      );
      final i = log.codes.indexOf(LogCode.deleteEverythingFailed);
      expect(log.details[i], -25244);
      source.copy('after');
      expect(h.service.items.map((i) => i.preview), ['after', 'before']);
    });

    test('no answer at all: stuck, so recording stays stopped for good and '
        'nothing is deleted or closed; a success after that stands '
        '(lead ruling B)', () async {
      final h = open(folder);
      final k = _LateKeys();
      final result = await late(k).run(h.service);
      expect(result, isA<EraseFailed>().having((e) => e.stuck, 'stuck', true));
      expect(k.reads, 1);
      expect(log.codes, contains(LogCode.deleteEverythingFailed));
      expect(steps, isEmpty);
      expect(h.store.closes, 0);
      expect(File(p.join(folder.path, 'kusunga.db')).existsSync(), isTrue);
      source.copy('later');
      await Future<void>.delayed(limit * 3);
      source.copy('much later');
      expect(h.service.items, isEmpty);
      k.answer.complete();
      await Future<void>.delayed(Duration.zero);
      expect(k.stored, isNull);
      source.copy('after the answer');
      expect(h.service.items, isEmpty);
    });

    test(
      'a read again that fails or never answers counts as still there',
      () async {
        for (final setUp in <void Function(_LateKeys)>[
          (k) => k.readError = StateError('locked'),
          (k) => k.hangRead = true,
        ]) {
          final h = open(folder);
          final k = _LateKeys();
          setUp(k);
          final result = await late(k).run(h.service);
          expect(result, isA<EraseFailed>().having((e) => e.stuck, 's', true));
          expect(File(p.join(folder.path, 'kusunga.db')).existsSync(), isTrue);
          await h.service.close();
        }
      },
    );

    test('memory only: a time-out is logged and the rest goes on, without '
        'reading the key or waiting again', () async {
      touch(folder, ['kusunga.db']);
      final service = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: log,
        notices: {HistoryNotice.memoryOnly},
      )..start();
      addTearDown(service.dispose);
      final k = _LateKeys();
      final result = await late(k).run(service);
      expect(result, isA<Erased>());
      expect(k.reads, 0);
      expect(names(folder), isEmpty);
      expect(log.codes, contains(LogCode.deleteEverythingFailed));
    });
  });

  test('memory-only (keychain unusable): the key delete is tried, a failure '
      'is logged and the rest goes on', () async {
    touch(folder, ['kusunga.db', 'kusunga.log']);
    final store = MemoryHistoryStore();
    final service = HistoryService(
      store: store,
      source: source,
      log: log,
      notices: {HistoryNotice.memoryOnly},
    )..start();
    addTearDown(service.dispose);
    source.copy('in memory');
    keys.deleteError = StateError('no keychain');
    final result = await eraser(
      DefaultEraseTarget(keys: keys, folder: () async => folder),
    ).run(service);
    expect(result, isA<Erased>());
    expect(store.count, 0, reason: 'the memory store is emptied');
    expect(names(folder), isEmpty);
    expect(log.codes, contains(LogCode.deleteEverythingFailed));
    expect(steps, ['stopFileLog', 'loginOff']);
  });

  test(
    'an incompatible session (key readable): a key failure stops it',
    () async {
      touch(folder, ['kusunga.db']);
      final service = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: log,
        notices: {HistoryNotice.incompatible},
      )..start();
      addTearDown(service.dispose);
      keys.deleteError = StateError('denied');
      final result = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
      ).run(service);
      expect(result, isA<EraseFailed>());
      expect(names(folder), ['kusunga.db']);
    },
  );

  test('HistoryStore is closed before files go', () async {
    final h = open(folder);
    var closedAtDelete = false;
    await eraser(
      DefaultEraseTarget(keys: keys, folder: () async => folder),
      deleteEntity: (e) {
        closedAtDelete = h.store.closes > 0;
        e.deleteSync();
      },
    ).run(h.service);
    expect(closedAtDelete, isTrue);
  });

  test('a profile\'s key store refuses to delete the shared key', () async {
    final setup = dataProfileSetup(
      const ActiveDataProfile('qa'),
      supportDirectory: () async => base,
      keys: keys,
      log: log,
    );
    await expectLater(setup.keys.delete(), throwsStateError);
    expect(keys.stored, _key);
    expect(keys.deletes, 0);
  });
}

class _HangingKeys extends FakeKeyStore {
  _HangingKeys(this.pending) : super(stored: _key);
  final Future<void> pending;
  @override
  Future<void> delete() => pending;
}

/// A key store whose delete answers only when the test says so, and which
/// runs [onRead] when the key is read again (T5).
class _LateKeys implements KeyStore {
  String? stored = _key;
  final answer = Completer<void>();

  /// The keychain has already removed the key; only its answer is late.
  bool removedEarly = false;
  void Function()? onRead;
  Object? readError;
  bool hangRead = false;
  int reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    onRead?.call();
    if (hangRead) return Completer<String?>().future;
    if (readError != null) throw readError!;
    return stored;
  }

  @override
  Future<void> write(String keyHex) async => stored = keyHex;

  @override
  Future<void> delete() async {
    if (removedEarly) stored = null;
    await answer.future;
    stored = null;
  }
}
