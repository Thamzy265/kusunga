// Edge cases of the shared bash finder (test/support/bash.dart), added by the
// tester. Every Windows rule runs on any machine: the machine's answers are
// passed in, and the probes are recorded so a test can say which bash was
// (and was never) tried.
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'bash.dart';

const _gitBash = r'C:\Program Files\Git\bin\bash.exe';
const _wslBash = r'C:\Windows\System32\bash.exe';

class _Run {
  _Run(this.result, this.probed, this.error);
  final String? result;
  final List<String> probed;
  final Object? error;
}

/// Runs [resolveBash] as a Windows machine and records every path probed.
_Run _win({
  Map<String, String> env = const {},
  Set<String> files = const {},
  List<String> where = const [],
  Set<String> working = const {},
  bool Function(String)? works,
  bool windows = true,
}) {
  final probed = <String>[];
  try {
    final r = resolveBash(
      windows: windows,
      env: env,
      exists: files.contains,
      gitExecutables: () => where,
      works: (b) {
        probed.add(b);
        return works != null ? works(b) : working.contains(b);
      },
    );
    return _Run(r, probed, null);
  } on StateError catch (e) {
    return _Run(null, probed, e);
  }
}

void main() {
  group('resolveBash env handling on Windows', () {
    test('empty and missing variables are ignored, not joined into a path', () {
      final r = _win(
        env: const {'ProgramFiles': '', 'LOCALAPPDATA': ''},
        files: {_gitBash, r'Git\bin\bash.exe', r'\Git\bin\bash.exe'},
        working: {_gitBash},
      );
      expect(r.error, isNotNull, reason: 'nothing real to find: ${r.probed}');
      expect(r.probed, isEmpty, reason: 'a relative path was probed');
    });

    test('ProgramFiles wins over ProgramW6432 when both work', () {
      final r = _win(
        env: const {
          'ProgramFiles': r'C:\Program Files',
          'ProgramW6432': r'D:\Programs',
        },
        files: {_gitBash, r'D:\Programs\Git\bin\bash.exe'},
        working: {_gitBash, r'D:\Programs\Git\bin\bash.exe'},
      );
      expect(r.result, _gitBash);
    });

    test('ProgramW6432 is used when ProgramFiles is empty (32-bit parent)', () {
      final r = _win(
        env: const {
          'ProgramFiles': '',
          'ProgramW6432': r'C:\Program Files',
          'ProgramFiles(x86)': r'C:\Program Files (x86)',
        },
        files: {_gitBash},
        working: {_gitBash},
      );
      expect(r.result, _gitBash);
    });

    test('64-bit Git is tried before the 32-bit one', () {
      const x86 = r'C:\Program Files (x86)\Git\bin\bash.exe';
      final r = _win(
        env: const {
          'ProgramFiles(x86)': r'C:\Program Files (x86)',
          'ProgramW6432': r'C:\Program Files',
        },
        files: {_gitBash, x86},
        working: {_gitBash, x86},
      );
      expect(r.result, _gitBash);
    });

    test('the same folder in two variables is probed once', () {
      final r = _win(
        env: const {
          'ProgramFiles': r'C:\Program Files',
          'ProgramW6432': r'C:\Program Files',
        },
        files: {_gitBash},
        working: const {},
      );
      expect(r.error, isNotNull);
      expect(r.probed, [_gitBash]);
    });

    test('a trailing backslash on the variable still finds Git Bash', () {
      final r = _win(
        env: const {'ProgramFiles': r'C:\Program Files\'},
        files: {_gitBash},
        working: {_gitBash},
      );
      expect(r.result, _gitBash);
    });

    test('variable names are matched case-insensitively when the map is', () {
      // Platform.environment is case-insensitive on Windows.
      final env = LinkedHashMap<String, String>(
        equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
        hashCode: (a) => a.toLowerCase().hashCode,
      )..['PROGRAMFILES'] = r'C:\Program Files';
      final r = _win(env: env, files: {_gitBash}, working: {_gitBash});
      expect(r.result, _gitBash);
    });

    test('a per-user install is the last of the fixed places', () {
      const user = r'C:\Users\u\AppData\Local\Programs\Git\bin\bash.exe';
      final r = _win(
        env: const {
          'ProgramFiles': r'C:\Program Files',
          'LOCALAPPDATA': r'C:\Users\u\AppData\Local',
        },
        files: {_gitBash, user},
        working: {_gitBash, user},
      );
      expect(r.result, _gitBash);
      final only = _win(
        env: const {
          'ProgramFiles': r'C:\Program Files',
          'LOCALAPPDATA': r'C:\Users\u\AppData\Local',
        },
        files: {user},
        working: {user},
      );
      expect(only.result, user);
    });
  });

  group('resolveBash where git on Windows', () {
    test(
      'a path with spaces and several lines: the first with a bash wins',
      () {
        final r = _win(
          files: {_gitBash},
          working: {_gitBash},
          where: const [
            r'C:\Tools\NoBash\cmd\git.exe',
            r'C:\Program Files\Git\cmd\git.exe',
          ],
        );
        expect(r.result, _gitBash);
      },
    );

    test('mingw64\\bin\\git.exe with spaces in the path', () {
      final r = _win(
        files: {_gitBash},
        working: {_gitBash},
        where: const [r'C:\Program Files\Git\mingw64\bin\git.exe'],
      );
      expect(r.result, _gitBash);
    });

    test(
      'a candidate found twice (fixed place and where git) is probed once',
      () {
        final r = _win(
          env: const {'ProgramFiles': r'C:\Program Files'},
          files: {_gitBash},
          where: const [r'C:\Program Files\Git\cmd\git.exe'],
        );
        expect(r.error, isNotNull);
        expect(r.probed, [_gitBash]);
      },
    );

    test('a bash that fails the probe falls through to the next git', () {
      const second = r'D:\Git\bin\bash.exe';
      final r = _win(
        env: const {'ProgramFiles': r'C:\Program Files'},
        files: {_gitBash, second},
        working: {second},
        where: const [r'D:\Git\cmd\git.exe'],
      );
      expect(r.result, second);
      expect(r.probed, [_gitBash, second]);
    });

    test('only an existing file is probed', () {
      final r = _win(
        env: const {'ProgramFiles': r'C:\Program Files'},
        working: {_gitBash},
        where: const [r'D:\Git\cmd\git.exe'],
      );
      expect(r.error, isNotNull);
      expect(r.probed, isEmpty);
    });

    test('a git.exe in System32 never leads to the WSL launcher', () {
      for (final git in [
        r'C:\Windows\System32\git.exe',
        r'C:\Windows\System32\wsl\git.exe',
        r'C:\Windows\git.exe',
      ]) {
        final r = _win(files: {_wslBash}, working: {_wslBash}, where: [git]);
        expect(r.result, isNot(_wslBash), reason: git);
        expect(r.probed, isNot(contains(_wslBash)), reason: git);
      }
    });
  });

  group('resolveBash never uses bash by name on Windows', () {
    test('only the WSL launcher on the machine: fails, probes nothing', () {
      final r = _win(
        files: {_wslBash},
        working: {_wslBash, 'bash'},
        where: const [r'C:\Windows\System32\git.exe'],
      );
      expect(r.error, isA<StateError>());
      expect(r.probed, isEmpty, reason: 'a candidate that is not Git Bash');
    });

    test('"bash" and the WSL launcher are never probed, whatever exists', () {
      final r = _win(
        env: const {'ProgramFiles': r'C:\Program Files'},
        files: {_gitBash, _wslBash},
        works: (_) => false,
        where: const [r'C:\Program Files\Git\cmd\git.exe'],
      );
      expect(r.error, isA<StateError>());
      for (final b in r.probed) {
        expect(b, isNot('bash'));
        expect(b.toLowerCase(), isNot(contains('system32')));
        expect(b.toLowerCase(), endsWith(r'\git\bin\bash.exe'));
      }
    });

    test('a launcher copied to a Git-like path is rejected by the probe', () {
      // Its probe prints "no installed distributions": exit code is not 0.
      final r = _win(
        env: const {'ProgramFiles': r'C:\Program Files'},
        files: {_gitBash},
        works: (_) => false,
      );
      expect(r.result, isNull);
      expect(
        (r.error as StateError).message,
        allOf(
          contains(_gitBash),
          contains('cannot run a command'),
          contains('Git for Windows'),
          contains('WSL'),
        ),
      );
    });

    test('the error names every candidate that was found but failed', () {
      const other = r'D:\Git\bin\bash.exe';
      final r = _win(
        env: const {'ProgramFiles': r'C:\Program Files'},
        files: {_gitBash, other},
        works: (_) => false,
        where: const [r'D:\Git\cmd\git.exe'],
      );
      final m = (r.error as StateError).message;
      expect(m, contains(_gitBash));
      expect(m, contains(other));
    });

    test('with nothing found the error does not claim anything was tried', () {
      final r = _win();
      expect((r.error as StateError).message, isNot(contains('Tried:')));
    });
  });

  group('resolveBash off Windows', () {
    test('asks only for "bash"; env, files and where git are not used', () {
      final probed = <String>[];
      final r = resolveBash(
        windows: false,
        env: const {'ProgramFiles': r'C:\Program Files'},
        exists: (_) => fail('exists must not be called'),
        gitExecutables: () => fail('where git must not be run'),
        works: (b) {
          probed.add(b);
          return true;
        },
      );
      expect(r, 'bash');
      expect(probed, ['bash']);
    });
  });

  group('forBash', () {
    test('lower-case and upper-case drive letters, back or forward slash', () {
      expect(forBash(r'c:\a\b'), 'c:/a/b');
      expect(forBash(r'Z:\a'), 'Z:/a');
      expect(forBash(r'C:\'), 'C:/');
      expect(forBash(r'C:/a\b'), 'C:/a/b', reason: 'mixed slashes');
      expect(forBash('C:/a/b'), 'C:/a/b');
    });

    test(
      'a bare drive, a drive-relative path and look-alikes are not paths',
      () {
        for (final s in [
          'C:',
          'a:b',
          r'C:foo\bar',
          r'1:\x',
          r'CC:\x',
          r'--out=C:\x',
          r' C:\x',
          'key:value',
        ]) {
          expect(forBash(s), s);
        }
      },
    );

    test('UNC and extended-length prefixes are left as they are', () {
      for (final s in [
        r'\\server\share\f.dll',
        r'\\?\C:\long\path',
        '//server/share/f',
      ]) {
        expect(forBash(s), s);
      }
    });

    test('relative paths keep their slashes', () {
      for (final s in [r'tool\x.sh', './tool/x.sh', r'.\tool\x.sh', '../x']) {
        expect(forBash(s), s);
      }
    });

    test('a value that starts with a drive path is changed in every part', () {
      expect(forBash(r'C:\a;D:\b'), 'C:/a;D:/b');
      expect(forBash(r'C:\a b\c d'), 'C:/a b/c d');
    });

    test('is idempotent', () {
      for (final s in [r'C:\a\b', 'C:/a', r'\\s\h', 'x', r'c:\a;d:\b']) {
        expect(forBash(forBash(s)), forBash(s));
      }
    });
  });

  group('runBash on this machine', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_bash_e_'));
    tearDown(() => dir.deleteSync(recursive: true));

    File script(String body) =>
        File('${dir.path}/s.sh')
          ..writeAsStringSync('#!/usr/bin/env bash\n$body\n');

    test('arguments that merely look like paths arrive unchanged', () {
      final r = runBash(script(r'printf "[%s]" "$@"').path, [
        'C:',
        'a:b',
        r'\\server\share',
        'C:foo',
        '',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, r'[C:][a:b][\\server\share][C:foo][]');
    });

    test('a drive path in an argument or an env value arrives with /', () {
      final r = runBash(
        script(r'printf "[%s][%s]" "$1" "$KUSUNGA_P"').path,
        [r'c:\a b\c'],
        environment: {'KUSUNGA_P': r'C:\x;D:\y z'},
      );
      expect(r.stdout, '[c:/a b/c][C:/x;D:/y z]');
    });

    test('the exit code and both streams come back', () {
      final r = runBash(script('echo out; echo err >&2; exit 7').path, []);
      expect(r.exitCode, 7);
      expect('${r.stdout}'.trim(), 'out');
      expect('${r.stderr}'.trim(), 'err');
    });

    test('the working directory is used', () {
      final r = runBash(script('pwd').path, [], workingDirectory: dir.path);
      expect(r.exitCode, 0);
      expect('${r.stdout}'.trim(), endsWith(dir.path.split('/').last));
    });

    test('a script that does not exist fails, it is not a pass', () {
      final r = runBash('${dir.path}/missing.sh', []);
      expect(r.exitCode, isNot(0));
    });

    test('shell: runs the given bash, not the found one', () {
      expect(
        () => runBash(script('true').path, [], shell: '${dir.path}/nope'),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('skipOnWindows', () {
    test('gives a printed reason on Windows and null elsewhere', () {
      final s = skipOnWindows('because');
      if (Platform.isWindows) {
        expect(s, 'not on Windows: because');
      } else {
        expect(s, isNull);
      }
    });
  });
}
