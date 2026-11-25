// M1.10c tester: the developer relaxed two licence guards so a row whose first
// cell says "(transitive" is accepted while the package is still in
// pubspec.lock. A relaxation like that can be used to hide a stale row, so
// this pins its limits: exactly the packages that ship through window_manager
// and tray_manager, each really transitive in the lock, each at the locked
// version, and none of them a direct dependency.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_text.dart';

Map<String, ({String version, String dependency})> _lock() {
  final out = <String, ({String version, String dependency})>{};
  final text = readSource('pubspec.lock');
  final entry = RegExp(r'^  ([a-z0-9_]+):\n((?:    .*\n)+)', multiLine: true);
  for (final m in entry.allMatches(text)) {
    final body = m.group(2)!;
    out[m.group(1)!] = (
      version: RegExp(r'version: "([^"]+)"').firstMatch(body)!.group(1)!,
      dependency: RegExp(
        r'dependency: "?([^"\n]+)"?',
      ).firstMatch(body)!.group(1)!,
    );
  }
  return out;
}

/// Every table row of docs/licences.md whose first cell says "(transitive":
/// package name -> version cell.
Map<String, String> _transitiveRows() => {
  for (final line in readSource('docs/licences.md').split('\n'))
    if (line.startsWith('| ') && line.split('|')[1].contains('(transitive'))
      line.split('|')[1].trim().split(' ').first: line.split('|')[2].trim(),
};

void main() {
  test('the "(transitive" rows are exactly nativeapi, nativeapi_flutter and '
      'cnativeapi', () {
    expect(_transitiveRows().keys.toSet(), {
      'nativeapi',
      'nativeapi_flutter',
      'cnativeapi',
    });
  });

  test('each "(transitive" row is at the locked version and the lock marks '
      'it transitive, so a direct dependency cannot hide behind the word', () {
    final lock = _lock();
    for (final MapEntry(key: name, value: version)
        in _transitiveRows().entries) {
      expect(lock, contains(name), reason: '$name is not in pubspec.lock');
      expect(version, lock[name]!.version, reason: '$name version');
      expect(lock[name]!.dependency, 'transitive', reason: name);
    }
  });

  test('the three native packages come in through window_manager and '
      'tray_manager at one version', () {
    final lock = _lock();
    final versions = {
      for (final n in ['nativeapi', 'nativeapi_flutter', 'cnativeapi'])
        lock[n]!.version,
    };
    expect(versions, hasLength(1), reason: 'the three drifted apart');
    expect(lock['window_manager']!.dependency, 'direct main');
    expect(lock['tray_manager']!.dependency, 'direct main');
  });

  test('the packages window_manager and tray_manager 0.5.x pulled in are '
      'neither locked nor in the table', () {
    final lock = _lock();
    final rows = readSource('docs/licences.md');
    for (final gone in ['menu_base', 'screen_retriever', 'shortid']) {
      expect(lock, isNot(contains(gone)), reason: gone);
      expect(rows, isNot(contains('| $gone ')), reason: '$gone has a row');
    }
  });

  test('the transitive rule does not reach other packages: every other '
      'package row is a direct dependency', () {
    final direct = {
      for (final e in _lock().entries)
        if (e.value.dependency.startsWith('direct')) e.key,
    };
    final rows = <String>{
      for (final l in File('docs/licences.md').readAsLinesSync())
        if (l.startsWith('| ') && RegExp(r'^\| [a-z0-9_]+ \|').hasMatch(l))
          l.split('|')[1].trim(),
    };
    final transitive = _transitiveRows().keys.toSet();
    expect(
      rows.difference(direct).difference(transitive).difference({'flutter'}),
      isEmpty,
    );
  });
}
