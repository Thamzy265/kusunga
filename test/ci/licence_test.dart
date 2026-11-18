import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards for the licence (PM decision D8, GPL-3.0): the licence file stays
/// the unchanged GNU text and the README keeps the licence notice.
void main() {
  test('LICENSE is the GNU GPL v3 text', () {
    final file = File('LICENSE');
    expect(file.existsSync(), isTrue, reason: 'LICENSE is missing');
    final text = file.readAsStringSync().trimLeft();
    expect(text, startsWith('GNU GENERAL PUBLIC LICENSE'));
    expect(text, contains('Version 3, 29 June 2007'));
  });

  test('README states the licence, the copyright and points to LICENSE', () {
    final readme = File('README.md').readAsStringSync();
    expect(readme, contains('Kusunga is licensed under the GNU GPL v3.0'));
    expect(readme, contains('Copyright (C) 2026 William Nasoni'));
    expect(readme, contains('LICENSE'));
  });
}
