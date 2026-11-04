import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';

/// The macOS unified log accepts only a closed list of code names
/// (macos/Runner/DiagLog.swift). It must hold every Dart log code and every
/// code the native sources log, or that diagnostic is silently dropped.
void main() {
  final swift = File('macos/Runner/DiagLog.swift').readAsStringSync();
  final block = swift.substring(
    swift.indexOf('static let knownCodes'),
    swift.indexOf('#if DEBUG'),
  );
  final known = {
    for (final m in RegExp(r'"([A-Za-z0-9]+)"').allMatches(block)) m.group(1)!,
  };

  test('every Dart log code is on the Swift list', () {
    for (final c in LogCode.values) {
      expect(known, contains(c.name));
    }
  });

  test('every code the native sources log is on the list', () {
    final used = <String>{};
    for (final f in Directory('macos/Runner').listSync().whereType<File>()) {
      if (!f.path.endsWith('.swift')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(
        r'(?:DiagLog\.log|diag)\(\s*"([A-Za-z0-9]+)"',
      ).allMatches(src)) {
        used.add(m.group(1)!);
      }
    }
    expect(used, isNotEmpty);
    for (final c in used) {
      expect(known, contains(c), reason: c);
    }
  });

  test('nothing on the list looks like content: camelCase names only', () {
    for (final c in known) {
      expect(RegExp(r'^[a-z][a-zA-Z]{3,38}$').hasMatch(c), isTrue, reason: c);
    }
  });
}
