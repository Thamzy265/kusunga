import '../history/clip_classifier.dart';
import '../history/clip_item.dart';
import '../history/history_store.dart' show checkContent;

/// What a snippet is. Shown as an icon and a word; stored as [name].
enum SnippetType {
  phone('Phone'),
  email('Email'),
  link('Link'),
  address('Address'),
  other('Other');

  const SnippetType(this.label);

  /// The word the user sees (UI spec, "Copy").
  final String label;

  static SnippetType fromName(String name) =>
      values.firstWhere((t) => t.name == name);
}

/// One row of the snippet list. Like a history item, it holds only a preview
/// of long text; `SnippetStore.contentOf` has the whole text.
class SnippetItem {
  const SnippetItem({
    required this.id,
    required this.name,
    required this.type,
    required this.preview,
    required this.isTruncated,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final SnippetType type;
  final String preview;
  final bool isTruncated;

  /// 0 for the first snippet, then 1, 2, ... with no gaps.
  final int position;

  /// Unix milliseconds.
  final int createdAt;
  final int updatedAt;
}

/// A whole snippet, kept in memory only while it is deleted, so that Undo can
/// put it back where it was.
class SnippetRecord {
  const SnippetRecord({
    required this.name,
    required this.content,
    required this.type,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  final String name;
  final String content;
  final SnippetType type;
  final int position;
  final int createdAt;
  final int updatedAt;
}

/// The store already keeps the most snippets it may (1,000).
class SnippetCapReached implements Exception {
  @override
  String toString() => 'SnippetCapReached';
}

/// Longest name, in characters (code points, as SQLite counts them).
const maxSnippetNameLength = 100;

/// Longest suggested name when a history item is pinned.
const pinNameLength = 40;

final _lineBreaks = RegExp(r'[\r\n\u2028\u2029]+');

/// A name is one line: line breaks become one space, NUL is removed (a name is
/// a label, never pasted), and the ends are trimmed.
String normaliseName(String raw) =>
    raw.replaceAll('\u0000', '').replaceAll(_lineBreaks, ' ').trim();

/// What is wrong with a snippet the user wants to save.
enum SnippetProblem { emptyName, longName, emptyContent, longContent }

/// The problems with [name] (already normalised) and [content]. Content is
/// "empty" when it is only white space, as for history.
Set<SnippetProblem> checkSnippet(String name, String content) => {
  if (name.trim().isEmpty) SnippetProblem.emptyName,
  if (name.runes.length > maxSnippetNameLength) SnippetProblem.longName,
  if (content.trim().isEmpty) SnippetProblem.emptyContent,
  if (isOverCap(content)) SnippetProblem.longContent,
};

/// What the stores accept; anything else is an [ArgumentError].
void checkSnippetFields(String name, String content) {
  if (name.isEmpty ||
      name.runes.length > maxSnippetNameLength ||
      name.contains(_lineBreaks) ||
      name.startsWith('\u0000')) {
    throw ArgumentError.value(name.length, 'name.length');
  }
  checkContent(content);
}

final _email = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$');
final _phoneChars = RegExp(r'^\+?[0-9 ().-]+$');
final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A suggestion for the type, from the content. Only a suggestion: the user's
/// choice always wins. Addresses are never guessed.
SnippetType suggestType(String content) {
  final text = content.trim();
  if (text.isEmpty) return SnippetType.other;
  if (classify(text) == ClipKind.link) return SnippetType.link;
  if (_email.hasMatch(text)) return SnippetType.email;
  if (_phoneChars.hasMatch(text) && !_date.hasMatch(text)) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digits >= 7 && digits <= 15) return SnippetType.phone;
  }
  return SnippetType.other;
}

/// The suggested name for a pinned history item: its first line that is not
/// empty, cut to 40 characters.
String pinName(String content) {
  for (final line in content.split(_lineBreaks)) {
    final name = normaliseName(line);
    if (name.isEmpty) continue;
    final runes = name.runes.toList();
    if (runes.length <= pinNameLength) return name;
    return String.fromCharCodes(runes.take(pinNameLength)).trimRight();
  }
  return '';
}
