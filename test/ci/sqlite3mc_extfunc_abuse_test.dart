// M1.9a tester: abuse cases for tool/check_sqlite3mc.sh (AC1, flag 1 in
// docs/licences.md). The script must fail closed: any path or file it cannot
// read and judge is a failure, never a pass. These run under the bash on the
// machine (stock macOS bash 3.2, or Git Bash on Windows).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/bash.dart';

final _script = File('tool/check_sqlite3mc.sh').absolute.path;

List<int> fake(List<String> strings) => [
  0,
  0,
  for (final s in strings) ...[...s.codeUnits, 0],
];

const clean = ['sqlite_master', 'sqlite3mc_config', 'main'];

const _symlinks =
    'a symlink needs Developer Mode on Windows, and Git Bash reads a native '
    'Windows link differently from a POSIX one; the DLL check is not given links';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sqlite3mc_abuse'));
  tearDown(() => dir.deleteSync(recursive: true));

  File binary(String name, List<String> strings) {
    final f = File(p.join(dir.path, name));
    f.parent.createSync(recursive: true);
    return f..writeAsBytesSync(fake(strings));
  }

  ProcessResult run(
    List<String> args, {
    Map<String, String>? env,
    String? cwd,
  }) => runBash(_script, args, environment: env, workingDirectory: cwd);

  String out(ProcessResult r) => '${r.stdout}${r.stderr}';

  group('file names', () {
    for (final name in [
      'sqlite3mc copy.dll',
      'two  spaces.dll',
      'star*.dll',
      '[brackets].dll',
      'dollar\$HOME.dll',
      "quote'.dll",
      'semi;colon.dll',
      'back\\slash.dll',
      'ünïcode.dll',
      '-leading-dash.dll',
    ]) {
      test(
        '"$name": a clean file passes and a bad one fails',
        skip: name.contains(RegExp(r'[*\\\n]'))
            ? skipOnWindows(
                'a Windows file name cannot hold *, a backslash or a new line',
              )
            : null,
        () {
          final good = binary(name, clean);
          final r = run([good.path]);
          expect(r.exitCode, 0, reason: out(r));
          good.writeAsBytesSync(fake([...clean, 'padl']));
          final bad = run([good.path]);
          expect(bad.exitCode, isNot(0));
          expect(out(bad), contains('padl'));
        },
      );
    }

    test('a relative path with a leading dash works from its folder', () {
      binary('-x.dll', [...clean, 'stdev']);
      final r = run(['./-x.dll'], cwd: dir.path);
      expect(r.exitCode, isNot(0), reason: out(r));
    });

    test('a path with spaces in the middle of a folder name', () {
      final f = binary('a b/c d/e f.dll', [...clean, 'variance']);
      expect(run([f.path]).exitCode, isNot(0));
    });

    test(
      'a new line in the file name does not hide a bad file',
      () {
        final f = binary('line\nbreak.dll', [...clean, 'padr']);
        expect(run([f.path]).exitCode, isNot(0));
      },
      skip: skipOnWindows('a Windows file name cannot hold a new line'),
    );
  });

  group('paths that are not a file', () {
    test('a folder is a failure, not a pass', () {
      Directory(p.join(dir.path, 'folder.dll')).createSync();
      final r = run([p.join(dir.path, 'folder.dll')]);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('FAIL'));
    });

    test('an empty argument is a failure', () {
      final r = run(['']);
      expect(r.exitCode, isNot(0));
    });

    test('a Windows-style path on a machine without it is a failure', () {
      final r = run([r'C:\build\windows\x64\runner\Release\sqlite3mc.dll']);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('no such file'));
    });

    test('a Git Bash style path that does not exist is a failure', () {
      final r = run(['/c/build/windows/x64/runner/Release/sqlite3mc.dll']);
      expect(r.exitCode, isNot(0));
    });

    test('a dangling symlink is a failure', () {
      final link = Link(p.join(dir.path, 'dangling.dll'))
        ..createSync(p.join(dir.path, 'nowhere.dll'));
      expect(run([link.path]).exitCode, isNot(0));
    }, skip: skipOnWindows(_symlinks));

    test('a symlink to a clean binary passes', () {
      final real = binary('real.dll', clean);
      final link = Link(p.join(dir.path, 'link.dll'))..createSync(real.path);
      expect(run([link.path]).exitCode, 0);
    }, skip: skipOnWindows(_symlinks));

    test('a symlink to a bad binary fails', () {
      final real = binary('real.dll', [...clean, 'charindex']);
      final link = Link(p.join(dir.path, 'link.dll'))..createSync(real.path);
      final r = run([link.path]);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('charindex'));
    }, skip: skipOnWindows(_symlinks));

    test('a symlink to a folder is a failure', () {
      final link = Link(p.join(dir.path, 'dirlink.dll'))..createSync(dir.path);
      expect(run([link.path]).exitCode, isNot(0));
    }, skip: skipOnWindows(_symlinks));

    test(
      'a file that cannot be read is a failure',
      () {
        if (Platform.environment['USER'] == 'root') return;
        final f = binary('locked.dll', clean);
        Process.runSync('chmod', ['000', f.path]);
        addTearDown(() => Process.runSync('chmod', ['644', f.path]));
        final r = run([f.path]);
        expect(r.exitCode, isNot(0), reason: out(r));
        expect(out(r), contains('FAIL'));
      },
      skip: skipOnWindows(
        'chmod 000 does not make a file unreadable on Windows',
      ),
    );
  });

  group('contents', () {
    test('marker names inside longer words pass', () {
      final r = run([
        binary('words.dll', [
          ...clean,
          'xpadlx',
          'padl_',
          '_padr',
          'padcx',
          'stdevice',
          'variances',
          'replicated',
          'preplicate',
        ]).path,
      ]);
      expect(r.exitCode, 0, reason: out(r));
    });

    test('a marker with a space or a dot around it is not a whole string', () {
      final r = run([
        binary('sp.dll', [
          ...clean,
          'padl ',
          ' padl',
          'padl.',
          'a padl b',
        ]).path,
      ]);
      expect(r.exitCode, 0, reason: out(r));
    });

    test('a long name inside a longer string still fails', () {
      final r = run([
        binary('inner.dll', [...clean, 'sqlite3_xstrfilterx_init']).path,
      ]);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('strfilter'));
    });

    test('the entry point name is caught inside a symbol string', () {
      final r = run([
        binary('entry.dll', [
          ...clean,
          '_sqlite3_RegisterExtensionFunctions',
        ]).path,
      ]);
      expect(r.exitCode, isNot(0));
    });

    test('a marker as the very last bytes, with no NUL after it, fails', () {
      final f = File(p.join(dir.path, 'tail.dll'))
        ..writeAsBytesSync([...fake(clean), ...'padl'.codeUnits]);
      expect(run([f.path]).exitCode, isNot(0));
    });

    test('a marker as the very first bytes, with no NUL before it, fails', () {
      final f = File(p.join(dir.path, 'head.dll'))
        ..writeAsBytesSync([...'stdev'.codeUnits, ...fake(clean)]);
      expect(run([f.path]).exitCode, isNot(0));
    });

    test('a marker on its own line instead of NUL-separated fails', () {
      final f = File(p.join(dir.path, 'nl.dll'))
        ..writeAsBytesSync([...fake(clean), ...'\npadc\n'.codeUnits]);
      expect(run([f.path]).exitCode, isNot(0));
    });

    test('every bad name is listed, not just the first', () {
      final r = run([
        binary('many.dll', [...clean, 'padl', 'stdev', 'leftstr']).path,
      ]);
      expect(
        out(r),
        allOf(contains('padl'), contains('stdev'), contains('leftstr')),
      );
    });

    final invalidUtf8 = [
      0xff, 0xfe, 0x80, 0, //
      ...fake(clean),
      0xc3, 0x28, 0,
      ...'padl'.codeUnits, 0,
      0xf0, 0x28, 0x8c, 0x28, 0,
    ];

    for (final locale in ['C', 'POSIX']) {
      test('bytes that are not valid UTF-8 do not hide a marker ($locale)', () {
        final f = File(p.join(dir.path, 'bin.dll'))
          ..writeAsBytesSync(invalidUtf8);
        final r = run([f.path], env: {'LC_ALL': locale, 'LANG': locale});
        expect(r.exitCode, isNot(0), reason: out(r));
        expect(out(r), contains('padl'));
      });
    }

    // BUG-M19A-5: in a UTF-8 locale (the default of Terminal.app and iTerm)
    // `tr` stops at the first byte that is not valid UTF-8, so every real
    // binary is reported as "not a SQLite library". It fails closed, but a
    // real release check gives a false FAIL with a misleading reason, and
    // build/native_assets/macos/libsqlite3mc.dylib shows it. The fix is
    // `LC_ALL=C tr` in strings_of.
    test('a bad binary is still named in a UTF-8 locale', () {
      final f = File(p.join(dir.path, 'bin.dll'))
        ..writeAsBytesSync(invalidUtf8);
      final r = run(
        [f.path],
        env: {'LC_ALL': 'en_US.UTF-8', 'LANG': 'en_US.UTF-8'},
      );
      expect(r.exitCode, isNot(0), reason: out(r));
      expect(out(r), contains('padl'));
    });

    test('a clean binary with invalid UTF-8 passes in a UTF-8 locale', () {
      final f = File(p.join(dir.path, 'bin.dll'))
        ..writeAsBytesSync([0xff, 0xfe, 0, ...fake(clean), 0xc3, 0x28, 0]);
      final r = run(
        [f.path],
        env: {'LC_ALL': 'en_US.UTF-8', 'LANG': 'en_US.UTF-8'},
      );
      expect(r.exitCode, 0, reason: out(r));
    });

    test('a marker only in UTF-16 text is not seen (known limit)', () {
      // C string tables are 8-bit, so extensionfunctions.c names are not
      // wide. This documents the limit rather than hiding it.
      final wide = [
        for (final c in 'padl'.codeUnits) ...[c, 0],
      ];
      final f = File(p.join(dir.path, 'wide.dll'))
        ..writeAsBytesSync([...fake(clean), ...wide, 0, 0]);
      expect(run([f.path]).exitCode, 0);
    });
  });

  group('big files', () {
    test(
      'a 16 MB binary of NUL bytes and one marker at the end fails',
      () {
        final f = File(p.join(dir.path, 'big.dll'));
        final raf = f.openSync(mode: FileMode.write);
        raf.writeFromSync(fake(clean));
        raf.setPositionSync(16 * 1024 * 1024);
        raf.writeFromSync([0, ...'upper_quartile'.codeUnits, 0]);
        raf.closeSync();
        final sw = Stopwatch()..start();
        final r = run([f.path]);
        expect(r.exitCode, isNot(0), reason: out(r));
        expect(out(r), contains('upper_quartile'));
        expect(sw.elapsed, lessThan(const Duration(seconds: 90)));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a 12 MB single line with no NUL and no new line passes if clean',
      () {
        final f = File(p.join(dir.path, 'line.dll'));
        final raf = f.openSync(mode: FileMode.write);
        raf.writeFromSync(fake(clean));
        final chunk = List<int>.filled(1024 * 1024, 0x41);
        for (var i = 0; i < 12; i++) {
          raf.writeFromSync(chunk);
        }
        raf.closeSync();
        final r = run([f.path]);
        expect(r.exitCode, 0, reason: out(r));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a binary with many thousands of strings and one marker fails',
      () {
        final f = binary('many.dll', [
          ...clean,
          for (var i = 0; i < 200000; i++) 'symbol_$i',
          'rightstr',
        ]);
        expect(run([f.path]).exitCode, isNot(0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('several files and arguments', () {
    test('the same good file twice passes', () {
      final f = binary('a.dll', clean);
      expect(run([f.path, f.path]).exitCode, 0);
    });

    test('a bad file after a missing one is still reported', () {
      final bad = binary('bad.dll', [...clean, 'padl']);
      final r = run([p.join(dir.path, 'missing.dll'), bad.path]);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('missing.dll'));
      expect(out(r), contains('bad.dll'));
    });

    test('a good file after a bad one does not turn the run green', () {
      final bad = binary('bad.dll', [...clean, 'padl']);
      final good = binary('good.dll', clean);
      expect(run([bad.path, good.path]).exitCode, isNot(0));
    });

    test('five files, the fourth bad: it is named, the others are ok', () {
      final files = [
        for (var i = 0; i < 5; i++)
          binary('f$i.dll', i == 3 ? [...clean, 'padc'] : clean).path,
      ];
      final r = run(files);
      expect(r.exitCode, isNot(0));
      // The script prints each path the way it was given to bash.
      expect(out(r), contains('FAIL ${forBash(files[3])}'));
      expect(out(r), contains('ok   ${forBash(files[0])}'));
      expect(out(r), contains('ok   ${forBash(files[4])}'));
    });
  });

  group('no argument: finding the binaries', () {
    ProcessResult discover(Directory root) =>
        run([], env: {'KUSUNGA_ROOT': root.path}, cwd: root.path);

    test('finds the Mac framework binary under build/ and checks it', () {
      binary(
        'build/macos/Build/Products/Release/Kusunga.app/Contents/Frameworks/'
        'sqlite3mc.framework/Versions/A/sqlite3mc',
        [...clean, 'padl'],
      );
      final r = discover(dir);
      expect(r.exitCode, isNot(0), reason: out(r));
      expect(out(r), contains('padl'));
    });

    test('finds the Windows DLL under build/ and checks it', () {
      binary('build/windows/x64/runner/Release/sqlite3mc.dll', [
        ...clean,
        'stdev',
      ]);
      expect(discover(dir).exitCode, isNot(0));
    });

    test('finds the downloaded library under .dart_tool and checks it', () {
      binary(
        '.dart_tool/hooks_runner/shared/sqlite3/build/download-abc/'
        'libsqlite3mc.dylib',
        [...clean, 'charindex'],
      );
      expect(discover(dir).exitCode, isNot(0));
    });

    test('one clean and one bad among those found fails the run', () {
      binary('build/windows/x64/runner/Release/sqlite3mc.dll', clean);
      binary('.dart_tool/hooks_runner/shared/sqlite3/build/d/libsqlite3mc.so', [
        ...clean,
        'variance',
      ]);
      final r = discover(dir);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('ok   '));
      expect(out(r), contains('FAIL '));
    });

    test('a root folder with spaces in its name works', () {
      final root = Directory(p.join(dir.path, 'my project'))..createSync();
      binary('my project/build/windows/sqlite3mc.dll', [...clean, 'padl']);
      expect(discover(root).exitCode, isNot(0));
      binary('my project/build/windows/sqlite3mc.dll', clean);
      expect(discover(root).exitCode, 0);
    });

    test('files with other names under build/ are not checked', () {
      binary('build/windows/other.dll', [...clean, 'padl']);
      final r = discover(dir);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('no sqlite3mc binary'));
    });

    test('runs from another folder than the repo root', () {
      final f = binary('x.dll', clean);
      final r = run([f.path], cwd: Directory.systemTemp.path);
      expect(r.exitCode, 0, reason: out(r));
    });
  });

  group('the script file', () {
    test('has LF line endings only, so Git Bash on Windows runs it', () {
      expect(File(_script).readAsBytesSync(), isNot(contains(13)));
    });

    test('uses no bash 4 features (macOS ships bash 3.2)', () {
      final src = File(_script).readAsStringSync();
      for (final bad in [
        'mapfile',
        'readarray',
        'declare -A',
        '\${!',
        '&>>',
        ';&',
        '^^',
        ',,',
      ]) {
        expect(src, isNot(contains(bad)), reason: bad);
      }
    });

    test('starts with a bash shebang', () {
      expect(
        File(_script).readAsStringSync(),
        startsWith('#!/usr/bin/env bash'),
      );
    });
  });
}
