// Edge cases of the Windows argument transfer in test/support/bash.dart
// (bashInvocation), added by the tester. The Windows invocation is run under
// real bash on every system. On a Mac or Linux: the stock /bin/bash (3.2 on a
// Mac) and any other bash found (Homebrew), so the reader code is tried on
// old and new bash. On Windows: the Git Bash that findBash finds, the bash the
// invocation is for. Where Git Bash differs from a POSIX bash, the test says
// so in a Windows branch or in its skip reason.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'bash.dart';
import 'bash_windows_args_test.dart' show dartWindowsCommandLine, msysArgv;

/// Bashes to try. Off Windows: the stock one, and Homebrew's when it is
/// installed. On Windows: Git Bash ([findBash]), as `/bin/bash` there is
/// `\bin\bash` on the current drive and never exists. findBash throws when
/// there is no Git Bash, so this file then fails to load with its message.
final _shells = Platform.isWindows
    ? [findBash()]
    : <String>[
        for (final s in [
          '/bin/bash',
          '/opt/homebrew/bin/bash',
          '/usr/local/bin/bash',
        ])
          if (File(s).existsSync()) s,
      ];

/// What `$BASH` is in a bash started as [shell]: the path the reader execs.
String _bashVariable(String shell) =>
    '${Process.runSync(shell, const ['-c', r'echo $BASH']).stdout}'.trim();

