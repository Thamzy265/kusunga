import 'dart:convert';

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

  /// Longest text the store accepts: 1 MiB of UTF-8 bytes.
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

/// The first [units] UTF-16 units of [text], never ending in half a
/// surrogate pair.
String cutUnits(String text, int units) {
  if (text.length <= units) return text;
  var end = units;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return text.substring(0, end);
}

/// The part of [content] shown in the list.
String previewOf(String content) => cutUnits(content, ClipItem.previewLength);

/// True if [text] is over the 1 MiB UTF-8 cap. A text with more UTF-16 units
/// than the cap has at least that many bytes, so it is not even encoded.
bool isOverCap(String text) =>
    text.length > ClipItem.maxContentLength ||
    utf8.encode(text).length > ClipItem.maxContentLength;
