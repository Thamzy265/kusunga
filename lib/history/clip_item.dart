/// What kind of text an item is. Images, files and rich text are not kept.
enum ClipKind {
  text,
  link;

  static ClipKind fromName(String name) =>
      ClipKind.values.firstWhere((k) => k.name == name);
}

/// One row of the history list. Holds only a preview of long text, so a list
/// of 5,000 items never loads 5,000 megabytes. Use `HistoryStore.contentOf`
/// for the whole text.
class ClipItem {
  const ClipItem({
    required this.id,
    required this.kind,
    required this.preview,
    required this.isTruncated,
    required this.createdAt,
    required this.lastCopiedAt,
  });

  /// Longest text kept in the list view, in UTF-16 code units.
  static const previewLength = 2000;

  /// Longest text the store accepts (1 MB of characters).
  static const maxContentLength = 1048576;

  final int id;
  final ClipKind kind;
  final String preview;
  final bool isTruncated;

  /// Unix milliseconds.
  final int createdAt;
  final int lastCopiedAt;
}

/// A whole item, kept only while it is removed so that Undo can put it back.
class ClipRecord {
  const ClipRecord({
    required this.content,
    required this.kind,
    required this.createdAt,
    required this.lastCopiedAt,
  });

  final String content;
  final ClipKind kind;
  final int createdAt;
  final int lastCopiedAt;
}

/// The part of [content] shown in the list. Never cuts a surrogate pair.
String previewOf(String content) {
  if (content.length <= ClipItem.previewLength) return content;
  var end = ClipItem.previewLength;
  final last = content.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return content.substring(0, end);
}
