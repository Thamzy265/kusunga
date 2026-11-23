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
/// Anything else is returned as it is.
String forBash(String s) =>
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(s) ? s.replaceAll(r'\', '/') : s;

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

/// Runs [script] with [args] under [findBash] (or [shell], to try one bash in
/// particular). Windows drive paths in the script, the arguments and the
/// environment values are given to bash with forward slashes.
ProcessResult runBash(
  String script,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
  String? shell,
}) => Process.runSync(
  shell ?? findBash(),
  [forBash(script), for (final a in args) forBash(a)],
  environment: environment?.map((k, v) => MapEntry(k, forBash(v))),
  workingDirectory: workingDirectory,
);

/// A `skip:` value for a test that cannot hold on Windows, for a reason that
/// is printed in the test run. Null on every other system, so the test runs
/// there (the Mac CI job runs all of them).
String? skipOnWindows(String reason) =>
    Platform.isWindows ? 'not on Windows: $reason' : null;
