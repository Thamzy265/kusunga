/// The bash the script tests (tool/*.sh) run under, found one way for every
/// test file.
///
/// On Windows, `bash` by name is not safe: C:\Windows\System32\bash.exe is the
/// WSL launcher, which has no Linux installed on a CI runner and prints "Windows
/// Subsystem for Linux has no installed distributions" in UTF-16. So on
/// Windows this looks only for Git Bash (Git for Windows), which the scripts
/// are documented to run under. It never skips: when there is no working bash
/// it throws a [StateError] that says what to install, so every test that
/// needs it fails with that message.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Picks a bash that runs. Every input is passed in so the Windows rules can
/// be tested on any machine (test/support/bash_test.dart).
///
/// [windows] false: `bash` from the PATH. True: Git Bash from the usual
/// install folders, then next to a `git.exe` that [gitExecutables] lists.
/// A candidate is used only when [works] says it can run a command.
String resolveBash({
  required bool windows,
  required Map<String, String> env,
  required bool Function(String path) exists,
  required List<String> Function() gitExecutables,
  required bool Function(String bash) works,
}) {
  if (!windows) {
    if (works('bash')) return 'bash';
    throw StateError(
      'bash was not found on the PATH, or it cannot run a command. '
      'The script tests need it.',
    );
  }
  final w = p.windows;
  final candidates = <String>[];
  void add(String path) {
    if (!candidates.contains(path)) candidates.add(path);
  }

  for (final key in ['ProgramFiles', 'ProgramW6432', 'ProgramFiles(x86)']) {
    final dir = env[key];
    if (dir != null && dir.isNotEmpty) {
      add(w.join(dir, 'Git', 'bin', 'bash.exe'));
    }
  }
  final local = env['LOCALAPPDATA'];
  if (local != null && local.isNotEmpty) {
    add(w.join(local, 'Programs', 'Git', 'bin', 'bash.exe'));
  }
  final tried = <String>[];
  for (final c in candidates) {
    if (exists(c)) {
      if (works(c)) return c;
      tried.add('$c (found, but it cannot run a command)');
    }
  }
  // Git is on the PATH but installed somewhere unusual: cmd\git.exe or
  // mingw64\bin\git.exe sits one or two folders below the install root.
  for (final git in gitExecutables()) {
    final bin = w.dirname(git);
    for (final root in [w.dirname(bin), w.dirname(w.dirname(bin))]) {
      final c = w.join(root, 'bin', 'bash.exe');
      if (exists(c) && !candidates.contains(c)) {
        candidates.add(c);
        if (works(c)) return c;
        tried.add('$c (found, but it cannot run a command)');
      }
    }
  }
  throw StateError(
    'No working Git Bash was found, and the script tests need one. Install '
    'Git for Windows (https://git-scm.com/download/win). Do not use the bash '
    'in C:\\Windows\\System32: that is the WSL launcher.'
    '${tried.isEmpty ? '' : ' Tried: ${tried.join('; ')}.'}',
  );
}

