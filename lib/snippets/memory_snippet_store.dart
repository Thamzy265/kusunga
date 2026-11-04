import '../history/clip_item.dart';
import 'snippet.dart';
import 'snippet_store.dart';

/// Snippets kept in memory only (tests, and memory-only or incompatible
/// mode, where the app never lets the user add one, so nothing typed is lost
/// on quit).
class MemorySnippetStore implements SnippetStore {
  final _entries = <_Entry>[]; // in order
  var _nextId = 1;

  @override
  int get count => _entries.length;

  @override
  List<SnippetItem> list() => [
    for (var i = 0; i < _entries.length; i++)
      SnippetItem(
        id: _entries[i].id,
        name: _entries[i].name,
        type: _entries[i].type,
        preview: previewOf(_entries[i].content),
        isTruncated: _entries[i].content.length > ClipItem.previewLength,
        position: i,
        createdAt: _entries[i].createdAt,
        updatedAt: _entries[i].updatedAt,
      ),
  ];

  _Entry? _find(int id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  String? contentOf(int id) => _find(id)?.content;

  @override
  int insert({
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
  }) {
    checkSnippetFields(name, content);
    if (_entries.length >= SnippetStore.maxCount) throw SnippetCapReached();
    final id = _nextId++;
    _entries.add(_Entry(id, name, content, type, nowMs, nowMs));
    return id;
  }

  @override
  bool update(
    int id, {
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
  }) {
    checkSnippetFields(name, content);
    final e = _find(id);
    if (e == null) return false;
    e
      ..name = name
      ..content = content
      ..type = type
      ..updatedAt = nowMs;
    return true;
  }

  @override
  bool move(int id, int toIndex) {
    final order = reorder([for (final e in _entries) e.id], id, toIndex);
    if (order == null) return false;
    final byId = {for (final e in _entries) e.id: e};
    _entries
      ..clear()
      ..addAll(order.map((i) => byId[i]!));
    return true;
  }

  @override
  SnippetRecord? delete(int id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    final e = _entries.removeAt(i);
    return SnippetRecord(
      name: e.name,
      content: e.content,
      type: e.type,
      position: i,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
    );
  }

  @override
  void restore(SnippetRecord record) {
    checkSnippetFields(record.name, record.content);
    if (_entries.length >= SnippetStore.maxCount) throw SnippetCapReached();
    _entries.insert(
      record.position.clamp(0, _entries.length),
      _Entry(
        _nextId++,
        record.name,
        record.content,
        record.type,
        record.createdAt,
        record.updatedAt,
      ),
    );
  }

  @override
  void close() {}
}

class _Entry {
  _Entry(
    this.id,
    this.name,
    this.content,
    this.type,
    this.createdAt,
    this.updatedAt,
  );

  final int id;
  String name;
  String content;
  SnippetType type;
  final int createdAt;
  int updatedAt;
}
