import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:convert';

import 'clip_item.dart';
import 'history_store.dart';
import 'migrations.dart';

/// The SQLite3 Multiple Ciphers library is not the one in use, so nothing can
/// be stored encrypted.
class EncryptionUnavailable implements Exception {
  @override
  String toString() => 'EncryptionUnavailable';
}

/// The database was written by a newer Kusunga. It is left untouched.
class UnsupportedSchemaVersion implements Exception {
  UnsupportedSchemaVersion(this.found);
  final int found;
  @override
  String toString() => 'UnsupportedSchemaVersion($found)';
}

/// A migration failed. It was rolled back; the backup copy is kept.
class MigrationFailed implements Exception {
  MigrationFailed(this.version, this.cause);
  final int version;
  final Object cause;
  @override
  String toString() => 'MigrationFailed($version)';
}

bool _defaultCipherActive(Database db) => db.select('PRAGMA cipher').isNotEmpty;

/// Encrypted SQLite history (ADR 0002). The whole file is encrypted with
/// SQLite3 Multiple Ciphers; the key lives in the OS keychain.
class SqliteHistoryStore implements HistoryStore {
  SqliteHistoryStore._(this._db, this._limit, this._path);

  final Database _db;
  final String _path;
  int _limit;
  bool _closed = false;

