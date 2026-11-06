// Tester round 6 on 21c17b4 (reviewer P1: a misspelled -KusungaDataProfile
// switch must never open the real data folder). The rule: an argument that
// starts with "-", an en dash, an em dash or "/", holds "kusunga" and
// "profil" in any case, and is not exactly "-KusungaDataProfile", is
// rejected (memory only, dataProfileRejected detail 3).
//
// The tests marked BUG-Q* are realistic slips that still get the real
// folder today. They are skipped repros (each fails when unskipped).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/data_profile.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/history/open_app_history.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  DataProfile parse(List<String> a) => dataProfileFrom(a, debug: true);

  bool rejected(List<String> a) => parse(a) is RejectedDataProfile;

  int? detailOf(List<String> a) => (parse(a) as RejectedDataProfile).detail;

  group('what the rule rejects, with detail 3', () {
    for (final arg in [
      '-KusungaDataProfil',
      '-KusungaDataProfileX',
      '-KusungaDataProfile=qa',
      '-KusungaDataProfile:qa',
      '-KusungaDataProfile=',
      '-kusungadataprofile',
      '-KUSUNGADATAPROFILE',
      '--KusungaDataProfile',
      '---KusungaDataProfile',
      '\u2013KusungaDataProfile', // en dash (autocorrect)
      '\u2014KusungaDataProfile', // em dash (autocorrect)
      '\u2013kusungadataprofil',
      '/KusungaDataProfile',
      '/KusungaDataProfile=qa',
      '-Kusunga-Profile',
      '-KusungaProfile',
      '-Kusunga_Test_Profile',
      '-KusungaProfiles',
      '-profile-of-kusunga',
      '-Kusunga\u200bDataProfile', // zero-width space between words
      '-KusungaData\u200bProfile',
      '-KusungaDataProfile\n',
      '-KusungaDataProfile ',
    ]) {
      test('${arg.replaceAll('\n', r'\n')} (alone, and before a name)', () {
        expect(detailOf([arg]), dataProfileMisspeltDetail);
        expect(detailOf([arg, 'qa']), dataProfileMisspeltDetail);
        expect(
          detailOf(['-other', arg, 'qa', '-last']),
          dataProfileMisspeltDetail,
        );
      });
    }

    test('the exact switch with a good name is still the profile', () {
      final profile = parse(['-KusungaDataProfile', 'qa']);
      expect(profile, isA<ActiveDataProfile>());
      expect((profile as ActiveDataProfile).name, 'qa');
    });
  });

  group('the order and the company of switches', () {
    test('exact then misspelled: rejected', () {
      expect(
        detailOf(['-KusungaDataProfile', 'qa', '-KusungaDataProfil']),
        dataProfileMisspeltDetail,
      );
      expect(
        detailOf(['-KusungaDataProfile', 'qa', '\u2013KusungaDataProfile']),
        dataProfileMisspeltDetail,
      );
    });
    test('misspelled then exact: rejected', () {
      expect(
        detailOf(['-KusungaDataProfil', '-KusungaDataProfile', 'qa']),
        dataProfileMisspeltDetail,
      );
      expect(
        detailOf(['/KusungaDataProfile', '-KusungaDataProfile', 'qa']),
        dataProfileMisspeltDetail,
      );
    });
    test('a valid name after a rejected switch is not used', () {
      final p1 = parse(['-KusungaDataProfil', 'qa']);
      expect(p1, isA<RejectedDataProfile>());
      expect(p1, isNot(isA<ActiveDataProfile>()));
      expect(
        parse(['\u2014KusungaDataProfile', 'qa']),
        isA<RejectedDataProfile>(),
      );
    });
    test('the exact switch given twice, or with an empty name, or none: '
        'rejected (no detail 3 needed)', () {
      expect(
        rejected(['-KusungaDataProfile', 'qa', '-KusungaDataProfile', 'qb']),
        isTrue,
      );
      expect(rejected(['-KusungaDataProfile', '']), isTrue);
      expect(rejected(['-KusungaDataProfile']), isTrue);
      expect(rejected(['-KusungaDataProfile', '-KusungaDataProfile']), isTrue);
      // A forgotten name followed by another switch: an upper-case switch is
      // not a name; a lower-case one such as --other is (a profile folder,
      // never the real data).
      expect(rejected(['-KusungaDataProfile', '-ApplePersistence']), isTrue);
      expect(
        parse(['-KusungaDataProfile', '--other']),
        isA<ActiveDataProfile>(),
      );
    });
    test('Release and Profile builds ignore every one of them', () {
      for (final a in [
        ['-KusungaDataProfil', 'qa'],
        ['\u2013KusungaDataProfile', 'qa'],
        ['-KusungaDataProfile', 'qa', '-KusungaDataProfil'],
        ['/KusungaDataProfile'],
      ]) {
        expect(
          dataProfileFrom(a, debug: false),
          isA<NoDataProfile>(),
          reason: '$a',
        );
      }
    });
  });

  group('unrelated launch arguments mean no profile (the real data)', () {
    // Shapes seen on a Mac (-psn, NSUserDefaults overrides, Xcode) and from
    // `flutter run` / the Flutter engine, and on Windows.
    for (final args in <List<String>>[
      [],
      ['-psn_0_123456'],
      ['-NSDocumentRevisionsDebugMode', 'YES'],
      ['-ApplePersistenceIgnoreState', 'YES'],
      ['-AppleLanguages', '(en)'],
      ['-AppleLocale', 'en_GB'],
      ['-NSQuitAlwaysKeepsWindows', 'NO'],
      ['-com.apple.CoreData.SQLDebug', '1'],
      ['-NSShowNonLocalizedStrings', 'YES'],
      ['--dart-define=FLUTTER_WEB_USE_SKIA=true'],
      ['--enable-dart-profiling'],
      ['--observatory-port=0', '--disable-service-auth-codes'],
      ['--vm-service-port=51234', '--enable-checked-mode'],
      ['--enable-software-rendering', '--use-test-fonts'],
      [
        '--flutter-assets-dir=/Users/qa/Developer/kusunga/build/macos/Build/'
            'Products/Debug/Kusunga.app/Contents/Frameworks/App.framework/'
            'Resources/flutter_assets',
      ],
      [
        r'--flutter-assets-dir=C:\dev\kusunga\build\windows\x64\runner\Debug\data',
      ],
      ['/ForceDesktop', '/NoSplash'],
      [r'C:\Program Files\Kusunga\kusunga.exe'],
      ['kusunga', 'profile'],
      ['profile', 'kusunga'],
      ['-kusunga'],
      ['-profile'],
      ['--profile'],
      ['--release'],
      ['-d', 'macos'],
    ]) {
      test(args.isEmpty ? 'no arguments' : args.join(' '), () {
        expect(parse(args), isA<NoDataProfile>());
      });
    }

    test('unrelated arguments beside a valid switch do not change it', () {
      final profile = parse([
        '-NSDocumentRevisionsDebugMode',
        'YES',
        '--vm-service-port=1',
        '-KusungaDataProfile',
        'qa',
        '-AppleLanguages',
        '(en)',
      ]);
      expect((profile as ActiveDataProfile).name, 'qa');
    });

    test('a path argument that holds both words is rejected: the safe '
        'direction (memory only), noted for QA', () {
      expect(rejected(['--dart-define=APP=kusunga-profile']), isTrue);
      expect(rejected(['/Users/qa/kusunga/profiles/x']), isTrue);
    });
  });

  group('a rejected switch reaches nothing real', () {
    late Directory base;
    late FakeLog mirror;
    final services = <HistoryService>[];

    setUp(() {
      base = Directory.systemTemp.createTempSync('kusunga_misspelt_');
      mirror = FakeLog();
    });
    tearDown(() async {
      for (final s in services) {
        await s.close();
        s.dispose();
      }
      services.clear();
      base.deleteSync(recursive: true);
    });

    Map<String, List<int>> state() => {
      for (final e in base.listSync(recursive: true).whereType<File>())
        p.relative(e.path, from: base.path): e.readAsBytesSync(),
    };

    for (final arg in [
      '-KusungaDataProfil',
      '\u2013KusungaDataProfile',
      '\u2014KusungaDataProfile',
      '/KusungaDataProfile',
      '-KusungaDataProfile=qa',
      '--KusungaDataProfile',
      '-kusungadataprofile',
    ]) {
      test('${arg.replaceAll('\n', r'\n')}: memory only, no folder lookup, '
          'no key call, no log file, the real folder byte for byte', () async {
        // The PM's real data first, opened as a normal launch.
        final keys = _SpyKeys(FakeKeyStore(stored: 'ab' * 32));
        final realLog = DeferredErrorLog(mirror: FakeLog());
        final src = FakeClipboardSource();
        final real = await openAppHistory(
          deferred: realLog,
          supportDirectory: () async => base,
          keys: keys,
          source: src,
        );
        for (var i = 0; i < 12; i++) {
          src.copy('real $i');
        }
        await real.close();
        real.dispose();
        File(p.join(base.path, 'kusunga.db.bak')).writeAsStringSync('bak');
        final before = state();
        final fresh = _SpyKeys(FakeKeyStore(stored: 'ab' * 32));
        var folderAsked = 0;

        final deferred = DeferredErrorLog(mirror: mirror);
        final setup = dataProfileSetup(
          parse([arg, 'qa']),
          supportDirectory: () async {
            folderAsked++;
            return base;
          },
          keys: fresh,
          log: deferred,
        );
        final service = await openAppHistory(
          deferred: deferred,
          supportDirectory: setup.supportDirectory,
          keys: setup.keys,
          source: FakeClipboardSource(),
        );
        services.add(service);

        expect(service.banners, contains(HistoryBanner.memoryOnly));
        expect(service.items, isEmpty, reason: 'the real history was read');
        expect(folderAsked, 0, reason: 'the real folder was looked up');
        expect(fresh.calls, isEmpty, reason: 'the keychain was touched');
        final i = mirror.codes.indexOf(LogCode.dataProfileRejected);
        expect(i, isNonNegative);
        expect(mirror.details[i], dataProfileMisspeltDetail);
        expect(mirror.codes, isNot(contains(LogCode.dataProfileActive)));
        service.saveSetting('paste_mode', 'copy_only');
        service.setLimit(10);
        service.clear();
        await service.close();
        expect(state(), before, reason: 'a file of the real folder changed');
        expect(
          base
              .listSync(recursive: true)
              .whereType<Directory>()
              .map((d) => p.basename(d.path)),
          isNot(contains('profiles')),
        );
      });
    }
  });

  // ---- Realistic slips that still open the real folder (skipped repros) --

  group('BUG-Q1: slips that are not recognised, so the real folder opens', () {
    void expectAllRejected(List<String> variants) {
      final escapes = [
        for (final v in variants)
          if (!rejected([v, 'qa']) && !rejected([v]))
            v.runes
                .map(
                  (r) => r > 126 || r < 33
                      ? 'U+${r.toRadixString(16).toUpperCase()}'
                      : String.fromCharCode(r),
                )
                .join(),
      ];
      expect(escapes, isEmpty, reason: 'these get the real folder: $escapes');
    }

    test(
      'a typo in the word (one letter dropped, doubled or swapped)',
      () {
        expectAllRejected([
          '-KusungaDataProfle',
          '-KusungaDataProfie',
          '-KusungaDataPofile',
          '-KusungaDataProile',
          '-KusungDataProfile',
          '-KusugaDataProfile',
          '-KusunagDataProfile',
          '-KusungaDataProfiel',
          '-KusungaDataProflie',
          '-KusungaDatarofile',
          '-KusunngaDataProfile',
        ]);
      },
      skip: 'BUG-Q1a: needs both "kusunga" and "profil" intact',
    );

    test(
      'part of the name left out',
      () {
        expectAllRejected([
          '-DataProfile',
          '-Profile',
          '-Kusunga',
          '-KusungaData',
        ]);
      },
      skip: 'BUG-Q1b: "-DataProfile", "-Kusunga" and the like are ignored',
    );

    test(
      'the dash forgotten',
      () {
        expectAllRejected([
          'KusungaDataProfile',
          'KusungaDataProfile=qa',
          'kusungadataprofile',
        ]);
      },
      skip: 'BUG-Q1c: no leading dash, so it is not looked at',
    );

    test(
      'a typographic dash or minus instead of "-"',
      () {
        expectAllRejected([
          '\u2212KusungaDataProfile', // minus sign
          '\u2010KusungaDataProfile', // hyphen
          '\u2011KusungaDataProfile', // non-breaking hyphen
          '\u2012KusungaDataProfile', // figure dash
          '\u2015KusungaDataProfile', // horizontal bar
          '\uFF0DKusungaDataProfile', // full-width hyphen-minus
          '\uFE63KusungaDataProfile', // small hyphen-minus
        ]);
      },
      skip: 'BUG-Q1d: only -, en dash, em dash and / are recognised',
    );

    test('a space, tab, newline or quote before the switch (pasted from a '
        'doc or a shell line)', () {
      expectAllRejected([
        ' -KusungaDataProfile',
        '\t-KusungaDataProfile',
        '\n-KusungaDataProfile',
        '\u00a0-KusungaDataProfile',
        '"-KusungaDataProfile"',
        "'-KusungaDataProfile'",
        '"-KusungaDataProfile',
      ]);
    }, skip: 'BUG-Q1e: the first character must be a dash or slash');

    test(
      'the switch split across arguments (a space typed inside it)',
      () {
        for (final args in [
          ['-Kusunga', 'DataProfile', 'qa'],
          ['-Kusunga', '-DataProfile', 'qa'],
          ['-KusungaData', 'Profile', 'qa'],
        ]) {
          expect(parse(args), isNot(isA<NoDataProfile>()), reason: '$args');
        }
      },
      skip: 'BUG-Q1f: each half alone is ignored',
    );
  });

  group('hardening, low realism (pasted text, look-alikes)', () {
    test('zero-width characters inside "Kusunga" or "Profile", Cyrillic or '
        'Turkish look-alikes, 1 or 0 for l or o', () {
      final escapes = [
        for (final v in [
          '-Kusu\u200bngaDataProfile',
          '-KusungaDataProfi\u200ble',
          '-KusungaDataPr\u043efile', // Cyrillic o
          '-Kusung\u0430DataProfile', // Cyrillic a
          '-KusungaDataProf\u0131le', // dotless i
          '-KusungaDataProf\u0130le', // dotted capital I
          '-KusungaDataProfi1e',
          '-KusungaDataPr0file',
          '-KusungaDataProfiIe',
        ])
          if (!rejected([v, 'qa'])) v,
      ];
      expect(
        escapes,
        isEmpty,
        reason: '${escapes.length} look-alikes get the real folder',
      );
    }, skip: 'Hardening (BUG-Q1g, low realism): look-alike letters');
  });
}

/// Records every call, so "the keychain was never touched" is checked.
class _SpyKeys implements KeyStore {
  _SpyKeys(this.inner);
  final FakeKeyStore inner;
  final calls = <String>[];

  @override
  Future<String?> read() {
    calls.add('read');
    return inner.read();
  }

  @override
  Future<void> write(String keyHex) {
    calls.add('write');
    return inner.write(keyHex);
  }
}
