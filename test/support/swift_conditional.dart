/// Which lines of a Swift source the compiler keeps only in a Debug build:
/// those inside an `#if DEBUG` block (nested `#if` blocks counted; the
/// `#else` or `#elseif` of an `#if DEBUG` is outside). Shared by the CI
/// guards that keep Debug-only code out of Release
/// (test/ci/typed_shortcut_guards_test.dart,
/// test/ci/data_profile_guard_test.dart) and their own tests
/// (test/ci/typed_shortcut_synthetic_edge_test.dart), so they can't drift.
///
/// Comments and string literals are never read as directives (G2).
///
/// Conservative: only a plain `#if DEBUG` counts. Any other condition
/// (`#if DEBUG || true`, `#if !DEBUG`, `#elseif DEBUG`) is treated as code
/// that may be in Release.
/// `#if DEBUG` and nothing after it but spaces or a line comment (G1:
/// `#if DEBUG || true` is true in Release too).
final _bareDebug = RegExp(r'^#if\s+DEBUG\s*(//.*)?$');

/// [src] twice, line for line: with comments blanked (`code`), and with
/// comments and string contents blanked (`bare`). Swift block comments nest;
/// `"..."` and `"""..."""` strings are handled (raw `#"..."#` strings are
/// not: none in these sources). G2: a `#if DEBUG` line inside a comment or
/// a string is not a directive.
({List<String> code, List<String> bare}) _strip(String src) {
  final code = StringBuffer();
  final bare = StringBuffer();
  var i = 0;
  var depth = 0; // block comment nesting
  var lineComment = false;
  String? quote; // '"' or '"""' while inside a string
  void keep(String c, {bool inString = false}) {
    code.write(c);
    bare.write(inString && c != '\n' ? ' ' : c);
  }

  void blank(String c) {
    final out = c == '\n' ? '\n' : ' ';
    code.write(out);
    bare.write(out);
  }

  bool at(String t) => src.startsWith(t, i);
  while (i < src.length) {
    final c = src[i];
    if (lineComment) {
      if (c == '\n') {
        lineComment = false;
        keep(c);
      } else {
        blank(c);
      }
      i++;
    } else if (depth > 0) {
      if (at('/*')) {
        depth++;
        blank('/');
        blank('*');
        i += 2;
      } else if (at('*/')) {
        depth--;
        blank('*');
        blank('/');
        i += 2;
      } else {
        blank(c);
        i++;
      }
    } else if (quote != null) {
      if (c == '\\' && i + 1 < src.length) {
        keep(c, inString: true);
        keep(src[i + 1], inString: true);
        i += 2;
      } else if (at(quote)) {
        for (final q in quote.split('')) {
          keep(q);
        }
        i += quote.length;
        quote = null;
      } else {
        keep(c, inString: true);
        i++;
      }
    } else if (at('//')) {
      lineComment = true;
      blank(c);
      i++;
    } else if (at('/*')) {
      depth = 1;
      blank('/');
      blank('*');
      i += 2;
    } else if (at('"""')) {
      quote = '"""';
      for (var k = 0; k < 3; k++) {
        keep('"');
      }
      i += 3;
    } else if (c == '"') {
      quote = '"';
      keep(c);
      i++;
    } else {
      keep(c);
      i++;
    }
  }
  return (code: code.toString().split('\n'), bare: bare.toString().split('\n'));
}

/// Each line of [src], without its comments (string literals kept, so a
/// guard can still look for an argument string), with whether the compiler
/// keeps it only in a Debug build.
List<(String, bool)> swiftDebugLines(String src) {
  final stack = <bool>[]; // true: this level is a DEBUG branch
  final out = <(String, bool)>[];
  final (:code, :bare) = _strip(src);
  for (var n = 0; n < code.length; n++) {
    final raw = code[n];
    final line = bare[n].trim();
    if (line.startsWith('#if')) {
      stack.add(_bareDebug.hasMatch(line));
      out.add((raw, stack.contains(true)));
      continue;
    }
    if (line.startsWith('#else') || line.startsWith('#elseif')) {
      if (stack.isNotEmpty) stack[stack.length - 1] = false;
      out.add((raw, stack.contains(true)));
      continue;
    }
    if (line.startsWith('#endif')) {
      out.add((raw, stack.contains(true)));
      if (stack.isNotEmpty) stack.removeLast();
      continue;
    }
    out.add((raw, stack.contains(true)));
  }
  return out;
}

/// [src] without the lines inside `#if DEBUG` blocks.
String swiftOutsideDebug(String src) => [
  for (final (line, inDebug) in swiftDebugLines(src))
    if (!inDebug) line,
].join('\n');