/// A variable of this process that no bash, nor Git Bash's runtime or its
/// launcher, makes or changes on its own, so seeing it in the script proves
/// it was inherited. HOME is not one: Git Bash makes it when Windows has
/// none. Names are compared without case on Windows, where they have none.
MapEntry<String, String>? _inheritedWitness() {
  const madeOrChanged = {
    'HOME',
    'PATH',
    'PWD',
    'OLDPWD',
    'SHLVL',
    '_',
    'SHELLOPTS',
    'BASHOPTS',
    'IFS',
    'TMP',
    'TEMP',
    'TMPDIR',
    'LD_LIBRARY_PATH',
    'SHELL',
    'TERM',
    'LANG',
    'HOSTNAME',
    'OSTYPE',
    'MACHTYPE',
    'HOSTTYPE',
    'EXEPATH',
    'PLINK_PROTOCOL',
    'SYSTEMROOT',
    'SYSTEMDRIVE',
    'WINDIR',
    'COMSPEC',
    'USERPROFILE',
    'HOMEDRIVE',
    'HOMEPATH',
    'LOGONSERVER',
    'USERDOMAIN',
    'USERNAME',
    'ORIGINAL_PATH',
    'ORIGINAL_TEMP',
    'ORIGINAL_TMP',
  };
  final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  final names = [
    for (final e in Platform.environment.entries)
      if (identifier.hasMatch(e.key) &&
          !madeOrChanged.contains(e.key.toUpperCase()) &&
          !RegExp(
            r'^(BASH|MSYS|MINGW|LC_|KUSUNGA_BASH_)',
          ).hasMatch(e.key.toUpperCase()) &&
          e.value.isNotEmpty &&
          !e.value.contains('\n'))
        e.key,
  ]..sort();
  if (names.isEmpty) return null;
  return MapEntry(names.first, Platform.environment[names.first]!);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_wedge'));
  tearDown(() => dir.deleteSync(recursive: true));

  File script(String body, {String name = 'a.sh'}) =>
      File('${dir.path}/$name')..writeAsStringSync(body);

  ProcessResult run(
    String shell,
    String scriptPath,
    List<String> args, {
    Map<String, String>? env,
    String? cwd,
  }) {
    final inv = bashInvocation(
      scriptPath,
      args,
      environment: env,
      windows: true,
    );
    return Process.runSync(
      shell,
      inv.arguments,
      environment: inv.environment,
      workingDirectory: cwd,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  /// What a script that prints `$#` and every argument NUL-terminated got.
  List<String> got(
    String shell,
    List<String> args, {
    Map<String, String>? env,
  }) {
    final s = script(r'printf "%s\0" "$#" "$@"');
    final r = run(shell, s.path, args, env: env);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final parts = '${r.stdout}'.split('\x00');
    return parts.sublist(0, parts.length - 1);
  }

  test('there is a bash to try', () => expect(_shells, isNotEmpty));

  for (final shell in _shells) {
    group('with $shell', () {
      test('zero arguments give "\$#" 0 and no empty argument', () {
        expect(got(shell, const []), ['0']);
      });

      test('200 arguments arrive in order', () {
        final args = [for (var i = 0; i < 200; i++) 'arg$i'];
        expect(got(shell, args), ['200', ...args]);
      });

      test('a 100000 character argument arrives whole', () {
        final big = 'x' * 100000;
        expect(got(shell, [big, 'after']), ['2', big, 'after']);
      });

      test('empty strings in every position are kept', () {
        expect(got(shell, ['', 'a', '', '', 'b', '']), [
          '6',
          '',
          'a',
          '',
          '',
          'b',
          '',
        ]);
      });

      test('trailing and leading new lines are not stripped', () {
        final args = ['a\n', 'b\n\n\n', '\n', '\nc', 'd\r\n', ' e \n '];
        expect(got(shell, args), ['6', ...args]);
        expect(got(shell, ['\n', '\n']), ['2', '\n', '\n']);
      });

      test('arguments that look like options, assignments or names', () {
        final args = [
          '-',
          '--',
          '-e',
          '-n',
          '-c',
          '-x',
          '--version',
          '-s',
          'a=b',
          '=',
          '==',
          '=x',
          'x=',
          'IFS=',
          'IFS= ',
          'PATH=/nowhere',
          'KUSUNGA_BASH_ARGC',
          'KUSUNGA_BASH_ARG_0',
          'KUSUNGA_BASH_RUN',
          'KUSUNGA_BASH_SCRIPT',
          r'$KUSUNGA_BASH_ARGC',
          r'${!v}',
          r'$v',
          r'$s',
          'ARGC',
          'ARG_1',
          's',
          'n',
          'i',
          'v',
          r'"$@"',
          '99',
          '-1',
          '0',
        ];
        expect(got(shell, args), ['${args.length}', ...args]);
      });

      test('shell syntax and glob characters stay text', () {
        final args = [
          '*',
          '?',
          '[a]',
          '{a,b}',
          '~',
          '~/x',
          '@x',
          '`id`',
          r'$(id)',
          '; echo pwned',
          '&& echo pwned',
          '| cat',
          '> /dev/null',
          '!!',
          '#c',
          "'",
          '"',
          r'\',
          r'\n',
          '\t',
          ' ',
          '  a  b  ',
          'é',
          '日本',
          '\u{1F600}',
        ];
        expect(got(shell, args), ['${args.length}', ...args]);
      });

      test('a glob argument is not expanded, whatever the folder holds', () {
        File('${dir.path}/one.txt').writeAsStringSync('');
        File('${dir.path}/two.txt').writeAsStringSync('');
        final s = script(r'printf "%s\0" "$#" "$@"');
        final r = run(shell, s.path, ['*', '*.txt', '?ne.txt'], cwd: dir.path);
        expect('${r.stdout}', '3\x00*\x00*.txt\x00?ne.txt\x00');
      });

      test('script paths with spaces, quotes, \$ and unicode work, \$0 is the '
          'path', () {
        for (final name in [
          'a b.sh',
          "it's.sh",
          // NTFS does not allow a double quote in a file name.
          if (!Platform.isWindows) 'q"q.sh',
          r'$HOME.sh',
          r'$(id).sh',
          'é 日本.sh',
          '`x`.sh',
          '-dash.sh',
          'a;b&c.sh',
          'semi;colon',
        ]) {
          final s = script(r'printf "%s\0" "$0" "$#" "$1"', name: name);
          final r = run(shell, s.path, ['one']);
          expect(r.exitCode, 0, reason: '$name: ${r.stderr}');
          // On Windows the reader is given the path with forward slashes.
          expect(
            '${r.stdout}',
            '${forBash(s.path)}\x001\x00one\x00',
            reason: name,
          );
        }
      });

      test('a relative script path is read in the working directory', () {
        script('echo "ran \$0 \$PWD"', name: 'rel.sh');
        final r = run(shell, 'rel.sh', const [], cwd: dir.path);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect('${r.stdout}', startsWith('ran rel.sh '));
      });

      test('the working directory and caller environment pass through', () {
        final s = script(
          r'printf "%s\0" "$PWD" "$KUSUNGA_BASHX" "$KUSUNGA_BAS" "$KUSUNGA_X" '
          r'"${KUSUNGA_X_EMPTY-unset}" "${KUSUNGA_BASH-unset}"',
        );
        final real = dir.resolveSymbolicLinksSync();
        final r = run(
          shell,
          s.path,
          const [],
          cwd: dir.path,
          env: {
            'KUSUNGA_BASHX': 'one',
            'KUSUNGA_BAS': 'three',
            'KUSUNGA_X': "multi\nline 'v'",
            'KUSUNGA_X_EMPTY': '',
            'KUSUNGA_BASH': 'bare',
          },
        );
        expect(r.exitCode, 0, reason: '${r.stderr}');
        final out = '${r.stdout}'.split('\x00');
        if (Platform.isWindows) {
          // Git Bash prints its own form of the folder (Temp is /tmp there),
          // so only the last segment can be compared. The relative script
          // test proves the real working directory.
          expect(out.first.split('/').last, p.basename(dir.path));
        } else {
          expect(out.first, real);
        }
        expect(out.sublist(1), [
          'one',
          'three',
          "multi\nline 'v'",
          '',
          'bare',
          '',
        ]);
      });

      test('the parent environment is still inherited', () {
        final witness = _inheritedWitness();
        expect(
          witness,
          isNotNull,
          reason: 'this process has no variable to check with',
        );
        final s = script('env');
        final r = run(shell, s.path, const []);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        String key(String n) => Platform.isWindows ? n.toUpperCase() : n;
        final seen = [
          for (final line in '${r.stdout}'.split('\n'))
            if (line.contains('=') &&
                key(line.substring(0, line.indexOf('='))) == key(witness!.key))
              line.substring(line.indexOf('=') + 1),
        ];
        expect(seen, [witness!.value], reason: witness.key);
      });

      test(
        'no KUSUNGA_BASH_ variable is left for the script or its children',
        () {
          final s = script(
            r'env | grep -c "^KUSUNGA_BASH_" ; '
            r'"$BASH" -c "env | grep -c ^KUSUNGA_BASH_"; '
            r'compgen -v | grep -c "^KUSUNGA_BASH_"',
          );
          final r = run(shell, s.path, ['a', 'b', 'c']);
          // grep -c prints 0 and exits 1 when nothing matches.
          expect('${r.stdout}'.trim().split('\n'), ['0', '0', '0']);
        },
      );

      test('the reader leaves no stray names in the script environment', () {
        // An earlier reader used the names s, n, i and v; it now uses only
        // KUSUNGA_BASH_ names. A caller who exports these short names must see
        // them again, unchanged, in the script.
        final s = script(r'printf "%s\0" "$s" "$n" "$i" "$v"');
        final r = run(
          shell,
          s.path,
          ['x', 'y'],
          env: {'s': 'S1', 'n': 'N1', 'i': 'I1', 'v': 'V1'},
        );
        expect('${r.stdout}', 'S1\x00N1\x00I1\x00V1\x00');
      });

      test('caller BASH, IFS, GLOBIGNORE, PATH-like and lower names: the '
          'Windows path gives the script what the plain path gives', () {
        // The reader runs `eval` with IFS= and set -f, then `exec "$BASH"`.
        // A caller who exports these names must not change that. The script
        // must get what the plain invocation (no reader at all) gives: the
        // caller's values, but $BASH and IFS set by bash itself. That text is
        // written out, because on Windows the plain invocation cannot be run
        // as it is (Git Bash would expand the `*` on its command line); off
        // Windows the plain invocation is run too and must give the same.
        final s = script(
          r'printf "%s\0" "$#" "$1" "$BASH" "$IFS" "$GLOBIGNORE" "$ARGC" '
          r'"$RUN" "$SCRIPT" "$x"; case $- in *f*) echo f;; *) echo nof;; esac',
        );
        final env = {
          'BASH': '/nonexistent/bash',
          'IFS': ':',
          'GLOBIGNORE': '*',
          'ARGC': '9',
          'RUN': 'r',
          'SCRIPT': 'sc',
          'x': 'ex',
        };
        final expected = [
          '2',
          '*',
          _bashVariable(shell),
          ' \t\n',
          '*',
          '9',
          'r',
          'sc',
          'ex',
          'nof\n',
        ].join('\x00');
        final win = run(shell, s.path, ['*', 'a b'], env: env);
        expect(win.exitCode, 0, reason: '${win.stderr}');
        expect('${win.stdout}', expected);
        if (!Platform.isWindows) {
          final plain = Process.runSync(
            shell,
            [s.path, '*', 'a b'],
            environment: env,
            stdoutEncoding: utf8,
          );
          expect('${plain.stdout}', expected);
        }
      });

      test('IFS, set -f and positional state do not leak into the script', () {
        final s = script(
          r'case $- in *f*) echo noglob;; *) echo glob;; esac; '
          r'printf "[%s]" "$IFS"; echo; x="a b"; set -- $x; echo $#',
        );
        final r = run(shell, s.path, const []);
        expect('${r.stdout}', 'glob\n[ \t\n]\n2\n');
      });

      test('an exported SHELLOPTS does not carry the reader\'s set -f into '
          'the script (L1)', () {
        // When SHELLOPTS is in the environment, bash keeps it up to date and
        // exported, so the reader's `set -f` reached the exec'd bash in it and
        // the script lost pathname expansion, on the Windows path only.
        final s = script(
          r'case $- in *f*) echo noglob;; *) echo glob;; esac; echo *.sh',
        );
        final r = run(
          shell,
          s.path,
          const [],
          cwd: dir.path,
          env: {'SHELLOPTS': 'braceexpand:hashall:interactive-comments'},
        );
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect('${r.stdout}', 'glob\na.sh\n');
      });

      test('stdout, stderr and the exit code are the script\'s own', () {
        for (final code in [0, 1, 2, 127, 255]) {
          final s = script('echo out; echo err >&2; exit $code');
          final r = run(shell, s.path, ['a']);
          expect(r.exitCode, code);
          expect(r.stdout, 'out\n');
          expect(r.stderr, 'err\n');
        }
      });

      test('a missing script gives bash\'s 127, not 0', () {
        final r = run(shell, '${dir.path}/nope.sh', ['a']);
        expect(r.exitCode, 127);
        expect('${r.stderr}', contains('nope.sh'));
      });

      test(
        'a signal that kills the script is reported as the signal',
        () {
          final s = script(r'kill -TERM $$; sleep 5');
          final r = run(shell, s.path, const []);
          // Dart reports a signal death as a negative code on POSIX, and the
          // reader must not have turned it into a normal exit.
          expect(r.exitCode, anyOf(-15, 143));
        },
        skip: skipOnWindows(
          'a Windows process does not die of a signal: Git Bash ends with an '
          'exit code of its own, and Dart reports a negative signal code only '
          'on POSIX, so there is no signal to see',
        ),
      );
    });
  }

  group('NUL cannot travel in an environment', () {
    // A NUL ends an environment value, so the transfer can never be exact
    // for it. It must fail loudly, never run with a cut argument. (On a Mac,
    // Process.runSync silently cuts at the NUL: the script got "a".)
    test('a NUL in an argument, the script or an environment value throws', () {
      for (final windows in [true, false]) {
        expect(
          () => bashInvocation('x.sh', ['a\x00b'], windows: windows),
          throwsArgumentError,
          reason: 'argument, windows=$windows',
        );
        expect(
          () => bashInvocation('x\x00.sh', const [], windows: windows),
          throwsArgumentError,
          reason: 'script, windows=$windows',
        );
        expect(
          () => bashInvocation(
            'x.sh',
            const [],
            environment: {'A': 'a\x00b'},
            windows: windows,
          ),
          throwsArgumentError,
          reason: 'environment, windows=$windows',
        );
      }
    });
  });

  group('the names runBash reserves', () {
    test('any KUSUNGA_BASH_ prefix, any case, is an ArgumentError', () {
      for (final windows in [true, false]) {
        for (final key in [
          'KUSUNGA_BASH_',
          'KUSUNGA_BASH_ARG_0',
          'KUSUNGA_BASH_RUN',
          'KUSUNGA_BASH_SCRIPT',
          'Kusunga_Bash_Argc',
          'kusunga_bash_',
        ]) {
          expect(
            () => bashInvocation(
              'x.sh',
              const [],
              environment: {key: ''},
              windows: windows,
            ),
            throwsArgumentError,
            reason: '$key windows=$windows',
          );
        }
      }
    });

    test(
      'a NUL in an environment name throws (B1 gap: it was left unchecked)',
      () {
        // Process.runSync cuts the name at the NUL, so `A\x00B` would silently
        // set `A`. Same rule as for values: refuse, never run with a changed
        // environment.
        for (final windows in [true, false]) {
          expect(
            () => bashInvocation(
              'x.sh',
              const [],
              environment: {'A\x00B': 'v'},
              windows: windows,
            ),
            throwsArgumentError,
            reason: 'windows=$windows',
          );
        }
      },
    );

    test('names that only look like the prefix are allowed', () {
      for (final key in [
        'KUSUNGA_BASH',
        'KUSUNGA_BASHX',
        'KUSUNGA_BAS',
        'XKUSUNGA_BASH_A',
        'KUSUNGA-BASH-A',
        'KUSUNGA_BAS_H_A',
      ]) {
        final inv = bashInvocation(
          'x.sh',
          const [],
          environment: {key: 'v'},
          windows: true,
        );
        expect(inv.environment[key], 'v', reason: key);
      }
    });

    test('the arguments are untouched when the error is thrown', () {
      final args = ['a'];
      expect(
        () => bashInvocation(
          'x.sh',
          args,
          environment: {'KUSUNGA_BASH_ARGC': '9'},
          windows: true,
        ),
        throwsArgumentError,
      );
      expect(args, ['a']);
    });
  });

  group('the Windows command line itself', () {
    test('is the same fixed text for every script and argument list', () {
      final a = bashInvocation('a.sh', const [], windows: true);
      final b = bashInvocation(r"C:\a b\it's.sh", [
        "q'",
        '*',
        '\n',
      ], windows: true);
      expect(a.arguments, b.arguments);
      expect(a.arguments.first, '-c');
      expect(a.arguments, hasLength(2));
      // Nothing the two Windows parsers would change.
      expect(a.arguments.last, isNot(matches(RegExp(r'''['"\\*?\[{~@\n]'''))));
    });

    test('argument count and values travel one for one', () {
      final inv = bashInvocation('s.sh', ['a', '', 'b'], windows: true);
      expect(inv.environment['KUSUNGA_BASH_ARGC'], '3');
      expect(inv.environment['KUSUNGA_BASH_ARG_0'], 'a');
      expect(inv.environment['KUSUNGA_BASH_ARG_1'], '');
      expect(inv.environment['KUSUNGA_BASH_ARG_2'], 'b');
      expect(inv.environment.containsKey('KUSUNGA_BASH_ARG_3'), isFalse);
    });

    test('the caller\'s environment map is not changed', () {
      final env = {'A': 'C:\\x'};
      bashInvocation('s.sh', const ['a'], environment: env, windows: true);
      expect(env, {'A': r'C:\x'});
    });
  });

  // The model in bash_windows_args_test.dart is only given the fixed command
  // line by its property test, so these pin the model itself with answers
  // that are known from the Dart SDK source and the CI runs (quote loss,
  // spaced path kept). A change to the model that breaks one of them would
  // otherwise go unseen.
  group('the model of the Windows parsers is not vacuous', () {
    const exe = r'C:\Program Files\Git\bin\bash.exe';
    List<String> argv(List<String> a) =>
        msysArgv(dartWindowsCommandLine(exe, a)).sublist(1);

    test('Dart quoting: empty, space, quote and trailing backslash', () {
      expect(dartWindowsCommandLine('bash', ['']), 'bash ""');
      expect(dartWindowsCommandLine('bash', ['a b']), 'bash "a b"');
      expect(dartWindowsCommandLine('bash', ['q"x']), r'bash "q\"x"');
      expect(dartWindowsCommandLine('bash', [r'a b\']), r'bash "a b\\"');
      expect(dartWindowsCommandLine('bash', ['plain']), 'bash plain');
      expect(dartWindowsCommandLine(exe, const []), '"$exe"');
    });

    test('an empty argument stays an empty word', () {
      expect(argv(['']), ['']);
      expect(argv(['a', '', 'b']), ['a', '', 'b']);
    });

    test('a lone single quote is dropped, a spaced one is kept', () {
      expect(argv(["q'x"]), ['qx']);
      expect(argv(["q'x y"]), ["q'x y"]);
      expect(msysArgv("bash 'a b' c"), ['bash', 'a b', 'c']);
      expect(msysArgv('bash "a\'b" c'), ['bash', "a'b", 'c']);
    });

    test('words the disk or a file could change are refused, not guessed', () {
      for (final w in ['*', '?x', '[a]', '{a,b}', '~', '~/x', '@list']) {
        expect(() => argv([w]), throwsUnsupportedError, reason: w);
      }
      // The same characters inside double quotes are plain text.
      expect(argv(['a b*']), ['a b*']);
    });

    test('an unquoted new line splits a word', () {
      expect(argv(['a\nb']), ['a', 'b']);
    });
  });
}
