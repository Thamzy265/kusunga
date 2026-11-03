import 'clip_item.dart';

/// Where clipboard history is kept. Calls are synchronous: the database is
/// local, and one copy is one small transaction.
abstract interface class HistoryStore {
  static const defaultLimit = 200;
  static const minLimit = 10;
  static const maxLimit = 5000;

  /// How many newest items are kept.
  int get limit;
  int get count;

  /// Newest first.
  List<ClipItem> list();

  /// The whole text of an item, or null if it is gone.
  String? contentOf(int id);

  /// Saves [content], or moves it to the top if it is already there, then
  /// trims to [limit]. All of it is one transaction. Returns the item id.
  /// Throws [ArgumentError] for empty text or text over 1 MB.
  int insertOrBump(String content, ClipKind kind, int nowMs);

  /// Removes one item and returns it so it can be restored, or null.
  ClipRecord? delete(int id);

  /// Puts a deleted item back with its original times (Undo).
  void restore(ClipRecord record);

  /// Removes everything and returns how many items were removed.
  int clear();

  /// How many items lowering the limit to [newLimit] would delete.
  int countRemovedBy(int newLimit);

  /// Saves the limit and trims, in one transaction. Throws [ArgumentError]
  /// outside 10 to 5,000.
  void setLimit(int newLimit);

  void close();
}

void checkContent(String content) {
  if (content.isEmpty || content.length > ClipItem.maxContentLength) {
    throw ArgumentError.value(content.length, 'content.length');
  }
}

void checkLimit(int limit) {
  if (limit < HistoryStore.minLimit || limit > HistoryStore.maxLimit) {
    throw ArgumentError.value(limit, 'limit');
  }
}
