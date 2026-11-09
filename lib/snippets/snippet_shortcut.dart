/// The rules for a snippet's typed shortcut, such as `;email` (M1.5,
/// `docs/design/typed-shortcuts.md`, "Shortcut rules"):
///  - 2 to 32 characters (code points, as SQLite and the native buffer count
///    them), with no spaces or line breaks;
///  - case-sensitive, so `;Email` and `;email` are different;
///  - unique;
///  - not the start of another shortcut, and no other shortcut is the start
///    of it (PM decision D1 A: a shortcut fires as soon as its last character
///    is typed, so the longer one would never fire).
library;

const minShortcutLength = 2;
const maxShortcutLength = 32;

/// What is wrong with the text of a shortcut on its own.
enum ShortcutProblem {
  /// Under 2 or over 32 characters.
  length,

  /// A space, a tab, a line break, another invisible control character, or
  /// half of a character (a lone UTF-16 surrogate, which the database would
  /// store as U+FFFD).
  spaces,
}

/// A shortcut is "empty" (no shortcut) when the field is empty. Nothing is
/// trimmed: a space the user typed is an error they can see and fix.
String? shortcutOrNull(String? raw) =>
    (raw == null || raw.isEmpty) ? null : raw;

/// The problem with [shortcut] on its own, or null if it is fine.
ShortcutProblem? checkShortcutText(String shortcut) {
  for (final r in shortcut.runes) {
    if (_isSpaceOrControl(r)) return ShortcutProblem.spaces;
  }
  final n = shortcut.runes.length;
  if (n < minShortcutLength || n > maxShortcutLength) {
    return ShortcutProblem.length;
  }
  return null;
}

bool _isSpaceOrControl(int r) =>
    (r >= 0xD800 && r <= 0xDFFF) || // a lone surrogate (T2)
    r < 0x20 ||
    r == 0x20 ||
    r == 0x7F ||
    (r >= 0x80 && r <= 0xA0) ||
    r == 0x1680 ||
    (r >= 0x2000 && r <= 0x200A) ||
    r == 0x2028 ||
    r == 0x2029 ||
    r == 0x202F ||
    r == 0x205F ||
    r == 0x3000;

/// How a new shortcut clashes with one another snippet already has.
enum ShortcutClashKind {
  /// The very same shortcut.
  same,

  /// The other shortcut is the start of the new one (`;em` vs `;email`): the
  /// new one would never fire.
  otherIsStart,

  /// The new shortcut is the start of the other one (`;em` vs `;email`): the
  /// other one would stop firing.
  newIsStart,
}

class ShortcutClash {
  const ShortcutClash({
    required this.kind,
    required this.otherId,
    required this.otherName,
    required this.otherShortcut,
  });

  final ShortcutClashKind kind;
  final int otherId;
  final String otherName;
  final String otherShortcut;
}

/// One snippet that has a shortcut.
typedef ShortcutOwner = ({int id, String name, String shortcut});

/// The first clash of [shortcut] with [others] (the snippet [selfId] itself is
/// skipped), or null.
ShortcutClash? findShortcutClash(
  String shortcut,
  Iterable<ShortcutOwner> others, {
  int? selfId,
}) {
  for (final o in others) {
    if (o.id == selfId) continue;
    final kind = o.shortcut == shortcut
        ? ShortcutClashKind.same
        : shortcut.startsWith(o.shortcut)
        ? ShortcutClashKind.otherIsStart
        : o.shortcut.startsWith(shortcut)
        ? ShortcutClashKind.newIsStart
        : null;
    if (kind != null) {
      return ShortcutClash(
        kind: kind,
        otherId: o.id,
        otherName: o.name,
        otherShortcut: o.shortcut,
      );
    }
  }
  return null;
}

/// What the editor shows under the Shortcut field: a problem with the text,
/// or a clash with another snippet.
class ShortcutIssue {
  const ShortcutIssue.problem(ShortcutProblem this.problem) : clash = null;
  const ShortcutIssue.clash(ShortcutClash this.clash) : problem = null;

  final ShortcutProblem? problem;
  final ShortcutClash? clash;

  @override
  bool operator ==(Object other) =>
      other is ShortcutIssue &&
      other.problem == problem &&
      other.clash?.kind == clash?.kind &&
      other.clash?.otherId == clash?.otherId;

  @override
  int get hashCode => Object.hash(problem, clash?.kind, clash?.otherId);
}

/// The store refused a shortcut that clashes with another snippet's. Nothing
/// was changed.
class ShortcutTaken implements Exception {
  ShortcutTaken(this.clash);
  final ShortcutClash clash;

  // Never the shortcut or the name: exception text can reach a log.
  @override
  String toString() => 'ShortcutTaken(${clash.kind.name})';
}

/// The store accepts only a valid shortcut (or none); anything else is an
/// [ArgumentError] that carries no text.
void checkShortcutField(String? shortcut) {
  if (shortcut == null) return;
  final problem = checkShortcutText(shortcut);
  if (problem != null) throw ArgumentError.value(problem.name, 'shortcut');
}
