import 'package:flutter_test/flutter_test.dart';

import '../support/source_text.dart';

/// Edge tests for the Windows CI artifact upload (PM decision 2026-11-25:
/// "CI uploads it", kept 3 days, public repo). They parse the workflow into
/// steps and ignore comment lines, so a word in a comment, a step moved to the
/// macOS job, or a loosened condition cannot satisfy them.
///
/// The parser is deliberately small: it knows only this file's shape (two
/// space indent for jobs, six spaces for `- ` steps, eight for step keys).
class _Step {
  _Step(this.lines);
  final List<String> lines; // comment-only lines already removed

  String get text => lines.join('\n');

  /// Top-level key of the step (`if`, `uses`, `run`, `name`...) -> raw value.
  /// Keys under `with:` are returned by [withMap].
  String? key(String k) {
    final re = RegExp('^(?:      - |        )$k: (.*)\$');
    final found = <String>[
      for (final l in lines)
        if (re.hasMatch(l)) re.firstMatch(l)!.group(1)!,
    ];
    expect(found.length, lessThanOrEqualTo(1), reason: 'duplicate $k in $text');
    return found.isEmpty ? null : found.single;
  }

  /// Keys directly under `with:` (ten space indent).
  Map<String, String> withMap() {
    final map = <String, String>{};
    var inWith = false;
    for (final l in lines) {
      if (l == '        with:') {
        inWith = true;
        continue;
      }
      if (inWith) {
        final m = RegExp(r'^          ([\w-]+): (.*)$').firstMatch(l);
        if (m == null) {
          inWith = false;
          continue;
        }
        expect(map.containsKey(m.group(1)), isFalse, reason: 'duplicate key');
        map[m.group(1)!] = m.group(2)!;
      }
    }
    return map;
  }
}

Map<String, List<_Step>> _jobs() {
  final lines = readSource('.github/workflows/check.yml').split('\n');
  final jobs = <String, List<_Step>>{};
  String? job;
  List<String>? current;
  void flush() {
    final done = current;
    if (job != null && done != null) {
      jobs[job]!.add(_Step(done));
    }
    current = null;
  }

  var inJobs = false;
  for (final raw in lines) {
    if (raw == 'jobs:') {
      inJobs = true;
      continue;
    }
    if (!inJobs) continue;
    final jobMatch = RegExp(r'^  (\w[\w-]*):\s*$').firstMatch(raw);
    if (jobMatch != null) {
      flush();
      job = jobMatch.group(1);
      jobs[job!] = [];
      continue;
    }
    if (job == null) continue;
    if (raw.trimLeft().startsWith('#')) continue; // comment-only line
    if (raw.startsWith('      - ')) {
      flush();
      current = [raw];
    } else if (current != null && raw.trim().isNotEmpty) {
      current!.add(raw);
    }
  }
  flush();
  return jobs;
}

bool _isUpload(_Step s) =>
    (s.key('uses') ?? '').startsWith('actions/upload-artifact');

