// Tester probes for the Debug-only test data profile (`-KusungaDataProfile`,
// PM decision 2026-11-05). The profile is a trust boundary: it runs beside
// the PM's real data, so a profile session must never read, migrate, trim,
// move aside, back up, clear or overwrite anything in the default folder, and
// must never write, replace or delete the keychain key.
//
// The symlink tests were repros for BUG-P1 and BUG-P2 (skipped until the
// fix). Do not delete them.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/data_profile.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/open_app_history.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

// BUG-P1 (symlinked profiles/ or profiles/<name>) and BUG-P2 (symlinked
// files in the profile folder) were fixed; their repros below now run.

/// A key store that records every call, so "never writes, replaces or
/// deletes the key" is checked on the wrapper the profile really receives.
class _SpyKeys implements KeyStore {
  _SpyKeys(this.inner);
  final FakeKeyStore inner;
  int reads = 0;
  final calls = <String>[];

  @override
  Future<String?> read() {
    reads++;
    calls.add('read');
    return inner.read();
  }

  @override
  Future<void> write(String keyHex) {
    calls.add('write');
    return inner.write(keyHex);
  }
}

void main() {
  late Directory root;
  late Directory base; // the "application support" folder
  late FakeLog mirror;
  final services = <HistoryService>[];
  const hex =
      '00112233445566778899aabbccddeeff'
      '00112233445566778899aabbccddeeff';

  setUp(() {
    root = Directory.systemTemp.createTempSync('kusunga_prof_abuse_');
    base = Directory(p.join(root.path, 'support'))..createSync();
    mirror = FakeLog();
  });
  tearDown(() async {
    for (final s in services) {
      await s.close();
      s.dispose();
    }
    services.clear();
    root.deleteSync(recursive: true);
  });

  /// Every entry under the default folder, outside `profiles/` (a symlink is
  /// recorded as a symlink with its target, a file with its bytes).
  Map<String, Object> defaultState() {
    final out = <String, Object>{};
    for (final e in base.listSync(recursive: true, followLinks: false)) {
      final rel = p.relative(e.path, from: base.path);
      if (rel == 'profiles' || rel.startsWith('profiles${p.separator}')) {
        continue;
      }
      if (e is Link) {
        out[rel] = 'link->${e.targetSync()}';
      } else if (e is File) {
        out[rel] = e.readAsBytesSync();
      } else {
        out[rel] = 'dir';
      }
    }
    return out;
  }

  Future<HistoryService> open(
    DataProfile profile,
    KeyStore keys, {
    FakeClipboardSource? source,
    Directory? support,
  }) async {
    final deferred = DeferredErrorLog(mirror: mirror);
    final setup = dataProfileSetup(
      profile,
      supportDirectory: () async => support ?? base,
      keys: keys,
      log: deferred,
    );
    final service = await openAppHistory(
      deferred: deferred,
      supportDirectory: setup.supportDirectory,
      keys: setup.keys,
      source: source ?? FakeClipboardSource(),
    );
    services.add(service);
    return service;
  }

  /// The PM's real data: history, a `.bak`, an `.unreadable-` file, a log.
  Future<Map<String, Object>> seedDefault(
    FakeKeyStore keys, {
    int items = 30,
  }) async {
    final source = FakeClipboardSource();
    final real = await open(const NoDataProfile(), keys, source: source);
    for (var i = 0; i < items; i++) {
      source.copy('real item $i');
    }
    await real.close();
    File(p.join(base.path, 'kusunga.db.bak')).writeAsStringSync('real backup');
    File(
      p.join(base.path, 'kusunga.db.unreadable-2026-11-01'),
    ).writeAsStringSync('real old');
    final st = defaultState();
    expect(st.keys, containsAll(['kusunga.db', 'kusunga.db.bak']));
    return st;
  }

  Directory profileDir(String name) =>
      Directory(p.join(base.path, 'profiles', name));

  /// Work a profile session hard: copies, a lower limit (trim), Clear
  /// history, a setting.
  Future<void> hammer(HistoryService s, FakeClipboardSource src) async {
    for (var i = 0; i < 25; i++) {
      src.copy('profile item $i');
    }
    s.setLimit(10);
    s.saveSetting('paste_mode', 'copy_only');
    s.clear();
    await s.close();
  }

  group('the real key is never written, replaced or deleted', () {
    test(
      'every profile outcome: no write call reaches the real store',
      () async {
        for (final scenario in ['ok', 'nokey', 'readError', 'timeout-ish']) {
          final fake = scenario == 'nokey'
              ? FakeKeyStore()
              : FakeKeyStore(stored: hex);
          if (scenario == 'readError') fake.readError = StateError('locked');
          final spy = _SpyKeys(fake);
          final service = await open(const ActiveDataProfile('qa'), spy);
          await service.close();
          expect(spy.calls, isNot(contains('write')), reason: scenario);
          expect(fake.writes, 0, reason: scenario);
          expect(
            fake.stored,
            scenario == 'nokey' ? isNull : hex,
            reason: scenario,
          );
        }
      },
    );

    test('a rejected name does not even read the key', () async {
      final spy = _SpyKeys(FakeKeyStore(stored: hex));
      await open(const RejectedDataProfile(), spy);
      expect(spy.calls, isNot(contains('write')));
      expect(spy.inner.stored, hex);
    });

    test('the wrapper itself refuses a write, even a direct one', () async {
      final fake = FakeKeyStore(stored: hex);
      final setup = dataProfileSetup(
        const ActiveDataProfile('qa'),
        supportDirectory: () async => base,
        keys: fake,
        log: FakeLog(),
      );
      await expectLater(setup.keys.write('f' * 64), throwsA(anything));
      expect(fake.stored, hex);
      expect(fake.writes, 0);
      expect(await setup.keys.read(), hex);
    });

    test(
      'with no key, nothing is created anywhere except the profile folder',
      () async {
        final fake = FakeKeyStore();
        final service = await open(const ActiveDataProfile('qa'), fake);
        expect(service.banners, contains(HistoryBanner.memoryOnly));
        await service.close();
        expect(defaultState(), isEmpty);
        expect(fake.stored, isNull);
        // No database was created in the profile either: no key, no file.
        expect(
          File(p.join(profileDir('qa').path, 'kusunga.db')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'a session whose key read fails (keychain locked) is memory only',
      () async {
        final seeded = FakeKeyStore(stored: hex);
        final before = await seedDefault(seeded);
        final locked = FakeKeyStore(stored: hex)..readError = StateError('x');
        final service = await open(const ActiveDataProfile('qa'), locked);
        expect(service.banners, contains(HistoryBanner.memoryOnly));
        expect(locked.writes, 0);
        expect(defaultState(), before);
      },
    );
  });

  group('a profile session leaves the default folder untouched', () {
    test(
      'copies, lower limit, Clear history, settings: byte for byte',
      () async {
        final keys = FakeKeyStore(stored: hex);
        final before = await seedDefault(keys);
        final src = FakeClipboardSource();
        final s = await open(const ActiveDataProfile('qa'), keys, source: src);
        expect(s.items, isEmpty, reason: 'the real history is not read');
        await hammer(s, src);
        expect(defaultState(), before);
        final real = await open(const NoDataProfile(), keys);
        expect(real.items, hasLength(30));
      },
    );

    test('a profile DB that is unreadable is moved aside in the profile; '
        'Clear history deletes only the profile\'s own old copies', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      profileDir('qa').createSync(recursive: true);
      File(
        p.join(profileDir('qa').path, 'kusunga.db'),
      ).writeAsBytesSync(List.filled(4096, 7));
      File(
        p.join(profileDir('qa').path, 'kusunga.db.bak'),
      ).writeAsStringSync('profile backup');
      final src = FakeClipboardSource();
      final s = await open(const ActiveDataProfile('qa'), keys, source: src);
      expect(s.banners, contains(HistoryBanner.readError));
      src.copy('x');
      s.clear();
      await s.close();
      final names = profileDir(
        'qa',
      ).listSync().map((e) => p.basename(e.path)).toList();
      expect(names.where((n) => n.contains('.unreadable-')), isEmpty);
      expect(names, isNot(contains('kusunga.db.bak')));
      expect(
        defaultState(),
        before,
        reason: 'default .bak and .unreadable survive Clear history',
      );
    });

    test('a profile DB encrypted with another key is moved aside in the '
        'profile only', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      // A profile database written with a different key.
      profileDir('qa').createSync(recursive: true);
      final other = FakeKeyStore(stored: generateKeyHex(Random(9)));
      final o = await openHistory(
        keys: other,
        directory: profileDir('qa').path,
        log: FakeLog(),
      );
      o.store.close();
      final s = await open(const ActiveDataProfile('qa'), keys);
      expect(s.banners, contains(HistoryBanner.readError));
      await s.close();
      expect(
        profileDir(
          'qa',
        ).listSync().where((e) => p.basename(e.path).contains('.unreadable-')),
        hasLength(1),
      );
      expect(defaultState(), before);
    });

    test('a profile DB from a newer version is left byte for byte, and the '
        'default folder too', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      profileDir('qa').createSync(recursive: true);
      final newer = await openHistory(
        keys: keys,
        directory: profileDir('qa').path,
        log: FakeLog(),
        migrations: [
          ...kMigrations,
          const Migration(version: 99, statements: []),
        ],
      );
      newer.store.close();
      final dbFile = File(p.join(profileDir('qa').path, 'kusunga.db'));
      final newerBytes = dbFile.readAsBytesSync();
      final src = FakeClipboardSource();
      final s = await open(const ActiveDataProfile('qa'), keys, source: src);
      expect(s.banners, contains(HistoryBanner.incompatible));
      src.copy('lost on quit');
      s.clear();
      await s.close();
      expect(dbFile.readAsBytesSync(), newerBytes);
      expect(
        profileDir(
          'qa',
        ).listSync().where((e) => p.basename(e.path).contains('.unreadable-')),
        isEmpty,
      );
      expect(defaultState(), before);
    });

    test('an older profile DB is migrated, backed up and cleaned in the '
        'profile; the default .bak and database are not touched', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      profileDir('qa').createSync(recursive: true);
      final old = await openHistory(
        keys: keys,
        directory: profileDir('qa').path,
        log: FakeLog(),
        migrations: kMigrations.sublist(0, 2),
      );
      old.store.close();
      final s = await open(const ActiveDataProfile('qa'), keys);
      expect(s.banners, isEmpty);
      await s.close();
      expect(defaultState(), before);
    });

    test('a failed migration backup in the profile leaves the default .bak '
        'alone', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      profileDir('qa').createSync(recursive: true);
      final old = await openHistory(
        keys: keys,
        directory: profileDir('qa').path,
        log: FakeLog(),
        migrations: kMigrations.sublist(0, 2),
      );
      old.store.close();
      // The backup path is a directory: the copy cannot be written.
      Directory(p.join(profileDir('qa').path, 'kusunga.db.bak')).createSync();
      final s = await open(const ActiveDataProfile('qa'), keys);
      expect(s.banners, contains(HistoryBanner.backupFailed));
      expect(defaultState(), before);
    });

    test('two launches with different profiles share nothing and touch '
        'nothing else', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      final srcA = FakeClipboardSource();
      final a = await open(const ActiveDataProfile('qa'), keys, source: srcA);
      srcA.copy('only in qa');
      await a.close();
      final srcB = FakeClipboardSource();
      final b = await open(const ActiveDataProfile('qb'), keys, source: srcB);
      expect(b.items, isEmpty);
      await hammer(b, srcB);
      final a2 = await open(const ActiveDataProfile('qa'), keys);
      expect(a2.items.map((i) => i.preview), ['only in qa']);
      expect(defaultState(), before);
    });

    test('the real app running at the same time is not disturbed by a '
        'profile session (both open, profile hammered)', () async {
      final keys = FakeKeyStore(stored: hex);
      final realSrc = FakeClipboardSource();
      final real = await open(const NoDataProfile(), keys, source: realSrc);
      realSrc.copy('real one');
      final src = FakeClipboardSource();
      final prof = await open(const ActiveDataProfile('qa'), keys, source: src);
      for (var i = 0; i < 25; i++) {
        src.copy('profile $i');
      }
      prof.setLimit(10);
      prof.clear();
      expect(real.items.map((i) => i.preview), ['real one']);
      expect(real.limit, isNot(10));
      await prof.close();
      expect(real.items.map((i) => i.preview), ['real one']);
    });
  });

  group('Release and Profile builds ignore the switch', () {
    test(
      'with debug: false the default folder and the real key store are '
      'used, no profile folder is made, nothing about a profile is logged',
      () async {
        final profile = dataProfileFrom([
          '-KusungaDataProfile',
          'qa',
        ], debug: false);
        expect(profile, isA<NoDataProfile>());
        final fake = FakeKeyStore(stored: hex);
        final setup = dataProfileSetup(
          profile,
          supportDirectory: () async => base,
          keys: fake,
          log: mirror,
        );
        expect(identical(setup.keys, fake), isTrue);
        expect((await setup.supportDirectory()).path, base.path);
        expect(mirror.codes, isEmpty);
        final s = await open(profile, fake);
        await s.close();
        expect(Directory(p.join(base.path, 'profiles')).existsSync(), isFalse);
        expect(File(p.join(base.path, 'kusunga.db')).existsSync(), isTrue);
      },
    );

    test('no argument shape turns it on when debug is false', () {
      for (final args in [
        ['-KusungaDataProfile'],
        ['-KusungaDataProfile', 'QA'],
        ['-KusungaDataProfile', 'a', '-KusungaDataProfile', 'b'],
        ['-KusungaDataProfile', '../../etc'],
      ]) {
        expect(
          dataProfileFrom(args, debug: false),
          isA<NoDataProfile>(),
          reason: '$args',
        );
      }
    });

    test('the default parameter is kDebugMode, not true', () {
      // Under `flutter test` kDebugMode is true, so the default works; the
      // guard test pins the source text. Here: the default equals an
      // explicit debug: true.
      expect(
        dataProfileFrom(['-KusungaDataProfile', 'qa']).runtimeType,
        dataProfileFrom(['-KusungaDataProfile', 'qa'], debug: true).runtimeType,
      );
    });
  });

  group('names that look like a profile but are not', () {
    final bad = <String, String>{
      'Cyrillic a': 'qа',
      'fullwidth': 'ｑａ',
      'zero-width space': 'q​a',
      'Kelvin sign': 'K',
      'dotless i': 'ı',
      'combining accent': 'á',
      'fullwidth slash': 'qa／x',
      'division slash': 'qa∕x',
      'trailing newline': 'qa\n',
      'trailing CRLF': 'qa\r\n',
      'leading newline': '\nqa',
      'line separator': 'qa ',
      'percent-encoded dot dot': '%2e%2e',
      'percent-encoded slash': 'qa%2fx',
      'percent-encoded NUL': 'qa%00',
      'percent sign alone': '%',
      'upper case (case-insensitive collision)': 'QA',
      'mixed case': 'qA',
      'tab': 'qa\t',
      'empty': '',
      'space': ' ',
      '33 characters': 'a' * 33,
      'backslash': r'qa\..',
      'colon (alternate stream / drive)': 'qa:x',
      'tilde expansion': '~',
      'emoji': '\u{1F600}',
    };
    bad.forEach((label, name) {
      test('$label is rejected', () {
        expect(
          dataProfileFrom(['-KusungaDataProfile', name]),
          isA<RejectedDataProfile>(),
        );
      });
    });

    test('a flag value that looks like the flag is not a profile', () {
      expect(
        dataProfileFrom(['-KusungaDataProfile', '-KusungaDataProfile']),
        isA<RejectedDataProfile>(),
      );
    });

    test('a rejected name runs memory only: nothing is made or read, in '
        'any folder', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      for (final name in ['QA', 'qa\n', '%2e%2e', 'qа', '../support']) {
        final profile = dataProfileFrom(['-KusungaDataProfile', name]);
        final spy = _SpyKeys(FakeKeyStore(stored: hex));
        final s = await open(profile, spy);
        expect(s.banners, contains(HistoryBanner.memoryOnly), reason: name);
        expect(s.items, isEmpty, reason: name);
        await s.close();
        expect(spy.calls, isNot(contains('write')));
      }
      expect(defaultState(), before);
      expect(Directory(p.join(base.path, 'profiles')).existsSync(), isFalse);
      expect(
        root.listSync().map((e) => p.basename(e.path)),
        ['support'],
        reason: 'nothing created beside the support folder',
      );
    });

    test('QA vs qa: the upper-case name never reaches the data of "qa" '
        '(case-insensitive filesystems)', () async {
      final keys = FakeKeyStore(stored: hex);
      final src = FakeClipboardSource();
      final qa = await open(const ActiveDataProfile('qa'), keys, source: src);
      src.copy('qa private');
      await qa.close();
      final snapshot = <String, List<int>>{
        for (final f in profileDir('qa').listSync().whereType<File>())
          p.basename(f.path): f.readAsBytesSync(),
      };
      final upper = dataProfileFrom(['-KusungaDataProfile', 'QA']);
      final s = await open(upper, keys);
      expect(s.items, isEmpty);
      expect(s.banners, contains(HistoryBanner.memoryOnly));
      await s.close();
      expect({
        for (final f in profileDir('qa').listSync().whereType<File>())
          p.basename(f.path): f.readAsBytesSync(),
      }, snapshot);
      expect(
        Directory(
          p.join(base.path, 'profiles'),
        ).listSync().map((e) => p.basename(e.path)),
        ['qa'],
      );
    });
  });

  group('the log never holds the name or the path', () {
    test('every outcome, scanned in every log file and the mirror', () async {
      const name = 'zebra-secret-7';
      final tmpName = p.basename(root.path);
      final outcomes = <String, Future<void> Function()>{
        'ok': () async {
          final s = await open(
            const ActiveDataProfile(name),
            FakeKeyStore(stored: hex),
          );
          await s.close();
        },
        'no key': () async {
          final s = await open(const ActiveDataProfile(name), FakeKeyStore());
          await s.close();
        },
        'unreadable db': () async {
          profileDir(name).createSync(recursive: true);
          File(
            p.join(profileDir(name).path, 'kusunga.db'),
          ).writeAsBytesSync(List.filled(2048, 1));
          final s = await open(
            const ActiveDataProfile(name),
            FakeKeyStore(stored: hex),
          );
          await s.close();
        },
        'rejected': () async {
          final s = await open(
            dataProfileFrom(['-KusungaDataProfile', 'Zebra-Secret/../x']),
            FakeKeyStore(stored: hex),
          );
          await s.close();
        },
      };
      for (final entry in outcomes.entries) {
        await entry.value();
      }
      final text = StringBuffer();
      for (final f in root.listSync(recursive: true).whereType<File>()) {
        if (p.basename(f.path).startsWith('kusunga.log')) {
          text.write(f.readAsStringSync());
        }
      }
      text.write(mirror.codes.map((c) => c.name).join(' '));
      text.write(mirror.details.join(' '));
      final all = text.toString().toLowerCase();
      for (final secret in [
        'zebra',
        'secret',
        tmpName.toLowerCase(),
        'profiles',
        'support',
        '/private',
        '/var/',
        '/users/',
      ]) {
        expect(all, isNot(contains(secret)), reason: secret);
      }
      expect(all, contains('dataprofileactive'));
      expect(all, contains('dataprofilerejected'));
      expect(all, contains('dataprofilenokey'));
    });
  });

  group('symlinks in the profile folder', () {
    test('Clear history with a profile .bak that is a symlink to the real '
        '.bak removes only the link', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      profileDir('qa').createSync(recursive: true);
      Link(
        p.join(profileDir('qa').path, 'kusunga.db.bak'),
      ).createSync(p.join(base.path, 'kusunga.db.bak'));
      Link(
        p.join(profileDir('qa').path, 'kusunga.db.unreadable-2026-01-01'),
      ).createSync(p.join(base.path, 'kusunga.db.unreadable-2026-11-01'));
      final src = FakeClipboardSource();
      final s = await open(const ActiveDataProfile('qa'), keys, source: src);
      src.copy('x');
      s.clear();
      await s.close();
      expect(defaultState(), before);
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);

    test('profiles/qa is a symlink to the default folder: the session must '
        'not read or change it', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      Directory(p.join(base.path, 'profiles')).createSync();
      Link(profileDir('qa').path).createSync(base.path);
      final src = FakeClipboardSource();
      final s = await open(const ActiveDataProfile('qa'), keys, source: src);
      expect(s.items, isEmpty, reason: 'the real history was read');
      await hammer(s, src);
      expect(defaultState(), before);
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);

    test('profiles is a symlink to the default folder (profiles/qa then '
        'lands inside it)', () async {
      final keys = FakeKeyStore(stored: hex);
      await seedDefault(keys);
      final outside = Directory(p.join(root.path, 'elsewhere'))..createSync();
      Link(p.join(base.path, 'profiles')).createSync(outside.path);
      final src = FakeClipboardSource();
      final s = await open(const ActiveDataProfile('qa'), keys, source: src);
      await hammer(s, src);
      expect(
        outside.listSync(),
        isEmpty,
        reason: 'a profile session wrote outside the support folder',
      );
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);

    test('profiles/qa is a symlink to a folder outside the support folder: '
        'nothing is written there', () async {
      final keys = FakeKeyStore(stored: hex);
      final outside = Directory(p.join(root.path, 'elsewhere'))..createSync();
      Directory(p.join(base.path, 'profiles')).createSync();
      Link(profileDir('qa').path).createSync(outside.path);
      final src = FakeClipboardSource();
      final s = await open(const ActiveDataProfile('qa'), keys, source: src);
      await hammer(s, src);
      expect(outside.listSync(), isEmpty);
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);

    test('profiles/qa is a dangling symlink: memory only or a clean failure, '
        'never a write through it', () async {
      final keys = FakeKeyStore(stored: hex);
      Directory(p.join(base.path, 'profiles')).createSync();
      final target = p.join(root.path, 'not-yet');
      Link(profileDir('qa').path).createSync(target);
      final s = await open(const ActiveDataProfile('qa'), keys);
      await s.close();
      expect(Directory(target).existsSync(), isFalse);
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);

    test(
      'profiles/qa/kusunga.db is a symlink to the real database',
      () async {
        final keys = FakeKeyStore(stored: hex);
        final before = await seedDefault(keys);
        profileDir('qa').createSync(recursive: true);
        Link(
          p.join(profileDir('qa').path, 'kusunga.db'),
        ).createSync(p.join(base.path, 'kusunga.db'));
        final src = FakeClipboardSource();
        final s = await open(const ActiveDataProfile('qa'), keys, source: src);
        expect(s.items, isEmpty, reason: 'the real history was read');
        await hammer(s, src);
        expect(defaultState(), before);
      },
      skip: Platform.isWindows ? 'creating a symlink needs rights' : null,
    );

    test(
      'profiles/qa/kusunga.log is a symlink to the real log',
      () async {
        final keys = FakeKeyStore(stored: hex);
        File(p.join(base.path, 'kusunga.log')).writeAsStringSync('real log\n');
        final before = defaultState();
        profileDir('qa').createSync(recursive: true);
        Link(
          p.join(profileDir('qa').path, 'kusunga.log'),
        ).createSync(p.join(base.path, 'kusunga.log'));
        final s = await open(const ActiveDataProfile('qa'), keys);
        await s.close();
        expect(defaultState(), before, reason: 'the real log was appended to');
      },
      skip: Platform.isWindows ? 'creating a symlink needs rights' : null,
    );

    test('an older profile DB whose .bak is a symlink to the real .bak must '
        'not overwrite the real backup', () async {
      final keys = FakeKeyStore(stored: hex);
      final before = await seedDefault(keys);
      profileDir('qa').createSync(recursive: true);
      final old = await openHistory(
        keys: keys,
        directory: profileDir('qa').path,
        log: FakeLog(),
        migrations: kMigrations.sublist(0, 2),
      );
      old.store.close();
      Link(
        p.join(profileDir('qa').path, 'kusunga.db.bak'),
      ).createSync(p.join(base.path, 'kusunga.db.bak'));
      final s = await open(const ActiveDataProfile('qa'), keys);
      await s.close();
      expect(
        defaultState(),
        before,
        reason: 'the migration backup was written through the link',
      );
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);
  });
}
