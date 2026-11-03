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
  String? contentOf(int id) {
    for (final e in _items) {
      if (e.id == id) return e.record.content;
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
  ClipRecord? delete(int id) {
    final i = _items.indexWhere((e) => e.id == id);
    return i < 0 ? null : _items.removeAt(i).record;
  }

  @override
  void restore(ClipRecord record) {
    _items.removeWhere((e) => e.record.content == record.content);
    final entry = _Entry(_nextId++, record);
    final at = _items.indexWhere(
      (e) => e.record.lastCopiedAt <= record.lastCopiedAt,
    );
    _items.insert(at < 0 ? _items.length : at, entry);
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
