import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../history/clip_item.dart';
import 'snippet.dart';
import 'snippet_store.dart';

/// The `snippets` table (schema version 3) on the history's encrypted
/// connection (ADR 0002). The connection belongs to the history store, which
/// opens and closes it, so [close] does nothing here.
class SqliteSnippetStore implements SnippetStore {
  SqliteSnippetStore(this._db);

  final Database _db;

  // Enough bytes for 2,000 UTF-16 units (at most 3 bytes each, 4 per pair).
  static const _previewBytes = ClipItem.previewLength * 4;

  T _transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  int get count =>
      _db.select('SELECT count(*) AS n FROM snippets').single['n'] as int;

  @override
  List<SnippetItem> list() {
    // As for history: the preview is cut on the bytes, because SQL text
    // functions stop at a NUL.
    final rows = _db.select(
      'SELECT id, name, type, position, created_at, updated_at, '
      'substr(CAST(content AS BLOB), 1, $_previewBytes) AS head, '
      'length(CAST(content AS BLOB)) AS bytes '
      'FROM snippets ORDER BY position, id',
    );
    return [
      for (final r in rows)
        () {
          final head = utf8.decode(
            r['head'] as List<int>,
            allowMalformed: true,
          );
          return SnippetItem(
            id: r['id'] as int,
            name: r['name'] as String,
            type: SnippetType.fromName(r['type'] as String),
            preview: previewOf(head),
            isTruncated:
                (r['bytes'] as int) > _previewBytes ||
                head.length > ClipItem.previewLength,
            position: r['position'] as int,
            createdAt: r['created_at'] as int,
            updatedAt: r['updated_at'] as int,
          );
        }(),
    ];
  }

  @override
  String? contentOf(int id) {
    final rows = _db.select('SELECT content FROM snippets WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.single['content'] as String;
  }

  @override
  int insert({
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
  }) {
    checkSnippetFields(name, content);
    return _transaction(() {
      final n = count;
      if (n >= SnippetStore.maxCount) throw SnippetCapReached();
      return _db.select(
            'INSERT INTO snippets '
            '(name, content, type, position, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?) RETURNING id',
            [name, content, type.name, n, nowMs, nowMs],
          ).single['id']
          as int;
    });
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
    return _transaction(() {
      _db.execute(
        'UPDATE snippets SET name = ?, content = ?, type = ?, updated_at = ? '
        'WHERE id = ?',
        [name, content, type.name, nowMs, id],
      );
      return _db.updatedRows > 0;
    });
  }

  List<int> _ids() => [
    for (final r in _db.select('SELECT id FROM snippets ORDER BY position, id'))
      r['id'] as int,
  ];

  void _renumber(List<int> order) {
    final stmt = _db.prepare('UPDATE snippets SET position = ? WHERE id = ?');
    try {
      for (var i = 0; i < order.length; i++) {
        stmt.execute([i, order[i]]);
      }
    } finally {
      stmt.close();
    }
  }

  @override
  bool move(int id, int toIndex) => _transaction(() {
    final order = reorder(_ids(), id, toIndex);
    if (order == null) return false;
    _renumber(order);
    return true;
  });

  @override
  SnippetRecord? delete(int id) => _transaction(() {
    final rows = _db.select(
      'SELECT name, content, type, created_at, updated_at FROM snippets '
      'WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final ids = _ids();
    final r = rows.single;
    _db.execute('DELETE FROM snippets WHERE id = ?', [id]);
    _renumber(ids.where((i) => i != id).toList());
    return SnippetRecord(
      name: r['name'] as String,
      content: r['content'] as String,
      type: SnippetType.fromName(r['type'] as String),
      position: ids.indexOf(id),
      createdAt: r['created_at'] as int,
      updatedAt: r['updated_at'] as int,
    );
  });

  @override
  void restore(SnippetRecord record) {
    checkSnippetFields(record.name, record.content);
    _transaction(() {
      final ids = _ids();
      if (ids.length >= SnippetStore.maxCount) throw SnippetCapReached();
      final id =
          _db.select(
                'INSERT INTO snippets '
                '(name, content, type, position, created_at, updated_at) '
                'VALUES (?, ?, ?, ?, ?, ?) RETURNING id',
                [
                  record.name,
                  record.content,
                  record.type.name,
                  ids.length,
                  record.createdAt,
                  record.updatedAt,
                ],
              ).single['id']
              as int;
      _renumber(ids..insert(record.position.clamp(0, ids.length), id));
    });
  }

  @override
  void close() {}
}