/// [s] with forward slashes when it is a Windows drive path (`C:\a\b`), for
/// the bash tools, which read `C:/a/b` the same way on every Git for Windows.
/// Anything else, and anything at all off Windows, is returned as it is.
/// [windows] defaults to this machine; tests pass it to check the rule.
String forBash(String s, {bool? windows}) =>
    (windows ?? Platform.isWindows) && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(s)
    ? s.replaceAll(r'\', '/')
    : s;

String? _found;

/// The bash to run scripts with on this machine; throws [StateError] when
/// there is none.
String findBash() => _found ??= resolveBash(
  windows: Platform.isWindows,
  env: Platform.environment,
  exists: (path) => File(path).existsSync(),
  gitExecutables: _whereGit,
  works: _runsACommand,
);

List<String> _whereGit() {
  try {
    final r = Process.runSync('where', ['git']);
    if (r.exitCode != 0) return const [];
    return '${r.stdout}'
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  } on ProcessException {
    return const [];
  }
}

bool _runsACommand(String bash) {
  try {
    final r = Process.runSync(bash, ['-c', 'echo kusunga-bash-ok']);
    return r.exitCode == 0 && '${r.stdout}'.trim() == 'kusunga-bash-ok';
  } on ProcessException {
    return false;
  }
}

/// What [runBash] starts bash with: its arguments and its environment.
typedef BashInvocation = ({
  List<String> arguments,
  Map<String, String> environment,
});

/// Environment names that [runBash] uses itself; a caller may not set them.
const reservedBashPrefix = 'KUSUNGA_BASH_';

/// The whole command line [runBash] gives Git Bash on Windows, after the
/// executable. Why: a Windows program gets one command-line string, not an
/// argv. Dart quotes each argument for the Microsoft C runtime, but Git Bash
/// (the MSYS2 runtime, winsup/cygwin/dcrt0.cc `build_argv` and `globify`)
/// parses that string with rules of its own: a single quote starts a quoted
/// run even outside double quotes (so an unquoted `quote'.dll` loses its
/// quote), a backslash can be taken as an escape, `*`, `?`, `[` and `{a,b}` are
/// expanded against the disk, a leading `~` is a home folder, `@name` reads
/// arguments from a file, and an unquoted new line splits a word. So no
/// argument is put on the command line. They go in the environment, which
/// reaches bash unparsed, and this fixed text reads them back. It has no
/// quote, backslash or wildcard, so both parsers leave it as it is (the same
/// shape as the probe `echo kusunga-bash-ok`), and `IFS=` with `set -f`
/// makes the unquoted `$KUSUNGA_BASH_RUN` one word, never split or globbed.
const _windowsCommand = r'set -f; IFS=; eval $KUSUNGA_BASH_RUN';

/// The code in KUSUNGA_BASH_RUN: rebuild "$@" as the script followed by
/// KUSUNGA_BASH_ARG_0..n-1, remove every KUSUNGA_BASH_ variable, and run the
/// script in a fresh bash (so IFS and `set -f` are back to normal and $0 is
/// the script, as with `bash script args`). Every name it sets has the
/// reserved prefix, which a caller cannot use, so the caller's own variables
/// reach the script unchanged. Bash 3.2 safe. Joined with \n, not a
/// multi-line literal, so the code is the same whatever line endings the
/// file has.
final _windowsRun = [
  r'set -- "$KUSUNGA_BASH_SCRIPT"',
  r'KUSUNGA_BASH_I=0',
  r'while [ "$KUSUNGA_BASH_I" -lt "$KUSUNGA_BASH_ARGC" ]; do',
  r'  KUSUNGA_BASH_V=KUSUNGA_BASH_ARG_$KUSUNGA_BASH_I',
  r'  set -- "$@" "${!KUSUNGA_BASH_V}"',
  r'  unset "$KUSUNGA_BASH_V"',
  r'  KUSUNGA_BASH_I=$((KUSUNGA_BASH_I + 1))',
  r'done',
  r'unset KUSUNGA_BASH_RUN KUSUNGA_BASH_SCRIPT KUSUNGA_BASH_ARGC '
      r'KUSUNGA_BASH_I KUSUNGA_BASH_V',
  r'exec "$BASH" "$@"',
].join('\n');

/// The arguments and environment [runBash] gives bash for [script] and
/// [args]. [windows] is passed in so the Windows rules can be tested on any
/// machine.
///
/// Off Windows: `bash script args...` with the environment as given.
/// On Windows: `bash -c <fixed text>`, with the script, the arguments and the
/// reading code in KUSUNGA_BASH_ variables, so every argument arrives byte
/// for byte (see [_windowsCommand]). Drive paths are given with forward
/// slashes ([forBash]).
///
/// Throws [ArgumentError] for an environment name with the
/// [reservedBashPrefix], and for a NUL character in the script, an argument,
/// an environment name or an environment value, on every system.
BashInvocation bashInvocation(
  String script,
  List<String> args, {
  Map<String, String>? environment,
  required bool windows,
}) {
  final env = environment ?? const <String, String>{};
  for (final key in env.keys) {
    // Windows names are case-insensitive, so compare them that way.
    if (key.toUpperCase().startsWith(reservedBashPrefix)) {
      throw ArgumentError.value(key, 'environment', 'is reserved for runBash');
    }
  }
  // A NUL ends a C string, so it cannot reach bash in an argument or in an
  // environment name or value: the process would get the text cut at the NUL
  // (`A\x00B` would set `A`). Refuse it on every system rather than run the
  // script with a changed value.
  void noNul(String value, String name) {
    if (value.contains('\x00')) {
      throw ArgumentError.value(value, name, 'contains a NUL character');
    }
  }

  noNul(script, 'script');
  for (final a in args) {
    noNul(a, 'args');
  }
  for (final e in env.entries) {
    noNul(e.key, 'environment');
    noNul(e.value, 'environment[${e.key}]');
  }
  if (!windows) return (arguments: [script, ...args], environment: {...env});
  String f(String s) => forBash(s, windows: true);
  return (
    arguments: const ['-c', _windowsCommand],
    environment: {
      for (final e in env.entries) e.key: f(e.value),
      'KUSUNGA_BASH_RUN': _windowsRun,
      'KUSUNGA_BASH_SCRIPT': f(script),
      'KUSUNGA_BASH_ARGC': '${args.length}',
      for (var i = 0; i < args.length; i++) 'KUSUNGA_BASH_ARG_$i': f(args[i]),
    },
  );
}

/// Runs [script] with [args] under [findBash] (or [shell], to try one bash in
/// particular). Every argument reaches the script byte for byte, on Windows
/// too ([bashInvocation]). On Windows, drive paths in the script, the
/// arguments and the environment values are given with forward slashes.
ProcessResult runBash(
  String script,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
  String? shell,
}) {
  final run = bashInvocation(
    script,
    args,
    environment: environment,
    windows: Platform.isWindows,
  );
  return Process.runSync(
    shell ?? findBash(),
    run.arguments,
    environment: run.environment,
    workingDirectory: workingDirectory,
  );
}

/// A `skip:` value for a test that cannot hold on Windows, for a reason that
/// is printed in the test run. Null on every other system, so the test runs
/// there (the Mac CI job runs all of them).
String? skipOnWindows(String reason) =>
    Platform.isWindows ? 'not on Windows: $reason' : null;
