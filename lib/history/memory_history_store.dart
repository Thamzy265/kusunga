import 'clip_item.dart';
import 'history_store.dart';

/// History kept in memory only. Used when the keychain cannot be reached:
/// nothing is ever written to disk, so nothing survives a quit.
class MemoryHistoryStore implements HistoryStore {
  final _items = <_Entry>[]; // newest first
  var _limit = HistoryStore.defaultLimit;
  var _nextId = 1;

  @override
  int get limit => _limit;

  @override
  int get count => _items.length;

  @override
  List<ClipItem> list() => [
    for (final e in _items)
      ClipItem(
        id: e.id,
        kind: e.record.kind,
        preview: previewOf(e.record.content),
        isTruncated: e.record.content.length > ClipItem.previewLength,
        createdAt: e.record.createdAt,
        lastCopiedAt: e.record.lastCopiedAt,
      ),
  ];

  @override
  List<ClipItem> listSince(int sinceMs) => [
    for (final i in list())
      if (i.lastCopiedAt >= sinceMs) i,
  ];

  @override
  int countOlderThan(int cutoffMs, {int? notBefore}) => _items
      .where(
        (e) =>
            e.record.lastCopiedAt < cutoffMs &&
            (notBefore == null || e.record.lastCopiedAt >= notBefore),
      )
      .length;

  @override
  int deleteOlderThan(int cutoffMs) {
    final before = _items.length;
    _items.removeWhere((e) => e.record.lastCopiedAt < cutoffMs);
    return before - _items.length;
  }

  @override
  int setExpiryDays(int days, {int? deleteBefore}) {
    checkExpiryDays(days);
    _settings[historyExpirySetting] = '$days';
    return deleteBefore == null ? 0 : deleteOlderThan(deleteBefore);
  }

  @override
  String? contentOf(int id, {int? notBefore}) {
    for (final e in _items) {
      if (e.id != id) continue;
      final kept = notBefore == null || e.record.lastCopiedAt >= notBefore;
      return kept ? e.record.content : null;
    }
    return null;
  }

  @override
  int insertOrBump(String content, ClipKind kind, int nowMs) {
    checkContent(content);
    final ts = _nextTimestamp(nowMs);
    final i = _items.indexWhere((e) => e.record.content == content);
    final int id;
    if (i >= 0) {
      final old = _items.removeAt(i);
      id = old.id;
      _items.insert(
        0,
        _Entry(
          id,
          ClipRecord(
            content: content,
            kind: kind,
            createdAt: old.record.createdAt,
            lastCopiedAt: ts,
          ),
        ),
      );
    } else {
      id = _nextId++;
      _items.insert(
        0,
        _Entry(
          id,
          ClipRecord(
            content: content,
            kind: kind,
            createdAt: ts,
            lastCopiedAt: ts,
          ),
        ),
      );
    }
    _trim();
    return id;
  }

  /// Strictly newer than every item already kept, so order never ties.
  int _nextTimestamp(int nowMs) {
    if (_items.isEmpty) return nowMs;
    final newest = _items.first.record.lastCopiedAt;
    return nowMs > newest ? nowMs : newest + 1;
  }

  @override
  bool bumpIfPresent(String content, int nowMs) {
    final i = _items.indexWhere((e) => e.record.content == content);
    if (i < 0) return false;
    final old = _items.removeAt(i);
    _items.insert(
      0,
      _Entry(
        old.id,
        ClipRecord(
          content: old.record.content,
          kind: old.record.kind,
          createdAt: old.record.createdAt,
          lastCopiedAt: _nextTimestamp(nowMs),
        ),
      ),
    );
    return true;
  }

  /// Auto-delete starts at Never in a memory-only session: it is usually an
  /// existing user whose keychain can't be reached, and nothing here
  /// outlives the session anyway.
  final _settings = <String, String>{historyExpirySetting: '0'};

  @override
  String? readSetting(String key) {
    checkSettingKey(key);
    return _settings[key];
  }

  @override
  void writeSetting(String key, String value) {
    checkSetting(key, value);
    _settings[key] = value;
  }

  @override
  ClipRecord? delete(int id) {
    final i = _items.indexWhere((e) => e.id == id);
    return i < 0 ? null : _items.removeAt(i).record;
  }

  @override
  void restore(ClipRecord record) {
    checkContent(record.content);
    var merged = record;
    var id = _nextId;
    final i = _items.indexWhere((e) => e.record.content == record.content);
    if (i >= 0) {
      // The same text was copied again meanwhile: keep the newer time and the
      // first time, like the SQLite store.
      final old = _items.removeAt(i);
      id = old.id;
      merged = ClipRecord(
        content: record.content,
        kind: old.record.kind,
        createdAt: old.record.createdAt < record.createdAt
            ? old.record.createdAt
            : record.createdAt,
        lastCopiedAt: old.record.lastCopiedAt > record.lastCopiedAt
            ? old.record.lastCopiedAt
            : record.lastCopiedAt,
      );
    } else {
      _nextId++;
    }
    final at = _items.indexWhere(
      (e) => e.record.lastCopiedAt <= merged.lastCopiedAt,
    );
    _items.insert(at < 0 ? _items.length : at, _Entry(id, merged));
    _trim();
  }

  @override
  int clear() {
    final n = _items.length;
    _items.clear();
    return n;
  }

  @override
  int countRemovedBy(int newLimit) {
    checkLimit(newLimit);
    return _items.length > newLimit ? _items.length - newLimit : 0;
  }

  @override
  void setLimit(int newLimit) {
    checkLimit(newLimit);
    _limit = newLimit;
    _trim();
  }

  void _trim() {
    if (_items.length > _limit) _items.removeRange(_limit, _items.length);
  }

  @override
  void close() {}
}

class _Entry {
  _Entry(this.id, this.record);
  final int id;
  final ClipRecord record;
}
