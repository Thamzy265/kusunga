// M1.10a (tester): Flutter 3.50's `pub get` writes `analyzer: exclude:` into
// analysis_options.yaml. The analyzer then skips those folders, so a Dart file
// of ours that lands in one would never be analysed (`flutter analyze` would
// still say "No issues found!"). These tests keep the list small and keep
// every project Dart file out of it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The entries under `analyzer:` -> `exclude:` in analysis_options.yaml.
List<String> excludes() {
  final lines = File('analysis_options.yaml').readAsLinesSync();
  final out = <String>[];
  var inAnalyzer = false;
  var inExclude = false;
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      inAnalyzer = line.startsWith('analyzer:');
      inExclude = false;
      continue;
    }
    if (!inAnalyzer) continue;
    if (indent == 2) {
      inExclude = line.trim().startsWith('exclude:');
      continue;
    }
    if (inExclude && line.trim().startsWith('- ')) {
      out.add(
        line
            .trim()
            .substring(2)
            .trim()
            .replaceAll(RegExp('^["\']|["\']\$'), ''),
      );
    }
  }
  return out;
}

/// The folder a `folder/**` glob covers, or null for any other shape.
String? folderOf(String glob) {
  final m = RegExp(r'^([A-Za-z0-9_.-]+)/\*\*$').firstMatch(glob);
  return m?.group(1);
}

/// [listed] as a '/' path relative to the project root, the same on every OS
/// (Windows lists `.\lib\app.dart`). [context] is the path style; tests pass
/// `p.windows`.
String projectPath(String listed, [p.Context? context]) {
  final c = context ?? p.context;
  return p.posix.joinAll(c.split(c.relative(listed)));
}

/// The project .dart files among [listed] (default: every file under the
/// project root), as [projectPath]s, skipping generated and cache folders.
List<String> projectDartFiles({Iterable<String>? listed, p.Context? context}) {
  listed ??= [
    for (final e in Directory(
      '.',
    ).listSync(recursive: true, followLinks: false))
      if (e is File) e.path,
  ];
  return [
    for (final path in listed)
      if (path.endsWith('.dart')) projectPath(path, context),
  ].where((path) {
    final parts = path.split('/');
    return !parts.contains('.dart_tool') &&
        !parts.contains('.git') &&
        !parts.contains('build') &&
        !parts.contains('.symlinks') &&
        !parts.contains('ephemeral');
  }).toList();
}

/// The [files] (project paths) that sit inside one of the [folders].
List<String> hiddenIn(Set<String> folders, Iterable<String> files) => [
  for (final f in files)
    if (folders.contains(f.split('/').first)) f,
];

void main() {
  test('the exclude list is read, and is exactly the three generated or '
      'native folders', () {
    expect(excludes(), unorderedEquals(['build/**', 'windows/**', 'macos/**']));
  });

  test('every exclude is a plain `folder/**` and none covers code we '
      'write (lib, test, tool, or the whole repo)', () {
    const ours = {'lib', 'test', 'tool', 'integration_test', 'bin', 'assets'};
    for (final glob in excludes()) {
      final folder = folderOf(glob);
      expect(folder, isNotNull, reason: '"$glob" is not a folder/** glob');
      expect(ours, isNot(contains(folder)), reason: '"$glob" hides our code');
    }
  });

  test('no project Dart file is inside an excluded folder', () {
    final folders = excludes().map(folderOf).whereType<String>().toSet();
    final hidden = hiddenIn(folders, projectDartFiles());
    expect(hidden, isEmpty, reason: 'analyzer would skip: $hidden');
  });

  test('the check sees our code: lib and test Dart files exist outside every '
      'excluded folder', () {
    final folders = excludes().map(folderOf).whereType<String>().toSet();
    final files = projectDartFiles();
    expect(files.where((f) => f.startsWith('lib/')), isNotEmpty);
    expect(files.where((f) => f.startsWith('test/')), isNotEmpty);
    expect(folders.intersection({'lib', 'test'}), isEmpty);
  });

  // R1 (review M1.10a): Windows lists `.\lib\app.dart`, so the paths must be
  // made '/' paths from the project root before they are checked. p.windows
  // runs these on every OS.
  test('a Windows path from listSync becomes a / path from the project '
      'root', () {
    expect(projectPath(r'.\lib\main.dart', p.windows), 'lib/main.dart');
    expect(
      projectPath(r'.\windows\runner\x.dart', p.windows),
      'windows/runner/x.dart',
    );
    expect(projectPath('./lib/main.dart', p.posix), 'lib/main.dart');
  });

  test('on Windows paths, a Dart file under windows\\ is caught as hidden, '
      'lib and test are found, and build and .dart_tool are skipped', () {
    final files = projectDartFiles(
      listed: [
        r'.\lib\main.dart',
        r'.\test\a_test.dart',
        r'.\windows\x.dart',
        r'.\build\gen.dart',
        r'.\.dart_tool\flutter_build\x.dart',
        r'.\windows\flutter\ephemeral\y.dart',
        r'.\lib\notes.txt',
      ],
      context: p.windows,
    );
    expect(files, ['lib/main.dart', 'test/a_test.dart', 'windows/x.dart']);
    expect(hiddenIn({'build', 'windows', 'macos'}, files), ['windows/x.dart']);
  });
}
