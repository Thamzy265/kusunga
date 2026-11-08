import 'clip_item.dart';

/// Where clipboard history is kept. Calls are synchronous: the database is
/// local, and one copy is one small transaction.
abstract interface class HistoryStore {
  static const defaultLimit = 200;
  static const minLimit = 10;
  static const maxLimit = 5000;

  /// Settings kept next to the history: the picker shortcut and the paste
  /// mode (schema version 2), and the typed-shortcuts switch, "0" or "1"
  /// (version 4). Not personal data.
  static const storedSettingKeys = {
    'picker_shortcut',
    'paste_mode',
    'typed_shortcuts_on',
  };
  static const maxSettingLength = 64;

  /// How many newest items are kept.
  int get limit;
  int get count;

  /// Newest first.
  List<ClipItem> list();

  /// The whole text of an item, or null if it is gone.
  String? contentOf(int id);

  /// Saves [content], or moves it to the top if it is already there, then
  /// trims to [limit]. All of it is one transaction. Returns the item id.
  /// Throws [ArgumentError] for empty text or text over 1 MiB of UTF-8.
  int insertOrBump(String content, ClipKind kind, int nowMs);

  /// Moves the item with exactly this text to the top and returns true, or
  /// returns false (and saves nothing) if it is not saved. Used when Kusunga
  /// itself put the text on the clipboard.
  bool bumpIfPresent(String content, int nowMs);

  /// A saved setting (see [storedSettingKeys]), or null if never saved.
  /// Throws [ArgumentError] for any other key.
  String? readSetting(String key);

  /// Saves a setting. Throws [ArgumentError] for an unknown key, or a value
  /// that is empty or over [maxSettingLength] characters.
  void writeSetting(String key, String value);

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
  if (content.isEmpty || isOverCap(content)) {
    throw ArgumentError.value(content.length, 'content.length');
  }
}

void checkLimit(int limit) {
  if (limit < HistoryStore.minLimit || limit > HistoryStore.maxLimit) {
    throw ArgumentError.value(limit, 'limit');
  }
}

void checkSettingKey(String key) {
  if (!HistoryStore.storedSettingKeys.contains(key)) {
    throw ArgumentError.value(key, 'key');
  }
}

void checkSetting(String key, String value) {
  checkSettingKey(key);
  if (value.isEmpty || value.length > HistoryStore.maxSettingLength) {
    throw ArgumentError.value(value.length, 'value.length');
  }
}
