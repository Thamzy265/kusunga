import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'source_text.dart';

void main() {
  test('readSource gives LF line endings whatever the checkout used', () {
    final dir = Directory.systemTemp.createTempSync('kusunga_src_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final crlf = File(p.join(dir.path, 'a.xcconfig'))
      ..writeAsStringSync('#include? "Local.xcconfig"\r\nA = 1\r\n');
    final lf = File(p.join(dir.path, 'b.xcconfig'))
      ..writeAsStringSync('#include? "Local.xcconfig"\nA = 1\n');
    expect(readSource(crlf.path), '#include? "Local.xcconfig"\nA = 1\n');
    expect(readSource(lf.path), readSource(crlf.path));
    expect(
      readSource(crlf.path).split('\n').first,
      '#include? "Local.xcconfig"',
    );
  });
}
