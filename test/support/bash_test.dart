// The shared helper that finds a real bash for the script tests
// (test/support/bash.dart). The Windows rules run here on any machine, with
// the machine's answers passed in.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'bash.dart';

const _gitBash = r'C:\Program Files\Git\bin\bash.exe';
const _wslBash = r'C:\Windows\System32\bash.exe';

/// A Windows machine like the GitHub runner: Git installed, WSL launcher
/// first on the PATH.
String resolve({
  bool windows = true,
  Map<String, String> env = const {'ProgramFiles': r'C:\Program Files'},
  Set<String> files = const {_gitBash, _wslBash},
  List<String> where = const [],
  bool Function(String)? works,
}) => resolveBash(
  windows: windows,
  env: env,
  exists: files.contains,
  gitExecutables: () => where,
  works: works ?? (b) => b != _wslBash,
);

void main() {
  group('resolveBash on Windows', () {
    test('uses Git Bash from Program Files, never the WSL launcher', () {
      expect(resolve(), _gitBash);
    });

    test('is not fooled by a bash.exe in System32 that is not Git', () {
      expect(resolve(files: {_wslBash, _gitBash}), isNot(_wslBash));
    });

    test('finds Git Bash from where git when Program Files has none', () {
      const root = r'D:\tools\Git';
      expect(
        resolve(
          env: const {},
          files: {r'D:\tools\Git\bin\bash.exe', _wslBash},
          where: const [r'D:\tools\Git\cmd\git.exe'],
        ),
        r'D:\tools\Git\bin\bash.exe',
        reason: root,
      );
    });

    test('finds Git Bash from a git.exe in mingw64\\bin', () {
      expect(
        resolve(
          env: const {},
          files: {r'D:\Git\bin\bash.exe'},
          where: const [r'D:\Git\mingw64\bin\git.exe'],
        ),
        r'D:\Git\bin\bash.exe',
      );
    });

    test('finds a per-user Git install', () {
      expect(
        resolve(
          env: const {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
          files: {r'C:\Users\u\AppData\Local\Programs\Git\bin\bash.exe'},
        ),
        r'C:\Users\u\AppData\Local\Programs\Git\bin\bash.exe',
      );
    });

    test('skips a Git Bash that cannot run a command and takes the next', () {
      const other = r'D:\Git\bin\bash.exe';
      expect(
        resolve(
          files: {_gitBash, other},
          where: const [r'D:\Git\cmd\git.exe'],
          works: (b) => b == other,
        ),
        other,
      );
    });

    test('fails loudly, naming Git for Windows, when there is none', () {
      expect(
        () => resolve(env: const {}, files: {_wslBash}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Git for Windows'), contains('WSL')),
          ),
        ),
      );
    });

    test('fails loudly when Git Bash is there but cannot run', () {
      expect(
        () => resolve(works: (_) => false),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(_gitBash),
          ),
        ),
      );
    });
  });

  group('resolveBash elsewhere', () {
    test('uses bash from the PATH when it runs', () {
      expect(resolve(windows: false, works: (b) => b == 'bash'), 'bash');
    });

    test('fails loudly when the bash on the PATH does not run', () {
      expect(
        () => resolve(windows: false, works: (_) => false),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('the real machine', () {
    test('a real bash is found and runs a command', () {
      final r = Process.runSync(findBash(), ['-c', 'echo hello']);
      expect(r.exitCode, 0);
      expect('${r.stdout}'.trim(), 'hello');
    });

    test('runBash runs a script file with its arguments', () {
      final dir = Directory.systemTemp.createTempSync('kusunga_bash_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final script = File('${dir.path}/echo.sh')
        ..writeAsStringSync('#!/usr/bin/env bash\necho "[\$1][\$KUSUNGA_X]"\n');
      final r = runBash(
        script.path,
        ['a b'],
        environment: {'KUSUNGA_X': 'v'},
        workingDirectory: dir.path,
      );
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}'.trim(), '[a b][v]');
    });
  });

  group('forBash', () {
    test('turns a Windows drive path into forward slashes', () {
      expect(forBash(r'C:\Users\a b\x.dll'), 'C:/Users/a b/x.dll');
      expect(forBash(r'D:/a/k/x'), 'D:/a/k/x');
    });

    test('leaves everything else alone', () {
      for (final s in ['', 'tool/x.sh', r'back\slash', '-x', r'\\server\s']) {
        expect(forBash(s), s);
      }
    });
  });
}
