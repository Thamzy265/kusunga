import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/data_profile.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/open_app_history.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

/// The debug-only test data profile (PM decision 2026-11-05, "Add a test
/// profile"): `-KusungaDataProfile <name>` keeps every file in
/// `<support>/profiles/<name>/` and never touches the default folder.
void main() {
  group('the launch switch', () {
    DataProfile parse(List<String> args, {bool debug = true}) =>
        dataProfileFrom(args, debug: debug);

    test('no switch: the default folder', () {
      expect(parse([]), isA<NoDataProfile>());
      expect(parse(['--other', 'qa']), isA<NoDataProfile>());
    });

    for (final name in ['qa', 'a', '7', 'qa-2', 'test-profile', 'a' * 32]) {
      test('"$name" is a profile name', () {
        final profile = parse(['-KusungaDataProfile', name]);
        expect(profile, isA<ActiveDataProfile>());
        expect((profile as ActiveDataProfile).name, name);
      });
    }

    for (final name in [
      '',
      'QA',
      'Qa',
      '..',
      '.',
      '../qa',
      'qa/..',
      '/qa',
      'qa/x',
      r'qa\x',
      r'..\qa',
      'qa x',
      ' qa',
      'qa\n',
      'qa\u0000',
      'qa.db',
      'qä',
      'q_a',
      '~',
      'a' * 33,
    ]) {
      test('"${name.replaceAll('\n', r'\n').replaceAll('\u0000', r'\0')}" '
          'is rejected', () {
        expect(
          parse(['-KusungaDataProfile', name]),
          isA<RejectedDataProfile>(),
        );
      });
    }

    test('a switch with no name, or given twice, is rejected', () {
      expect(parse(['-KusungaDataProfile']), isA<RejectedDataProfile>());
      expect(
        parse(['-KusungaDataProfile', 'qa', '-KusungaDataProfile', 'qb']),
        isA<RejectedDataProfile>(),
      );
    });

    test('Release (and Profile) builds ignore it: the default folder', () {
      expect(
        parse(['-KusungaDataProfile', 'qa'], debug: false),
        isA<NoDataProfile>(),
      );
      expect(
        parse(['-KusungaDataProfile', '../x'], debug: false),
        isA<NoDataProfile>(),
      );
    });
  });

  group('the data folder', () {
    late Directory base;
    late FakeLog log;
    final services = <HistoryService>[];

    setUp(() {
      base = Directory.systemTemp.createTempSync('kusunga_profile_');
      log = FakeLog();
    });
    tearDown(() async {
      for (final s in services) {
        await s.close();
        s.dispose();
      }
      services.clear();
      base.deleteSync(recursive: true);
    });

    /// Every file under the default folder, outside `profiles/`, with its
    /// bytes.
    Map<String, List<int>> defaultFiles() => {
      for (final f in base.listSync(recursive: true).whereType<File>())
        if (!p
            .relative(f.path, from: base.path)
            .startsWith('profiles${Platform.pathSeparator}'))
          p.relative(f.path, from: base.path): f.readAsBytesSync(),
    };

    List<String> profileFiles(String name) {
      final dir = Directory(p.join(base.path, 'profiles', name));
      if (!dir.existsSync()) return [];
      return dir.listSync().map((e) => p.basename(e.path)).toList()..sort();
    }

    Future<HistoryService> open(
      DataProfile profile,
      FakeKeyStore keys, {
      FakeClipboardSource? source,
    }) async {
      final deferred = DeferredErrorLog(mirror: log);
      final setup = dataProfileSetup(
        profile,
        supportDirectory: () async => base,
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

    /// The PM's real data: a database with history in it, a migration
    /// backup, a file moved aside as unreadable, and the log.
    Future<Map<String, List<int>>> seedDefault(FakeKeyStore keys) async {
      final source = FakeClipboardSource();
      final real = await open(const NoDataProfile(), keys, source: source);
      for (var i = 0; i < 30; i++) {
        source.copy('real item $i');
      }
      await real.close();
      File(p.join(base.path, 'kusunga.db.bak')).writeAsStringSync('backup');
      File(
        p.join(base.path, 'kusunga.db.unreadable-2026-11-01'),
      ).writeAsStringSync('old');
      File(
        p.join(base.path, 'kusunga.log'),
      ).writeAsStringSync('2026-11-05T00:00:00.000Z flushFailed\n');
      final files = defaultFiles();
      expect(
        files.keys,
        containsAll([
          'kusunga.db',
          'kusunga.db.bak',
          'kusunga.db.unreadable-2026-11-01',
          'kusunga.log',
        ]),
      );
      return files;
    }

    test('the profile uses <support>/profiles/<name>/ for its database, '
        'log and settings', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(1)));
      final source = FakeClipboardSource();
      final service = await open(
        const ActiveDataProfile('qa'),
        keys,
        source: source,
      );
      expect(service.banners, isEmpty);
      source.copy('profile item');
      expect(service.saveSetting('paste_mode', 'copy_only'), isTrue);
      await service.close();
      expect(profileFiles('qa'), containsAll(['kusunga.db', 'kusunga.log']));
      final again = await open(const ActiveDataProfile('qa'), keys);
      expect(again.items.map((i) => i.preview), ['profile item']);
      expect(again.setting('paste_mode'), 'copy_only');
      expect(defaultFiles(), isEmpty, reason: 'nothing in the default folder');
    });

    test('limit, trim, move-aside and Clear history in the profile never '
        'touch the default folder', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(2)));
      final before = await seedDefault(keys);

      // An unreadable profile database is moved aside in the profile only.
      Directory(
        p.join(base.path, 'profiles', 'qa'),
      ).createSync(recursive: true);
      File(
        p.join(base.path, 'profiles', 'qa', 'kusunga.db'),
      ).writeAsStringSync('not a database');
      final source = FakeClipboardSource();
      final service = await open(
        const ActiveDataProfile('qa'),
        keys,
        source: source,
      );
      expect(service.banners, contains(HistoryBanner.readError));
      expect(
        profileFiles('qa').where((f) => f.startsWith('kusunga.db.unreadable-')),
        hasLength(1),
      );
      expect(service.items, isEmpty, reason: 'the real history is not read');

      for (var i = 0; i < 25; i++) {
        source.copy('profile item $i');
      }
      expect(service.setLimit(10), isTrue);
      expect(service.items, hasLength(10));
      expect(service.clear(), 10);
      expect(service.items, isEmpty);
      await service.close();

      // Clear history removed the profile's own old copies only.
      expect(
        profileFiles('qa').where((f) => f.startsWith('kusunga.db.unreadable-')),
        isEmpty,
      );
      expect(defaultFiles(), before, reason: 'the default folder unchanged');

      // And the real history is still all there.
      final real = await open(const NoDataProfile(), keys);
      expect(real.items, hasLength(30));
      expect(real.limit, isNot(10));
    });

    test('two profiles do not share data', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(3)));
      final source = FakeClipboardSource();
      final a = await open(const ActiveDataProfile('qa'), keys, source: source);
      source.copy('in qa');
      await a.close();
      final b = await open(const ActiveDataProfile('qb'), keys);
      expect(b.items, isEmpty);
    });

    test('the profile reuses the key and never writes one: no new keychain '
        'item, so no new prompt', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(4)));
      final service = await open(const ActiveDataProfile('qa'), keys);
      expect(service.banners, isEmpty);
      expect(keys.writes, 0);
    });

    test('with no key yet, the profile is memory only and writes no key '
        '(a new key would make the real history unreadable)', () async {
      final keys = FakeKeyStore();
      final service = await open(const ActiveDataProfile('qa'), keys);
      expect(service.banners, contains(HistoryBanner.memoryOnly));
      expect(keys.writes, 0);
      expect(keys.stored, isNull);
      expect(log.codes, contains(LogCode.dataProfileNoKey));
      expect(defaultFiles(), isEmpty);
    });

    test(
      'a rejected name: memory only, nothing read or written anywhere',
      () async {
        final keys = FakeKeyStore(stored: generateKeyHex(Random(5)));
        final before = await seedDefault(keys);
        final service = await open(const RejectedDataProfile(), keys);
        expect(service.banners, contains(HistoryBanner.memoryOnly));
        expect(service.items, isEmpty);
        expect(log.codes, contains(LogCode.dataProfileRejected));
        expect(defaultFiles(), before);
        expect(Directory(p.join(base.path, 'profiles')).existsSync(), isFalse);
      },
    );

    test('the start is logged as a closed code, never with the name or the '
        'path', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(6)));
      final service = await open(const ActiveDataProfile('zebra-7'), keys);
      await service.close();
      expect(log.codes, contains(LogCode.dataProfileActive));
      final text = File(
        p.join(base.path, 'profiles', 'zebra-7', 'kusunga.log'),
      ).readAsStringSync();
      expect(text, contains('dataProfileActive'));
      expect(text, isNot(contains('zebra')));
      expect(text, isNot(contains('profiles')));
    });

    test('without a profile nothing is logged about one', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(7)));
      await open(const NoDataProfile(), keys);
      expect(log.codes.where((c) => c.name.startsWith('dataProfile')), isEmpty);
    });
  });
}