  static final _keyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Opens (or creates) the database at [path]. [keyHex] is the 256-bit key as 64 hex
  /// characters. Throws [EncryptionUnavailable] if the cipher is not active,
  /// before anything is written. Throws [SqliteException] if the file cannot
  /// be read with this key.
  static SqliteHistoryStore open({
    required String path,
    required String keyHex,
    bool Function(Database db)? cipherActive,
    List<Migration> migrations = kMigrations,
  }) {
    if (!_keyPattern.hasMatch(keyHex)) {
      throw ArgumentError.value('<redacted>', 'keyHex', 'not 64 hex digits');
    }
    final check = cipherActive ?? _defaultCipherActive;

    // Prove the cipher is in this build before a file is created.
    final probe = sqlite3.openInMemory();
    final active = check(probe);
    probe.close();
    if (!active) throw EncryptionUnavailable();

    final db = sqlite3.open(path);
    try {
      db.execute("PRAGMA cipher = 'chacha20'");
      db.execute("PRAGMA key = \"x'$keyHex'\"");
      // Fails with "file is not a database" if the key is wrong.
      db.select('SELECT count(*) FROM sqlite_master');
      if (!check(db)) throw EncryptionUnavailable();
      db.execute('PRAGMA secure_delete = ON');
      _migrate(db, path, migrations);
      _checkIntact(db);
      final limit =
          db
                  .select(
                    "SELECT value FROM settings WHERE key = 'history_limit'",
                  )
                  .single['value']
              as int;
      return SqliteHistoryStore._(db, limit, path);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// Reads every page. Damage in the middle of the file (which the key check
  /// on the first page does not see) throws here, so the file is treated as
  /// unreadable at start-up instead of failing later as an empty list.
  static void _checkIntact(Database db) {
    final rows = db.select('PRAGMA quick_check');
    if (rows.length != 1 || rows.single.values.single != 'ok') {
      throw StateError('store damaged');
    }
  }

  static void _migrate(Database db, String path, List<Migration> all) {
    final current = db.select('PRAGMA user_version').single.values.single;
    final from = current as int;
    final target = all.last.version;
    if (from > target) throw UnsupportedSchemaVersion(from);
    if (from == target) return;

    final backup = from > 0 ? File('$path.bak') : null;
    backup?.writeAsBytesSync(File(path).readAsBytesSync(), flush: true);

    for (final m in all.where((m) => m.version > from)) {
      m.onRun?.call();
      db.execute('BEGIN IMMEDIATE');
      try {
        for (final sql in m.statements) {
          db.execute(sql);
        }
        db.execute('PRAGMA user_version = ${m.version}');
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        throw MigrationFailed(m.version, e);
      }
    }
    if (backup != null && backup.existsSync()) backup.deleteSync();
  }

  @override
  int get limit => _limit;

  @override
  int get count =>
      _db.select('SELECT count(*) AS n FROM clip_items').single['n'] as int;

  // Enough bytes for 2,000 UTF-16 units (at most 3 bytes each, 4 per pair).
  static const _previewBytes = ClipItem.previewLength * 4;

  @override
  List<ClipItem> list() {
    // The preview is cut on the bytes (CAST ... AS BLOB) because SQL text
    // functions stop at a NUL and count code points, not UTF-16 units.
    final rows = _db.select(
      'SELECT id, kind, substr(CAST(content AS BLOB), 1, $_previewBytes) AS '
      'head, length(CAST(content AS BLOB)) AS bytes, created_at, '
      'last_copied_at FROM clip_items ORDER BY last_copied_at DESC, id DESC',
    );
    return [for (final r in rows) _item(r)];
  }

  ClipItem _item(Row r) {
    final head = utf8.decode(r['head'] as List<int>, allowMalformed: true);
    final preview = previewOf(head);
    return ClipItem(
      id: r['id'] as int,
      kind: ClipKind.fromName(r['kind'] as String),
      preview: preview,
      isTruncated:
          (r['bytes'] as int) > _previewBytes ||
          head.length > ClipItem.previewLength,
      createdAt: r['created_at'] as int,
      lastCopiedAt: r['last_copied_at'] as int,
    );
  }

  @override
  String? contentOf(int id) {
    final rows = _db.select('SELECT content FROM clip_items WHERE id = ?', [
      id,
    ]);
    return rows.isEmpty ? null : rows.single['content'] as String;
  }

  Uint8List _hash(String content) =>
      Uint8List.fromList(sha256.convert(utf8.encode(content)).bytes);

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

  /// Strictly newer than every item already kept, so order never ties.
  int _nextTimestamp(int nowMs) {
    final newest = _db
        .select('SELECT max(last_copied_at) AS m FROM clip_items')
        .single['m'];
    if (newest == null) return nowMs;
    return nowMs > (newest as int) ? nowMs : newest + 1;
  }

  void _trim([int? limit]) {
    _db.execute(
      'DELETE FROM clip_items WHERE id IN (SELECT id FROM clip_items '
      'ORDER BY last_copied_at DESC, id DESC LIMIT -1 OFFSET ?)',
      [limit ?? _limit],
    );
  }

  @override
  int insertOrBump(String content, ClipKind kind, int nowMs) {
    checkContent(content);
    return _transaction(() {
      final ts = _nextTimestamp(nowMs);
      final id =
          _db.select(
                'INSERT INTO clip_items '
                '(content, kind, content_hash, created_at, last_copied_at) '
                'VALUES (?, ?, ?, ?, ?) '
                'ON CONFLICT (content_hash) DO UPDATE SET '
                'last_copied_at = excluded.last_copied_at, '
                'kind = excluded.kind RETURNING id',
                [content, kind.name, _hash(content), ts, ts],
              ).single['id']
              as int;
      _trim();
      return id;
    });
  }

  @override
  ClipRecord? delete(int id) => _transaction(() {
    final rows = _db.select(
      'SELECT content, kind, created_at, last_copied_at FROM clip_items '
      'WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    _db.execute('DELETE FROM clip_items WHERE id = ?', [id]);
    return ClipRecord(
      content: r['content'] as String,
      kind: ClipKind.fromName(r['kind'] as String),
      createdAt: r['created_at'] as int,
      lastCopiedAt: r['last_copied_at'] as int,
    );
  });

  @override
  void restore(ClipRecord record) {
    checkContent(record.content);
    _transaction(() {
      _db.execute(
        'INSERT INTO clip_items '
        '(content, kind, content_hash, created_at, last_copied_at) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT (content_hash) DO UPDATE SET '
        'last_copied_at = max(last_copied_at, excluded.last_copied_at), '
        'created_at = min(created_at, excluded.created_at)',
        [
          record.content,
          record.kind.name,
          _hash(record.content),
          record.createdAt,
          record.lastCopiedAt,
        ],
      );
      _trim();
    });
  }

  @override
  int clear() {
    final n = _transaction(() {
      final n = count;
      _db.execute('DELETE FROM clip_items');
      return n;
    });
    _removeOldCopies();
    return n;
  }

  /// "Clear history" must leave nothing readable behind: the migration backup
  /// and files moved aside as unreadable are encrypted with the key that is
  /// still in the keychain, so they are deleted too.
  void _removeOldCopies() {
    try {
      final file = File(_path);
      final name = file.uri.pathSegments.last;
      for (final f in file.parent.listSync().whereType<File>()) {
        final other = f.uri.pathSegments.last;
        if (other == '$name.bak' || other.startsWith('$name.unreadable-')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  int countRemovedBy(int newLimit) {
    checkLimit(newLimit);
    final n = count;
    return n > newLimit ? n - newLimit : 0;
  }

  @override
  void setLimit(int newLimit) {
    checkLimit(newLimit);
    _transaction(() {
      _db.execute(
        'INSERT INTO settings (key, value) VALUES (?, ?) '
        'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
        ['history_limit', newLimit],
      );
      _trim(newLimit);
    });
    // Only after the commit: a failed save leaves the limit as it was.
    _limit = newLimit;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
  }
}