void main() {
  late Map<String, List<_Step>> jobs;
  late List<_Step> windows;
  late _Step upload;

  setUp(() {
    jobs = _jobs();
    windows = jobs['windows']!;
    final found = windows.where(_isUpload).toList();
    expect(found, hasLength(1), reason: 'exactly one upload in windows job');
    upload = found.single;
  });

  test('the parser sees both jobs and their steps (guards the guard)', () {
    expect(jobs.keys, containsAll(['macos', 'windows']));
    expect(windows.length, greaterThan(5));
  });

  test('no upload-artifact in any job but windows, comments excluded', () {
    for (final e in jobs.entries) {
      if (e.key == 'windows') continue;
      expect(
        e.value.where(_isUpload),
        isEmpty,
        reason: '${e.key} must not upload',
      );
    }
  });

  test('the upload is a real step after the build, and the last step', () {
    final buildIdx = windows.indexWhere(
      (s) => s.key('run') == 'flutter build windows --debug',
    );
    expect(buildIdx, greaterThanOrEqualTo(0), reason: 'a real build step');
    final uploadIdx = windows.indexOf(upload);
    expect(uploadIdx, greaterThan(buildIdx));
    // Last, so no later step can sit between the build and the upload with
    // different success semantics, and nothing uploads stale output.
    expect(uploadIdx, windows.length - 1);
  });

  test('the upload condition is exactly success(): not always, not '
      '!cancelled, not failure, no continue-on-error', () {
    expect(upload.key('if'), r'${{ success() }}');
    expect(upload.text, isNot(contains('always()')));
    expect(upload.text, isNot(contains('cancelled()')));
    expect(upload.text, isNot(contains('failure()')));
    expect(upload.key('continue-on-error'), isNull);
    // The build keeps running after failed tests, which is why the upload
    // needs its own condition: success() is false once any earlier step failed.
    final build = windows.firstWhere(
      (s) => s.key('run') == 'flutter build windows --debug',
    );
    expect(build.key('if'), r'${{ !cancelled() }}');
  });

  test('the action is pinned to a 40-hex commit SHA with a version comment, '
      'never a tag', () {
    final uses = RegExp(
      r'^      - uses: (\S+)@(\S+) # (v\d+\.\d+\.\d+)$',
    ).firstMatch(upload.lines.first);
    expect(uses, isNotNull, reason: upload.lines.first);
    expect(uses!.group(1), 'actions/upload-artifact');
    expect(uses.group(2), matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(uses.group(3), 'v7.0.2');
    expect(upload.text, isNot(contains('upload-artifact@v')));
  });

  test('every action in the whole workflow is pinned to a 40-hex SHA', () {
    for (final e in jobs.entries) {
      for (final s in e.value) {
        final u = s.key('uses');
        if (u == null) continue;
        expect(
          u,
          matches(RegExp(r'^[\w./-]+@[0-9a-f]{40} # v\d+(\.\d+)*$')),
          reason: '${e.key}: $u',
        );
      }
    }
  });

  test('retention is exactly 3 days: present, one integer, not 30 or 90', () {
    final w = upload.withMap();
    expect(w['retention-days'], '3');
  });

  test('path is the whole Debug folder: one line, no glob, no exclusion, '
      'not just the exe', () {
    final w = upload.withMap();
    expect(w['path'], 'build/windows/x64/runner/Debug/');
    expect(w['path'], isNot(contains('*')));
    expect(w['path'], isNot(contains('!')));
    expect(w['path'], isNot(contains('.exe')));
    expect(w['path'], isNot(contains('|')));
    // A multi-line path list would show up as a second key-less line.
    expect(
      upload.lines.where((l) => l.contains('Debug')),
      hasLength(1),
      reason: 'one mention of the folder',
    );
  });

  test('the folder matches the build mode: a debug build, and no release '
      'build in the job', () {
    final builds = [
      for (final s in windows)
        if ((s.key('run') ?? '').startsWith('flutter build windows'))
          s.key('run')!,
    ];
    expect(builds, ['flutter build windows --debug']);
    expect(upload.withMap()['path'], contains('/Debug/'));
  });

  test('the name carries the full commit SHA and nothing that can collide '
      'across runs', () {
    final name = upload.withMap()['name'];
    expect(name, r'kusunga-windows-debug-${{ github.sha }}');
    expect(upload.withMap().containsKey('overwrite'), isFalse);
  });

  test('a missing build fails the step, and hidden files are not widened', () {
    final w = upload.withMap();
    expect(w['if-no-files-found'], 'error');
    // Only these inputs are set; a new one (include-hidden-files, overwrite,
    // compression-level 0...) is a deliberate change that needs a new test.
    expect(w.keys.toSet(), {
      'name',
      'path',
      'retention-days',
      'if-no-files-found',
    });
  });

  test('the token stays read-only and the workflow adds no secrets to a '
      'public artifact', () {
    final yaml = readSource('.github/workflows/check.yml');
    expect(
      RegExp(
        r'^permissions:\n  contents: read\n',
        multiLine: true,
      ).hasMatch(yaml),
      isTrue,
    );
    expect(yaml, isNot(contains('actions: write')));
    expect(yaml, isNot(contains('secrets.')));
  });
}
