// How runBash hands a script its arguments on Windows, where Git Bash does
// not get an argv: it gets one command-line string, which Dart builds with
// the Microsoft C runtime's quoting rules and the MSYS2 runtime then parses
// with rules of its own (single quotes, globbing, braces, ~ and @file).
//
// The two Windows steps are modelled below as pure functions, so the rules
// run on every machine. The model is anchored to what the Windows CI job
// showed. The Windows-mode invocation is then also run under the real bash
// on this machine (Git Bash on the Windows job), to show every argument
// arrives byte for byte.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'bash.dart';

/// The Windows command line Dart builds for `Process.run(exe, args)`.
/// Copied from the Dart SDK (sdk/lib/_internal/vm/bin/process_patch.dart,
/// `_ProcessImpl` and `_windowsArgumentEscape`): the executable is put in
/// double quotes when it has a space, each argument goes through the C
/// runtime escaping, and they are joined with single spaces.
String dartWindowsCommandLine(String exe, List<String> args) {
  final path = exe.contains(' ') && !exe.contains('"') ? '"$exe"' : exe;
  return [path, ...args.map(_dartEscape)].join(' ');
}

String _dartEscape(String argument) {
  if (argument.isEmpty) return '""';
  if (!argument.contains('\t') &&
      !argument.contains(' ') &&
      !argument.contains('"')) {
    return argument;
  }
  final sb = StringBuffer();
  var next = 0;
  var quote = argument.indexOf('"');
  while (quote != -1) {
    var backslashes = 0;
    var pos = quote - 1;
    while (pos >= 0 && argument[pos] == r'\') {
      backslashes++;
      pos--;
    }
    sb.write(argument.substring(next, quote - backslashes));
    for (var i = 0; i < backslashes; i++) {
      sb.write(r'\\');
    }
    sb.write(r'\"');
    next = quote + 1;
    quote = argument.indexOf('"', next);
  }
  sb.write(argument.substring(next));
  final out = StringBuffer('"')..write(sb);
  for (var i = argument.length - 1; i >= 0 && argument[i] == r'\'; i--) {
    out.write(r'\');
  }
  out.write('"');
  return out.toString();
}

/// The argv an MSYS2 program (Git Bash) builds from [line] when a Windows
/// program, not another MSYS2 one, started it with globbing on (the
/// default). A transcription of `build_argv`, `quoted` and `globify` in
/// winsup/cygwin/dcrt0.cc of git-for-windows/msys2-runtime, with the
/// "minus quoting" that glob() gives back under GLOB_NOCHECK|GLOB_QUOTE.
///
/// It throws [UnsupportedError] for any word whose result depends on the
/// files on the machine or grows into several words (an unprotected `*`,
/// `?`, `[` or `{`, a leading `~`, or `@file` after argv[0]), so a word it
/// returns is exact, whatever the disk holds.
List<String> msysArgv(String line) {
  final c = line.split('');
  final argv = <String>[];
  bool sep(int i) => i >= c.length || ' \t\n\r'.contains(c[i]);
  var i = 0;
  while (i < c.length) {
    if (sep(i)) {
      i++;
      continue;
    }
    final start = i;
    var sawQuote = -1;
    while (i < c.length) {
      if (c[i] != '"' && c[i] != "'") {
        i++;
      } else {
        sawQuote = i;
        final keep = argv.isNotEmpty && c[start] != '@';
        i = keep ? _quotedKept(c, i) : _quotedStripped(c, i);
      }
      if (sep(i)) break;
    }
    final word = c.sublist(start, i).join();
    if (i < c.length) i++;
    if (argv.isNotEmpty && sawQuote != start && word.startsWith('@')) {
      throw UnsupportedError('@file: MSYS2 reads arguments from a file: $word');
    }
    argv.addAll(argv.isEmpty ? [word] : [_globify(word)]);
  }
  return argv;
}

/// `quoted` for argv[0]: the quotes are removed.
int _quotedStripped(List<String> c, int i) {
  final quote = c.removeAt(i);
  var p = i;
  while (p < c.length && c[p] != quote) {
    p++;
  }
  if (p < c.length) c.removeAt(p);
  return p;
}

/// `quoted` for later words: the quotes stay for `globify`. Inside double
/// quotes a backslash protects the next character and `""` becomes `\"`;
/// inside single quotes nothing is special. An unclosed quote runs to the
/// end of the line.
int _quotedKept(List<String> c, int i) {
  final quote = c[i];
  final special = quote == "'" ? const ["'"] : const [r'\', '"'];
  var cmd = i;
  while (cmd < c.length && ++cmd < c.length) {
    var p = cmd;
    while (p < c.length && !special.contains(c[p])) {
      p++;
    }
    if (p >= c.length) return c.length;
    if (c[p] == r'\') {
      cmd = p + 1;
    } else if (quote == '"' && p + 1 < c.length && c[p + 1] == '"') {
      c[p] = r'\';
      cmd = p + 1;
    } else {
      return p + 1;
    }
  }
  return cmd;
}

bool _isDosPath(String s) =>
    (s.length >= 2 && RegExp('[A-Za-z]').hasMatch(s[0]) && s[1] == ':') ||
    (s.length >= 3 &&
        s.startsWith(r'\\') &&
        RegExp('[A-Za-z]').hasMatch(s[2]) &&
        s.substring(3).contains(r'\'));

/// `globify` followed by glob()'s quote handling, for a word that matches
/// no file.
String _globify(String word) {
  if (!word.startsWith('~') && !word.contains(RegExp(r'''[?*\["'(){}]'''))) {
    return word;
  }
  final isQuote = RegExp('''["']''').hasMatch;
  var dos = _isDosPath(word);
  if (!dos && word.isNotEmpty && isQuote(word[0]) && word.length > 2) {
    dos = _isDosPath(word.substring(1));
  }
  // The pattern globify hands to glob(): quoted characters get a backslash.
  final pattern = StringBuffer();
  for (var s = 0; s < word.length; s++) {
    final ch = word[s];
    if (!isQuote(ch)) {
      if (dos && ch == r'\') pattern.write(r'\');
      pattern.write(ch);
      continue;
    }
    while (++s < word.length && word[s] != ch) {
      if (word[s] == r'\' &&
          s + 1 < word.length &&
          (word[s + 1] == ch || word[s + 1] == r'\')) {
        s++;
      }
      pattern
        ..write(r'\')
        ..write(word[s]);
    }
    if (s >= word.length) break;
  }
  // glob() with GLOB_QUOTE: a backslash protects the next character.
  final p = pattern.toString();
  final out = StringBuffer();
  for (var k = 0; k < p.length; k++) {
    if (p[k] == r'\') {
      out.write(++k < p.length ? p[k] : r'\');
    } else if ('*?[{'.contains(p[k]) || (k == 0 && p[k] == '~')) {
      throw UnsupportedError(
        'the result of "$word" depends on the files on the machine or on '
        'brace expansion',
      );
    } else {
      out.write(p[k]);
    }
  }
  return out.toString();
}

/// Arguments the script tests pass, or could: every character that Dart's
/// quoting or the MSYS2 parser treats specially, alone and mixed.
const hard = [
  "quote'.dll",
  r"C:\Users\RUNNER~1\AppData\Local\Temp\sqlite3mc_abuse2744870a\quote'.dll",
  "it's 'quoted' \"twice\"",
  '"',
  "'",
  '""',
  "''",
  '',
  ' ',
  'two  spaces',
  'tab\there',
  'line\nbreak',
  'cr\rlf\r\n',
  r'back\slash',
  r'trailing\',
  r'\"',
  r'\\server\share\f.dll',
  r'C:\a b\c\',
  r'C:\x"y',
  r"C:\dir\it's here.dll",
  'semi;colon & pipe | lt < gt >',
  r'dollar$HOME $(echo no) `echo no` ${x}',
  '!bang',
  'star*.dll',
  '?.dll',
  '[brackets].dll',
  '{a,b}',
  '{}',
  '(paren)',
  '~',
  '~root/x',
  '@args.txt',
  '-leading-dash',
  r'--out=C:\x',
  '%PATH%',
  '^caret',
  'ünïcode ✓',
  '=',
];

const _gitBash = r'C:\Program Files\Git\bin\bash.exe';

void main() {
  group('the MSYS2 model matches what the Windows CI job showed', () {
    List<String> parsed(List<String> args) =>
        msysArgv(dartWindowsCommandLine(_gitBash, args)).sublist(1);

    test('an unquoted path loses its single quote (CI run 45161191729)', () {
      // The failing test passed this path; the script said
      // "FAIL C:/Users/RUNNER~1/.../sqlite3mc_abuse2744870a/quote.dll".
      const path =
          'C:/Users/RUNNER~1/AppData/Local/Temp/sqlite3mc_abuse2744870a/'
          "quote'.dll";
      expect(parsed(['tool/check_sqlite3mc.sh', path]), [
        'tool/check_sqlite3mc.sh',
        'C:/Users/RUNNER~1/AppData/Local/Temp/sqlite3mc_abuse2744870a/'
            'quote.dll',
      ]);
    });

    test('a path with a space keeps its single quotes (edge test passed)', () {
      // Dart puts it in double quotes, and MSYS2 keeps ' inside "...".
      const path = "D:/a/t/macguard_edge1/My Kusunga 'x'.app";
      expect(parsed(['binary', path]), ['binary', path]);
    });

    test('the bash probe and plain names arrive as they are (CI passed)', () {
      for (final args in [
        ['-c', 'echo kusunga-bash-ok'],
        ['C:/t/semi;colon.dll'],
        [r'C:/t/dollar$HOME.dll'],
        ['C:/t/ünïcode.dll'],
        ['C:/t/sqlite3mc copy.dll'],
        ['C:/t/two  spaces.dll'],
      ]) {
        expect(parsed(args), args);
      }
    });
  });

  group('runBash on Windows (the rules, run here)', () {
    test('the command line survives the MSYS2 parser for any argument', () {
      for (final a in hard) {
        final run = bashInvocation(
          r'D:\a\kusunga\kusunga\tool\check_sqlite3mc.sh',
          [a, 'x$a'],
          environment: {'KUSUNGA_X': a},
          windows: true,
        );
        final line = dartWindowsCommandLine(_gitBash, run.arguments);
        expect(
          msysArgv(line).sublist(1),
          run.arguments,
          reason: 'argument ${jsonEncode(a)}, command line $line',
        );
      }
    });
  });

  group('the Windows invocation, run by the bash on this machine', () {
    late Directory dir;
    late File script;
    setUp(() {
      dir = Directory.systemTemp.createTempSync("kusunga_bash_w'");
      script = File('${dir.path}/args.sh')
        ..writeAsStringSync(
          r'printf "%s\0" "$0" "$#" "$KUSUNGA_X" "${!KUSUNGA_BASH_*}" "$@"',
        );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    List<String> received(BashInvocation run) {
      final r = Process.runSync(
        findBash(),
        run.arguments,
        environment: run.environment,
        workingDirectory: dir.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final parts = '${r.stdout}'.split('\x00');
      expect(parts.last, '');
      return parts.sublist(0, parts.length - 1);
    }

    test('every argument and the env arrive byte for byte', () {
      final run = bashInvocation(
        script.path,
        hard,
        environment: {'KUSUNGA_X': "env 'x' \"y\" \$z"},
        windows: true,
      );
      expect(received(run), [
        forBash(script.path, windows: true),
        '${hard.length}',
        "env 'x' \"y\" \$z",
        '',
        for (final a in hard) forBash(a, windows: true),
      ]);
    });

    test('no arguments, and an exit code that comes back', () {
      final run = bashInvocation(script.path, const [], windows: true);
      expect(received(run), [forBash(script.path, windows: true), '0', '', '']);
      script.writeAsStringSync('exit 7');
      final exit = bashInvocation(script.path, const [], windows: true);
      final r = Process.runSync(
        findBash(),
        exit.arguments,
        environment: exit.environment,
      );
      expect(r.exitCode, 7);
    });

    test('drive paths are given with forward slashes', () {
      final run = bashInvocation(
        script.path,
        [r'C:\a b\c', r'--out=C:\x'],
        environment: {'KUSUNGA_X': r'C:\x;D:\y z'},
        windows: true,
      );
      expect(received(run).sublist(1), [
        '2',
        'C:/x;D:/y z',
        '',
        'C:/a b/c',
        r'--out=C:\x',
      ]);
    });
  });

  group('the names runBash uses are reserved', () {
    test('a caller cannot set them, on any system', () {
      for (final windows in [true, false]) {
        for (final key in ['KUSUNGA_BASH_ARGC', 'kusunga_bash_x']) {
          expect(
            () => bashInvocation(
              'x.sh',
              const [],
              environment: {key: 'v'},
              windows: windows,
            ),
            throwsArgumentError,
          );
        }
      }
    });
  });

  group('off Windows nothing changes', () {
    test('the script and arguments are passed as they are', () {
      final run = bashInvocation(
        'tool/x.sh',
        [r'C:\a', "q'", ''],
        environment: {'KUSUNGA_X': r'C:\b'},
        windows: false,
      );
      expect(run.arguments, ['tool/x.sh', r'C:\a', "q'", '']);
      expect(run.environment, {'KUSUNGA_X': r'C:\b'});
    });

    test('forBash leaves a drive path alone', () {
      expect(forBash(r'C:\a\b', windows: false), r'C:\a\b');
      expect(forBash(r'C:\a\b', windows: true), 'C:/a/b');
      if (!Platform.isWindows) expect(forBash(r'C:\a\b'), r'C:\a\b');
    });
  });
}
