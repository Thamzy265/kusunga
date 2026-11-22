import 'dart:io';

/// Reads a source file for a guard test with LF line endings, whatever the
/// checkout used: Git on Windows can check text files out with CRLF, and a
/// guard that splits on '\n' would then see a trailing '\r'.
String readSource(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
