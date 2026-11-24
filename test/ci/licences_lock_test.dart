// M1.10a (tester): docs/licences.md lists every direct dependency with the
// version in pubspec.lock. Nothing checked that, so a package added by hand
// (material_ui, M1.10a) or bumped (M1.10b) could leave the table stale.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Direct dependencies (not dev, not the SDK packages) from pubspec.yaml.
List<String> directDeps() {
  final out = <String>[];
  var inDeps = false;
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    if (RegExp(r'^\S').hasMatch(line)) {
      inDeps = line.startsWith('dependencies:');
    }
    if (!inDeps) continue;
    final m = RegExp(r'^  ([a-z0-9_]+):\s*(\S.*)?$').firstMatch(line);
    if (m != null && m.group(1) != 'flutter') out.add(m.group(1)!);
  }
  return out;
}

/// package -> version in pubspec.lock.
Map<String, String> locked() {
  final out = <String, String>{};
  String? name;
  for (final line in File('pubspec.lock').readAsLinesSync()) {
    final n = RegExp(r'^  ([a-z0-9_]+):$').firstMatch(line);
    if (n != null) name = n.group(1);
    final v = RegExp(r'^    version: "([^"]+)"').firstMatch(line);
    if (v != null && name != null) out[name] = v.group(1)!;
  }
  return out;
}

/// first cell -> version cell of each table row in docs/licences.md.
Map<String, String> rows() {
  final out = <String, String>{};
  for (final l in File('docs/licences.md').readAsLinesSync()) {
    if (!l.startsWith('| ')) continue;
    final c = l.split('|').map((s) => s.trim()).toList();
    if (c.length > 3) out.putIfAbsent(c[1].split(' ').first, () => c[2]);
  }
  return out;
}

void main() {
  test('the dependency list is read (guards against an empty pass)', () {
    expect(directDeps(), containsAll(['material_ui', 'sqlite3', 'path']));
    expect(locked()['material_ui'], isNotNull);
  });

  test('every direct dependency has a docs/licences.md row at the version in '
      'pubspec.lock', () {
    final lock = locked();
    final table = rows();
    final problems = <String>[];
    for (final d in directDeps()) {
      if (!table.containsKey(d)) {
        problems.add('$d: no row in docs/licences.md');
      } else if (table[d] != lock[d]) {
        problems.add('$d: licences.md ${table[d]} vs lock ${lock[d]}');
      }
    }
    expect(problems, isEmpty);
  });

  test(
    'every package row in docs/licences.md is still a direct dependency',
    () {
      final direct = directDeps().toSet();
      final lock = locked();
      // M1.10c: a transitive package that ships (nativeapi and friends,
      // ADR 0009) has a row that says "(transitive"; it is not stale.
      final transitive = {
        for (final l in File('docs/licences.md').readAsLinesSync())
          if (l.startsWith('| ') && l.split('|')[1].contains('(transitive'))
            l.split('|')[1].trim().split(' ').first,
      };
      final stale = [
        for (final k in rows().keys)
          if (lock.containsKey(k) &&
              !direct.contains(k) &&
              !transitive.contains(k))
            k,
      ];
      expect(stale, isEmpty);
      // Each transitive row is at the locked version.
      for (final t in transitive) {
        expect(rows()[t], lock[t], reason: '$t row vs pubspec.lock');
      }
    },
  );
}
