import '../data/export_format.dart';
import 'clip_item.dart';

/// Auto-delete (M1.7, schema version 6): "0" never, or "1", "7" or "30"
/// days since an item was last copied. Any other value counts as never.
const historyExpirySetting = 'history_expiry_days';

/// The only auto-delete values, in days; 0 is never.
const historyExpiryChoices = [0, 1, 7, 30];

/// Where clipboard history is kept. Calls are synchronous: the database is
/// local, and one copy is one small transaction.
abstract interface class HistoryStore {
  static const defaultLimit = 200;
  static const minLimit = 10;
  static const maxLimit = 5000;

  /// Settings kept next to the history: the picker shortcut and the paste
  /// mode (schema version 2), and the typed-shortcuts switch, "0" or "1"
  /// (version 4), and the history pause, "0", "-1" or an end time in ms
  /// (M1.6, `history_paused_until`; the user's choice to stop recording,
  /// kept in the encrypted file like the rest), and auto-delete (M1.7,
  /// version 6, [historyExpirySetting]).
  static const storedSettingKeys = {
    'picker_shortcut',
    'paste_mode',
    'typed_shortcuts_on',
    'history_paused_until',
    historyExpirySetting,
  };
  static const maxSettingLength = 64;

  /// How many newest items are kept.
  int get limit;
  int get count;

  /// Newest first.
  List<ClipItem> list();

  /// Newest first, only items last copied at or after [sinceMs] (M1.7 read
  /// filter: an expired item is never shown, even before the clean-up).
  List<ClipItem> listSince(int sinceMs);

  /// How many items were last copied before [cutoffMs] (and, with
  /// [notBefore], at or after it).
  int countOlderThan(int cutoffMs, {int? notBefore});

  /// Removes every item last copied before [cutoffMs], in one transaction,
  /// and returns how many went. Snippets are never touched.
  int deleteOlderThan(int cutoffMs);

  /// Saves the auto-delete setting ([historyExpiryChoices]) and, with
  /// [deleteBefore], removes the items last copied before it, all in one
  /// transaction: if either fails, neither happens. Returns how many items
  /// went. Throws [ArgumentError] for any other number of days.
  int setExpiryDays(int days, {int? deleteBefore});

  /// The whole text of an item, or null if it is gone (or, with
  /// [notBefore], last copied before it: the M1.7 read filter, so an id
  /// kept from before the item expired gives nothing).
  String? contentOf(int id, {int? notBefore});

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

  /// Every item with its whole text, newest first; with [notBefore], only
  /// items last copied at or after it (the auto-delete read filter). For
  /// export (M1.8).
  List<ClipRecord> records({int? notBefore});

  /// Rebuilds the file so freed pages are gone, not only zeroed (Delete all
  /// history, M1.8 D4 A). Nothing to do in memory.
  void compact();

  /// Adds a checked import file in one write transaction: if anything fails,
  /// nothing changes (M1.8; see `importIntoDatabase`). Throws
  /// [UnsupportedError] where import is not offered (memory only, G2).
  ImportCounts importBundle(
    ExportBundle bundle, {
    required bool applySettings,
    int? notBefore,
    required int nowMs,
  });

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

void checkExpiryDays(int days) {
  if (!historyExpiryChoices.contains(days)) {
    throw ArgumentError.value(days, 'days');
  }
}
