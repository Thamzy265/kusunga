/// Which lines of a Swift source the compiler keeps only in a Debug build:
/// those inside an `#if DEBUG` block (nested `#if` blocks counted; the
/// `#else` or `#elseif` of an `#if DEBUG` is outside). Shared by the CI
/// guards that keep Debug-only code out of Release
/// (test/ci/typed_shortcut_guards_test.dart,
/// test/ci/data_profile_guard_test.dart) and their own tests
/// (test/ci/typed_shortcut_synthetic_edge_test.dart), so they can't drift.
///
/// Conservative: only a plain `#if DEBUG` counts. Any other condition
/// (`#if DEBUG || true`, `#if !DEBUG`, `#elseif DEBUG`) is treated as code
/// that may be in Release.
/// `#if DEBUG` and nothing after it but spaces or a line comment (G1:
/// `#if DEBUG || true` is true in Release too).
final _bareDebug = RegExp(r'^#if\s+DEBUG\s*(//.*)?$');

List<(String, bool)> swiftDebugLines(String src) {
  final stack = <bool>[]; // true: this level is a DEBUG branch
  final out = <(String, bool)>[];
  for (final raw in src.split('\n')) {
    final line = raw.trim();
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
