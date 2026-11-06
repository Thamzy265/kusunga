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

    /// The arguments for a test name: invisible and non-ASCII characters as
    /// U+XXXX, at most 80 characters.
    String shown(List<String> args) {
      final text = args
          .map(
            (a) => a.runes
                .map(
                  (r) => r > 126 || r < 32
                      ? 'U+${r.toRadixString(16).toUpperCase()}'
                      : String.fromCharCode(r),
                )
                .join(),
          )
          .join(' ');
      return text.length > 80 ? '${text.substring(0, 80)}...' : text;
    }

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

    for (final args in [
      ['-KusungaDataProfile=qa'],
      ['--KusungaDataProfile', 'qa'],
      ['--KusungaDataProfile=qa'],
      ['-KusungaDataProfileqa'],
      ['-kusungadataprofile', 'qa'],
      ['-KusungaDataProfile', 'qa', '--KusungaDataProfile=qb'],
    ]) {
      test('a mistyped switch ${args.join(' ')} is rejected (memory only), '
          'never the default folder', () {
        expect(parse(args), isA<RejectedDataProfile>());
        expect(parse(args, debug: false), isA<NoDataProfile>());
      });
    }

    // Reviewer P1: a misspelled switch, or one whose dash autocorrect turned
    // into an en or em dash, must never mean the real folder.
    for (final args in [
      ['-KusungaDataProfil', 'qa'],
      ['-KusungaProfile', 'qa'],
      ['-kusunga-data-profile', 'qa'],
      ['\u2013KusungaDataProfile', 'qa'],
      ['\u2014KusungaDataProfile', 'qa'],
      ['/KusungaDataProfile', 'qa'],
      ['-KUSUNGADATAPROFILE', 'qa'],
      ['-kUsUnGaDaTaPrOfIlE', 'qa'],
      ['-ProfileKusunga', 'qa'],
      ['--kusunga_profile=qa'],
      ['-KusungaDataProfile', 'qa', '\u2013KusungaDataProfile', 'qa'],
    ]) {
      test('a misspelled switch ${args.join(' ')} is rejected, with detail '
          '$dataProfileMisspeltDetail, never the default folder', () {
        final profile = parse(args);
        expect(profile, isA<RejectedDataProfile>());
        expect(
          (profile as RejectedDataProfile).detail,
          dataProfileMisspeltDetail,
        );
        expect(parse(args, debug: false), isA<NoDataProfile>());
      });
    }

    // BUG-Q1 (PM decision 2026-11-06, "Common slips + label check"): typos
    // within a few letters, a forgotten dash, any dash or minus character,
    // spaces and quotes around it, the switch split across two arguments.
    for (final args in [
      ['-KusungaDataProfle', 'qa'],
      ['-KusungaDataPofile', 'qa'],
      ['-KusungDataProfile', 'qa'],
      ['-KusunagDataProfile', 'qa'],
      ['-KusunngaDataProfile', 'qa'],
      ['-KsungaDtaProfle', 'qa'], // three letters dropped
      ['-KusungaDataProfiel=qa'],
      ['KusungaDataProfile', 'qa'],
      ['KusungaDataProfle', 'qa'], // no dash and a typo
      ['kusunga-data-profile', 'qa'],
      ['KusungaDataProfile:qa'],
      ['KusungaDataProfile qa'], // one argument with a space inside
      ['KusungaDataProfile=test-profile'],
      ['\u2212KusungaDataProfile', 'qa'],
      ['\u2212KusungaDataProfle', 'qa'],
      ['\uFF0D\uFF0DKusungaDataProfile', 'qa'],
      ['\u2010KusungaDataProfile', 'qa'],
      ['\u2015kusungadataprofile', 'qa'],
      ['/kusungadataprofle', 'qa'],
      ['-KusungaDataProfile\u00a0', 'qa'],
      ['KusungaDataProfile ', 'qa'],
      ['\u201c-KusungaDataProfile\u201d', 'qa'], // curly double quotes
      ['\u2018-KusungaDataProfile\u2019', 'qa'], // curly single quotes
      ['\u201c\u2013KusungaDataProfile\u201d', 'qa'],
      ['"KusungaDataProfile"', 'qa'],
      [' \t-KusungaDataProfile\r\n', 'qa'],
      ['- KusungaDataProfile', 'qa'],
      ['-Kusunga', 'DataProfile', 'qa'],
      ['-KusungaData', 'Profile', 'qa'],
      ['-Kusunga', '-DataProfile', 'qa'],
      ['\u2013Kusunga', 'DataProfle', 'qa'],
      ['-KusungaDataPro', 'file', 'qa'],
      ['-other', '-Kusunga', 'DataProfile', 'qa'],
      ['-KusungaDataProfile', 'qa', 'KusungaDataProfile'],
    ]) {
      test('a common slip [${shown(args)}] is rejected with detail '
          '$dataProfileMisspeltDetail; Release ignores it', () {
        final profile = parse(args);
        expect(profile, isA<RejectedDataProfile>());
        expect(
          (profile as RejectedDataProfile).detail,
          dataProfileMisspeltDetail,
        );
        expect(parse(args, debug: false), isA<NoDataProfile>());
      });
    }

    test(
      'a common slip logs dataProfileRejected 3 and opens nothing',
      () async {
        for (final args in [
          ['KusungaDataProfile', 'qa'],
          ['-KusungaDataProfle', 'qa'],
          ['\u2212KusungaDataProfile', 'qa'],
          [' -KusungaDataProfile', 'qa'],
          ['-Kusunga', 'DataProfile', 'qa'],
        ]) {
          final log = FakeLog();
          final setup = dataProfileSetup(
            parse(args),
            supportDirectory: () async => Directory.systemTemp,
            keys: FakeKeyStore(),
            log: log,
          );
          expect(log.codes, [LogCode.dataProfileRejected], reason: '$args');
          expect(log.details, [dataProfileMisspeltDetail], reason: '$args');
          await expectLater(setup.supportDirectory(), throwsA(anything));
        }
      },
    );

    // The split-switch check never pairs the exact switch with a neighbour:
    // "YES" + "-KusungaDataProfile" is only three letters from the switch.
    for (final args in [
      ['YES', '-KusungaDataProfile', 'qa'],
      ['-a', '-KusungaDataProfile', 'qa'],
      ['k', '-KusungaDataProfile', 'qa'],
      ['-KusungaForcePost', 'YES', '-KusungaDataProfile', 'qa'],
      ['-KusungaDataProfile', 'qa', '-KusungaForcePost', 'YES'],
      ['-KusungaDataProfile', 'qa', 'extra'],
    ]) {
      test('the exact switch beside ${args.join(' ')} is still the profile '
          '"qa"', () {
        final profile = parse(args);
        expect(profile, isA<ActiveDataProfile>());
        expect((profile as ActiveDataProfile).name, 'qa');
      });
    }

    for (final args in [
      ['-KusungaForcePost', 'YES'],
      ['-KusungaForcePost', 'NO', '-AppleLanguages', '(en)'],
      ['kusunga', 'profile'],
      ['-KusungaDataPath', '/tmp/x'],
      ['--observatory-port=0', '--disable-service-auth-codes'],
      ['-NSDocumentRevisionsDebugMode', 'YES', '-ApplePersistenceIgnoreState'],
      ['/Users/qa/Developer/kusunga/build/macos/Build/Products/Debug'],
      [r'C:\Users\qa\AppData\Roaming\Kusunga\kusunga.exe'],
      ['-x', 'x' * 100000],
    ]) {
      test('unrelated arguments [${shown(args)}] mean no profile', () {
        expect(parse(args), isA<NoDataProfile>());
      });
    }

    test('a very long argument is judged in bounded time', () {
      final watch = Stopwatch()..start();
      expect(
        parse(['-KusungaDataProfile=${'q' * 1000000}']),
        isA<RejectedDataProfile>(),
      );
      expect(
        parse(['KusungaDataProfle${'q' * 1000000}']),
        isA<RejectedDataProfile>(),
      );
      expect(
        parse(['--flutter-assets-dir=${'a/' * 500000}', 'q' * 1000000]),
        isA<NoDataProfile>(),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    for (final args in [
      ['-NSDocumentRevisionsDebugMode', 'YES'],
      ['--enable-dart-profiling', '--observatory-port=0'],
      ['--dart-define=FLUTTER_WEB_USE_SKIA=true', '-AppleLanguages', '(en)'],
      ['/Users/qa/Kusunga.app'],
      ['-psn_0_12345'],
    ]) {
      test('unrelated arguments ${args.join(' ')} mean no profile', () {
        expect(parse(args), isA<NoDataProfile>());
      });
    }

    test('the exact switch still works next to unrelated arguments', () {
      final profile = parse([
        '-NSDocumentRevisionsDebugMode',
        'YES',
        '-KusungaDataProfile',
        'qa',
      ]);
      expect(profile, isA<ActiveDataProfile>());
      expect((profile as ActiveDataProfile).name, 'qa');
    });

    test('a misspelled switch logs dataProfileRejected with its detail and '
        'opens nothing', () async {
      final log = FakeLog();
      final setup = dataProfileSetup(
        parse(['\u2013KusungaDataProfile', 'qa']),
        supportDirectory: () async => Directory.systemTemp,
        keys: FakeKeyStore(),
        log: log,
      );
      expect(log.codes, [LogCode.dataProfileRejected]);
      expect(log.details, [dataProfileMisspeltDetail]);
      await expectLater(setup.supportDirectory(), throwsA(anything));
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

    test('a symlink at profiles/ or profiles/<name> is refused: memory '
        'only, dataProfileRejected 2, and no file anywhere (BUG-P1)', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(8)));
      final before = await seedDefault(keys);
      final outside = Directory.systemTemp.createTempSync('kusunga_out_');
      addTearDown(() => outside.deleteSync(recursive: true));
      for (final linkAt in ['profiles', 'profiles/qa']) {
        log.codes.clear();
        log.details.clear();
        final link = Link(p.join(base.path, linkAt));
        if (linkAt == 'profiles/qa') {
          Directory(p.join(base.path, 'profiles')).createSync();
        }
        link.createSync(outside.path);
        final service = await open(const ActiveDataProfile('qa'), keys);
        expect(service.banners, contains(HistoryBanner.memoryOnly));
        expect(service.items, isEmpty);
        final at = log.codes.indexOf(LogCode.dataProfileRejected);
        expect(at, isNonNegative, reason: linkAt);
        expect(log.details[at], 2, reason: linkAt);
        expect(outside.listSync(), isEmpty, reason: linkAt);
        expect(defaultFiles(), before, reason: linkAt);
        link.deleteSync();
        if (linkAt == 'profiles/qa') {
          Directory(p.join(base.path, 'profiles')).deleteSync();
        }
      }
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);

    test('a symlinked file in the profile folder is refused before anything '
        'is opened, written or backed up (BUG-P2)', () async {
      final keys = FakeKeyStore(stored: generateKeyHex(Random(9)));
      final before = await seedDefault(keys);
      final dir = Directory(p.join(base.path, 'profiles', 'qa'))
        ..createSync(recursive: true);
      for (final file in [
        'kusunga.db',
        'kusunga.db-wal',
        'kusunga.log',
        'kusunga.db.bak',
        'kusunga.db.unreadable-2026-11-01',
      ]) {
        log.codes.clear();
        log.details.clear();
        final link = Link(p.join(dir.path, file))
          ..createSync(p.join(base.path, 'kusunga.db.bak'));
        final service = await open(const ActiveDataProfile('qa'), keys);
        expect(
          service.banners,
          contains(HistoryBanner.memoryOnly),
          reason: file,
        );
        final at = log.codes.indexOf(LogCode.dataProfileRejected);
        expect(at, isNonNegative, reason: file);
        expect(log.details[at], 2, reason: file);
        expect(dir.listSync().map((e) => p.basename(e.path)), [file]);
        expect(defaultFiles(), before, reason: file);
        await service.close();
        link.deleteSync();
      }
    }, skip: Platform.isWindows ? 'creating a symlink needs rights' : null);

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
