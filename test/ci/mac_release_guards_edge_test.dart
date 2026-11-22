import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// M1.9b tester: edge cases for tool/mac_release_guards.sh and the Xcode build
/// settings. Probed by hand first (macOS 27, stock bash 3.2), then locked in.
/// Tests named "documented limit" pin behaviour that is a known blind spot, so
/// a change to it is noticed on purpose. Nothing here builds or signs.
final script = File('tool/mac_release_guards.sh').absolute.path;
const needle = 'KusungaAcceptSyntheticKeys';

String read(String path) => File(path).readAsStringSync();

ProcessResult guard(
  List<String> args, {
  String shell = 'bash',
  Map<String, String>? env,
  String? cwd,
}) => Process.runSync(
  shell,
  [script, ...args],
  environment: env,
  workingDirectory: cwd,
);

List<int> bin(String embedded) => [
  0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0, //
  ...embedded.codeUnits,
  0, 1, 2, 3,
];

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('macguard_edge'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory app(Map<String, List<int>> files, {String name = 'Kusunga.app'}) {
    final dir = Directory('${tmp.path}/$name')..createSync();
    files.forEach((rel, bytes) {
      File('${dir.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    });
    return dir;
  }

  group('binary guard: where the marker hides', () {
    test('inside a nested framework version folder', () {
      final dir = app({
        'Contents/MacOS/Kusunga': bin('ok'),
        'Contents/Frameworks/Y.framework/Versions/A/Y': bin(needle),
      });
      expect(guard(['binary', dir.path]).exitCode, 1);
    });

    test('inside a plugin dylib and a resource file', () {
      final a = app({
        'Contents/MacOS/Kusunga': bin('ok'),
        'Contents/Frameworks/libplugin.dylib': bin(needle),
      });
      expect(guard(['binary', a.path]).exitCode, 1);
      final b = app({
        'Contents/MacOS/Kusunga': bin('ok'),
        'Contents/Resources/notes.txt': 'x $needle y'.codeUnits,
      }, name: 'B.app');
      expect(guard(['binary', b.path]).exitCode, 1);
    });

    test('in a large file, across the 64 KiB and 1 MiB boundaries', () {
      for (final offset in [65536 - 10, 1048576 - 10, 5 * 1048576 - 13]) {
        final bytes = List<int>.filled(offset + needle.length + 50, 0x41);
        bytes.setRange(offset, offset + needle.length, needle.codeUnits);
        final dir = app({
          'Contents/MacOS/Kusunga': bytes,
        }, name: 'L$offset.app');
        expect(guard(['binary', dir.path]).exitCode, 1, reason: '$offset');
      }
    });

    test('in an in-bundle symlink target, reported once via the real file', () {
      final dir = app({'Contents/Resources/real.bin': bin(needle)});
      Link('${dir.path}/Contents/Resources/alias.bin').createSync('real.bin');
      Link('${dir.path}/Contents/Frameworks').createSync('Resources');
      final r = guard(['binary', dir.path]);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('real.bin'));
    });

    test(
      'a dangling symlink does not hide a marker or fail a clean bundle',
      () {
        final clean = app({'Contents/MacOS/Kusunga': bin('ok')});
        Link('${clean.path}/Contents/dangling').createSync('/nonexistent/x');
        expect(guard(['binary', clean.path]).exitCode, 0);
        final dirty = app({
          'Contents/MacOS/Kusunga': bin(needle),
        }, name: 'D.app');
        Link('${dirty.path}/Contents/dangling').createSync('/nonexistent/x');
        expect(guard(['binary', dirty.path]).exitCode, 1);
      },
    );

    test('a bundle of only symlinks has nothing to scan (2)', () {
      final target = File('${tmp.path}/outside.txt')..writeAsStringSync(needle);
      final dir = Directory('${tmp.path}/S.app')..createSync();
      Link('${dir.path}/l').createSync(target.path);
      expect(guard(['binary', dir.path]).exitCode, 2);
    });

    test('a top-level symlink to a file has nothing to scan (2)', () {
      final target = File('${tmp.path}/outside.txt')..writeAsStringSync(needle);
      final link = Link('${tmp.path}/top')..createSync(target.path);
      expect(guard(['binary', link.path]).exitCode, 2);
    });

    test('a directory that is not an .app is still scanned', () {
      final dir = app({'f': bin(needle)}, name: 'plain');
      expect(guard(['binary', dir.path]).exitCode, 1);
    });

    test(
      'a single clean file passes; a marker in a file named like a flag',
      () {
        final f = File('${tmp.path}/Kusunga')..writeAsBytesSync(bin('clean'));
        expect(guard(['binary', f.path]).exitCode, 0);
        final dir = app({'-n': bin(needle), 'a b': bin('x')});
        expect(guard(['binary', dir.path]).exitCode, 1);
      },
    );

    test('every dirty file is named, the pass line is absent', () {
      final dir = app({
        'one': bin(needle),
        'two': bin(needle),
        'three': bin('x'),
      });
      final r = guard(['binary', dir.path]);
      expect(r.exitCode, 1);
      expect(r.stderr, allOf(contains('one'), contains('two')));
      expect(r.stderr, isNot(contains('three contains')));
      expect(r.stdout, isNot(contains('ok:')));
    });

    test('a bundle path with spaces and quotes', () {
      final dirty = app({'f': bin(needle)}, name: 'My "Kusunga" \'x\'.app');
      expect(guard(['binary', dirty.path]).exitCode, 1);
      final clean = app({'f': bin('x')}, name: 'Your "K" \'y\'.app');
      expect(guard(['binary', clean.path]).exitCode, 0);
    });

    test('a path starting with ./- works', () {
      app({'f': bin(needle)}, name: '-dash.app');
      expect(guard(['binary', './-dash.app'], cwd: tmp.path).exitCode, 1);
    });

    test('an unreadable file fails with 2, never a pass', () {
      if (Platform.isWindows) return;
      final dir = app({'Contents/MacOS/Kusunga': bin('ok')});
      final f = File('${dir.path}/Contents/secret')..writeAsBytesSync(bin('x'));
      Process.runSync('chmod', ['000', f.path]);
      addTearDown(() => Process.runSync('chmod', ['644', f.path]));
      if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') return;
      expect(guard(['binary', dir.path]).exitCode, 2);
    });

    test('marker next to non-text bytes in the C locale', () {
      final f = File('${tmp.path}/m')
        ..writeAsBytesSync([0xFF, 0x80, ...needle.codeUnits, 0xC3, 0xFF]);
      expect(guard(['binary', f.path], env: {'LC_ALL': 'C'}).exitCode, 1);
    });

    test('documented limit: UTF-16 and NUL-split markers are not found', () {
      // The compiled switch is a plain C string in __cstring, so only the
      // contiguous 8-bit form matters. UTF-16 or a split marker is not scanned.
      final utf16 = <int>[
        for (final c in needle.codeUnits) ...[c, 0],
      ];
      final a = File('${tmp.path}/u16')..writeAsBytesSync(utf16);
      expect(guard(['binary', a.path]).exitCode, 0);
      final b = File('${tmp.path}/split')
        ..writeAsBytesSync([
          ...needle.codeUnits.sublist(0, 10),
          0,
          ...needle.codeUnits.sublist(10),
        ]);
      expect(guard(['binary', b.path]).exitCode, 0);
      final lower = File('${tmp.path}/lower')
        ..writeAsStringSync(needle.toLowerCase());
      expect(guard(['binary', lower.path]).exitCode, 0);
    });

    test('documented limit: a symlink to a file outside the bundle', () {
      // find -type f skips symlinks. codesign rejects such a bundle anyway, so
      // it cannot be notarised, but the guard itself does not follow it.
      final out = File('${tmp.path}/outside.txt')..writeAsStringSync(needle);
      final dir = app({'Contents/MacOS/Kusunga': bin('ok')});
      Link('${dir.path}/Contents/Resources').createSync(out.path);
      expect(guard(['binary', dir.path]).exitCode, 0);
    });
  });

  group('guard exit codes and usage', () {
    test('wrong arguments exit exactly 2 and print usage', () {
      for (final args in [
        <String>[],
        ['binary'],
        ['xcconfig'],
        ['binary', 'a', 'b'],
        ['bogus', 'x'],
        ['BINARY', 'x'],
        ['--', 'x'],
        ['-h'],
      ]) {
        final r = guard(args);
        expect(r.exitCode, 2, reason: '$args');
        expect(r.stderr, contains('usage'), reason: '$args');
      }
    });

    test('an empty path argument exits 2', () {
      expect(guard(['binary', '']).exitCode, 2);
      expect(guard(['xcconfig', '']).exitCode, 2);
    });

    test('an xcconfig guard on a directory exits 2', () {
      expect(guard(['xcconfig', tmp.path]).exitCode, 2);
    });
  });

  group('bash 3.2 (stock macOS)', () {
    final stock = File('/bin/bash');
    test('pass, fail and error exit codes are the same', () {
      if (!Platform.isMacOS || !stock.existsSync()) return;
      final ok = app({'f': bin('x')}, name: 'Ok.app');
      final bad = app({'f': bin(needle)}, name: 'Bad.app');
      expect(guard(['binary', ok.path], shell: stock.path).exitCode, 0);
      expect(guard(['binary', bad.path], shell: stock.path).exitCode, 1);
      expect(
        guard(['binary', '${tmp.path}/no'], shell: stock.path).exitCode,
        2,
      );
      expect(
        guard(['xcconfig', '${tmp.path}/no'], shell: stock.path).exitCode,
        2,
      );
    });
  });

  group('xcconfig guard: spelling variants', () {
    int check(String body) {
      final f = File('${tmp.path}/Local.xcconfig.example')
        ..writeAsStringSync(body);
      return guard(['xcconfig', f.path]).exitCode;
    }

    test('fails on SDK and combined conditionals', () {
      expect(
        check('SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=macosx*] = X\n'),
        1,
      );
      expect(
        check(
          'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Release][sdk=macosx*]'
          ' = X\n',
        ),
        1,
      );
      expect(check('OTHER_SWIFT_FLAGS[config=Release] = -DX\n'), 1);
      expect(check('OTHER_SWIFT_FLAGS[sdk=macosx*][arch=arm64] = -DX\n'), 1);
    });

    test('fails on tab, CRLF and no-space spellings', () {
      expect(check('\tSWIFT_ACTIVE_COMPILATION_CONDITIONS\t=\tX\n'), 1);
      expect(check('SWIFT_ACTIVE_COMPILATION_CONDITIONS=X'), 1);
      expect(check('A = 1\r\nSWIFT_ACTIVE_COMPILATION_CONDITIONS = X\r\n'), 1);
      expect(check('OTHER_SWIFT_FLAGS =\t-DX\n'), 1);
      expect(check('OTHER_SWIFT_FLAGS = -DX\r\n'), 1);
      expect(check('OTHER_SWIFT_FLAGS = -Onone -D\tX\n'), 1);
    });

    test('fails on inherited value and other -D positions', () {
      expect(
        check(
          'SWIFT_ACTIVE_COMPILATION_CONDITIONS = \$(inherited) KUSUNGA_X\n',
        ),
        1,
      );
      expect(check('OTHER_SWIFT_FLAGS = -Xfrontend -DX\n'), 1);
      expect(check('OTHER_SWIFT_FLAGS = -Onone -DX\n'), 1);
      expect(check('OTHER_SWIFT_FLAGS = -D X\n'), 1);
      expect(check('SWIFT_ACTIVE_COMPILATION_CONDITIONS \\\n = X\n'), 1);
    });

    test('a trailing // comment does not hide a real setting', () {
      expect(
        check('// c\nSWIFT_ACTIVE_COMPILATION_CONDITIONS = X // trailing\n'),
        1,
      );
    });

    test('a key that only appears after // on a setting line is a comment', () {
      expect(
        check(
          'DEVELOPMENT_TEAM = X // SWIFT_ACTIVE_COMPILATION_CONDITIONS = Y\n',
        ),
        0,
      );
      expect(check('  // c\n// OTHER_SWIFT_FLAGS = -DX\n'), 0);
    });

    test('settings outside the signing allow-list fail (R1)', () {
      // The guard is an allow-list: GCC_PREPROCESSOR_DEFINITIONS or an
      // unrelated key is as unwelcome in the signing example as a condition.
      expect(check('OTHER_SWIFT_FLAGS = -Onone\n'), 1);
      expect(check('GCC_PREPROCESSOR_DEFINITIONS = DEBUG=1\n'), 1);
      expect(check('FOO = \$(SWIFT_ACTIVE_COMPILATION_CONDITIONS)\n'), 1);
      expect(check('A = 1 // SWIFT_ACTIVE_COMPILATION_CONDITIONS = X\n'), 1);
      expect(check(''), 0);
    });

    test('#include and lower-case keys fail: not allow-listed (R1)', () {
      // An #include would pull in a file the guard does not read, so it fails
      // instead of passing. Xcode keys are case-sensitive; a lower-case key is
      // still not one of the allowed signing keys.
      expect(
        check('#include "Other.xcconfig"\n#include? "Local.xcconfig"\n'),
        1,
      );
      expect(check('swift_active_compilation_conditions = X\n'), 1);
    });
  });

  group('build settings: project mapping (AC3, AC8)', () {
    final pbx = read('macos/Runner.xcodeproj/project.pbxproj');
    final refs = {
      for (final m in RegExp(
        r'(\w{24}) /\* ([\w.\-]+\.xcconfig) \*/ = \{isa = PBXFileReference',
      ).allMatches(pbx))
        m[1]!: m[2]!,
    };
    // Every build configuration: id, base file, name, and its build settings.
    final configs = [
      for (final m in RegExp(
        r'\t\t(\w{24}) /\* (\w+) \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n'
        r'(?:\t\t\tbaseConfigurationReference = (\w{24}) [^\n]*\n)?'
        r'\t\t\tbuildSettings = \{\n(.*?)\n\t\t\t\};\n\t\t\tname = (\w+);',
        dotAll: true,
      ).allMatches(pbx))
        (name: m[5]!, base: m[3] == null ? null : refs[m[3]], settings: m[4]!),
    ];

    test('the parser found the expected configurations', () {
      expect(configs.length, 12);
      expect(refs.values, containsAll(['Release.xcconfig', 'Debug.xcconfig']));
    });

    test(
      'project-level Release and Profile use Release.xcconfig, Debug not',
      () {
        final project = configs.where(
          (c) => c.base == 'Release.xcconfig' || c.base == 'Debug.xcconfig',
        );
        expect(project.length, 3);
        for (final c in project) {
          expect(
            c.base,
            c.name == 'Debug' ? 'Debug.xcconfig' : 'Release.xcconfig',
            reason: c.name,
          );
        }
        expect(
          project.where((c) => c.base == 'Release.xcconfig').map((c) => c.name),
          unorderedEquals(['Release', 'Profile']),
        );
      },
    );

    test('no target or project setting overrides architectures or runtime', () {
      for (final c in configs) {
        for (final key in [
          'ARCHS',
          'VALID_ARCHS',
          'EXCLUDED_ARCHS',
          'ENABLE_HARDENED_RUNTIME',
          'OTHER_CODE_SIGN_FLAGS',
          'CODE_SIGN_INJECT_BASE_ENTITLEMENTS',
        ]) {
          expect(
            RegExp('^\\s*$key\\b', multiLine: true).hasMatch(c.settings),
            isFalse,
            reason: '$key in ${c.name} (${c.base})',
          );
        }
        expect(c.settings, isNot(contains('x86_64')));
        expect(c.settings, isNot(contains('arm64e')));
      }
    });

    test(
      'Release and Profile do not switch DEBUG code or change optimisation',
      () {
        for (final c in configs.where((c) => c.name != 'Debug')) {
          expect(
            c.settings,
            isNot(contains('SWIFT_ACTIVE_COMPILATION_CONDITIONS')),
            reason: c.name,
          );
          expect(
            c.settings,
            isNot(contains('OTHER_SWIFT_FLAGS')),
            reason: c.name,
          );
          expect(c.settings, isNot(contains('-Onone')), reason: c.name);
        }
      },
    );

    test('Debug gets no ARCHS or Hardened Runtime from its xcconfig files', () {
      final debug = read('macos/Runner/Configs/Debug.xcconfig');
      final flutterDebug = read('macos/Flutter/Flutter-Debug.xcconfig');
      for (final text in [debug, flutterDebug]) {
        expect(text, isNot(contains('ARCHS')));
        expect(text, isNot(contains('ENABLE_HARDENED_RUNTIME')));
        expect(text, isNot(contains('Release.xcconfig')));
      }
      // Debug keeps building for the host only.
      expect(pbx, contains('ONLY_ACTIVE_ARCH = YES;'));
    });

    test(
      'Release.xcconfig sets ARCHS and the runtime once, after its includes',
      () {
        final text = read('macos/Runner/Configs/Release.xcconfig');
        final lines = text.split('\n');
        int last(bool Function(String) f) => lines.lastIndexWhere(f);
        bool setsKey(String l, String k) => RegExp('^\\s*$k\\s*=').hasMatch(l);
        final archs = lines.where((l) => setsKey(l, 'ARCHS')).toList();
        expect(archs.length, 1);
        expect(archs.single.replaceAll(RegExp(r'\s'), ''), 'ARCHS=arm64');
        expect(
          lines
              .singleWhere((l) => setsKey(l, 'ENABLE_HARDENED_RUNTIME'))
              .replaceAll(RegExp(r'\s'), ''),
          'ENABLE_HARDENED_RUNTIME=YES',
        );
        expect(
          lines.where((l) => setsKey(l, 'ENABLE_HARDENED_RUNTIME')).length,
          1,
        );
        final include = last((l) => l.trimLeft().startsWith('#include'));
        expect(last((l) => setsKey(l, 'ARCHS')), greaterThan(include));
        expect(
          last((l) => setsKey(l, 'ENABLE_HARDENED_RUNTIME')),
          greaterThan(include),
        );
        // No later conditional line can undo them.
        expect(text, isNot(contains('ARCHS[')));
        expect(text, isNot(contains('ENABLE_HARDENED_RUNTIME[')));
      },
    );

    test(
      'Flutter-Release.xcconfig and generated settings do not set ARCHS',
      () {
        expect(
          read('macos/Flutter/Flutter-Release.xcconfig'),
          isNot(contains('ARCHS')),
        );
        final gen = File('macos/Flutter/ephemeral/Flutter-Generated.xcconfig');
        if (gen.existsSync()) {
          expect(gen.readAsStringSync(), isNot(contains('ARCHS')));
        }
      },
    );

    test('the deployment target is 12.0 in every project configuration', () {
      final all = RegExp(
        r'MACOSX_DEPLOYMENT_TARGET = ([\d.]+);',
      ).allMatches(pbx).map((m) => m[1]).toList();
      expect(all, isNotEmpty);
      expect(all.toSet(), {'12.0'});
    });

    test('the release notes line for the minimum macOS is in ADR 0003', () {
      final adr = read('docs/adr/0003-mac-distribution-and-sandbox.md');
      expect(adr, contains('arm64'));
      expect(adr, contains('Hardened Runtime'));
      expect(adr, contains('KusungaAcceptSyntheticKeys'));
    });
  });
}
