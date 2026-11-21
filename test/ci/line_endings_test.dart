import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Windows CI green (group D): Git on Windows (core.autocrlf=true) checked
/// text files out with CRLF, and guard tests that split on '\n' failed. Every
/// text file is checked out with LF on every OS; LICENSE stays unconverted.
void main() {
  Map<String, String> attrs(String attr, List<String> paths) {
    final r = Process.runSync('git', ['check-attr', attr, '--', ...paths]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return {
      for (final line in (r.stdout as String).trim().split('\n'))
        line.split(': ').first: line.split(': ').last.trim(),
    };
  }

  const samples = [
    'lib/main.dart',
    'test/ci/mac_signing_and_diag_guards_test.dart',
    'macos/Runner/Configs/AppInfo.xcconfig',
    'macos/Runner/PasteFlow.swift',
    'windows/runner/main.cpp',
    'docs/PLAN.md',
  ];

  test('text files are checked out with LF on every OS', () {
    for (final f in samples) {
      expect(File(f).existsSync(), isTrue, reason: '$f is missing');
    }
    expect(attrs('text', samples).values.toSet(), {'auto'});
    expect(attrs('eol', samples).values.toSet(), {'lf'});
  });

  test('LICENSE is still never converted (the rule is above it)', () {
    expect(attrs('text', ['LICENSE'])['LICENSE'], 'unset');
    final lines = File(
      '.gitattributes',
    ).readAsLinesSync().map((l) => l.trim()).toList();
    final all = lines.indexOf('* text=auto eol=lf');
    expect(all, isNonNegative, reason: 'the LF rule is missing');
    expect(all, lessThan(lines.indexOf('LICENSE -text')));
  });
}
