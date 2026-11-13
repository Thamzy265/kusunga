import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../history/clip_item.dart';
import '../history/expiry_service.dart';
import '../history/history_store.dart';
import '../picker/paste_mode.dart';
import '../shortcuts/ignored_apps.dart';
import '../snippets/snippet.dart';
import '../snippets/snippet_shortcut.dart';
import '../snippets/snippet_store.dart';
import 'export_format.dart';

/// Writes a checked import into [db]. The caller holds one write
/// transaction around it, so a failure anywhere changes nothing (R2).
///
/// Merge rules (D3 A, D5 A, lead ruling G5 2026-11-12, PM decision "Never
/// remove" 2026-11-13):
///  - snippets are added after the existing ones; one with the same name and
///    content as a snippet already here is skipped; a shortcut that clashes
///    is dropped and the snippet added without it;
///  - history never deletes or changes anything shown here. Items keep the
///    file's times. A text already shown is "already here": its item keeps
///    its times and its place (lead ruling R9, 2026-11-13). Items older than
///    the auto-delete time are not added. The rest fill only the free room
///    under the limit, newest first; the others don't fit and are not
///    added. The count is of items added, not lines in the file (T4);
///  - settings and ignored apps only with [applySettings]; apps are only
///    ever added. A history limit or auto-delete time that would delete an
///    item shown now is kept as it is; the other settings still apply.
///
/// [notBefore] is the auto-delete cut-off in use now (items last copied
/// before it are hidden and on their way out); null for Never.
ImportCounts importIntoDatabase(
  Database db,
  ExportBundle bundle, {
  required bool applySettings,
  required int? notBefore,
  required int nowMs,
  required Uint8List Function(String content) hash,
}) {
  var kept = (cutoff: notBefore, limit: false, expiry: false, changed: false);
  var appsAdded = 0;
  if (applySettings) {
    kept = _applySettings(
      db,
      bundle.settings,
      notBefore: notBefore,
      nowMs: nowMs,
    );
    appsAdded = _addIgnoredApps(db, bundle.ignoredApps ?? const []);
  }
  final (added, alreadyHere, dropped) = _addSnippets(db, bundle, nowMs);
  final history = _addHistory(
    db,
    bundle.history ?? const [],
    notBefore: kept.cutoff,
    hash: hash,
  );
  return ImportCounts(
    snippetsAdded: added,
    snippetsAlreadyHere: alreadyHere,
    shortcutsDropped: dropped,
    historyAdded: history.added,
    historyAlreadyHere: history.alreadyHere,
    historyTooOld: history.tooOld,
    historyNoRoom: history.noRoom,
    limitKept: kept.limit,
    expiryKept: kept.expiry,
    // Only a real change counts (lead ruling R10, 2026-11-13).
    settingsApplied: kept.changed || appsAdded > 0,
  );
}

/// Items shown under the cut-off [notBefore] (all of them for Never).
int _shown(Database db, int? notBefore) =>
    db.select(
          'SELECT count(*) AS n FROM clip_items WHERE last_copied_at >= ?',
          [notBefore ?? _minInt],
        ).single['n']
        as int;

const _minInt = -0x8000000000000000;

/// Saves the file's settings (D5 A), except a history limit or an
/// auto-delete time that would delete an item shown now: that one keeps its
/// value (PM decision 2026-11-13). Items already hidden by the auto-delete
/// time in use don't count: they go at its next clean-up anyway. Returns
/// the cut-off the history import then uses, which setting was kept, and
/// whether any stored value really changed.
({int? cutoff, bool limit, bool expiry, bool changed}) _applySettings(
  Database db,
  ExportSettings? s, {
  required int? notBefore,
  required int nowMs,
}) {
  if (s == null) {
    return (cutoff: notBefore, limit: false, expiry: false, changed: false);
  }
  var changed = false;
  void put(String key, Object? value) {
    if (value == null || '$value' == _inUse(db, key)) return;
    db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
    changed = true;
  }

  var cutoff = notBefore;
  var expiryKept = false;
  final days = s.historyExpiryDays;
  if (days != null) {
    checkExpiryDays(days);
    final next = expiryCutoff(days, nowMs);
    final wouldGo = next == null
        ? 0
        : db.select(
                'SELECT count(*) AS n FROM clip_items '
                'WHERE last_copied_at < ? AND last_copied_at >= ?',
                [next, notBefore ?? _minInt],
              ).single['n']
              as int;
    if (wouldGo == 0) {
      put(historyExpirySetting, days);
      cutoff = next;
    } else {
      expiryKept = true;
    }
  }
  var limitKept = false;
  final limit = s.historyLimit;
  if (limit != null) {
    checkLimit(limit);
    if (limit >= _shown(db, cutoff)) {
      put('history_limit', limit);
    } else {
      limitKept = true;
    }
  }
  final typed = s.typedShortcutsOn;
  put('typed_shortcuts_on', typed == null ? null : (typed ? 1 : 0));
  put('paste_mode', s.pasteMode);
  return (
    cutoff: cutoff,
    limit: limitKept,
    expiry: expiryKept,
    changed: changed,
  );
}

/// The value a setting has in use now, read the way the app reads it: the
/// stored row, or the app's default when there is no row or the row isn't
/// one the app accepts (lead ruling R11, 2026-11-13). Paste mode: auto.
/// Auto-delete: Never. Typed shortcuts: off. History limit: 200.
String _inUse(Database db, String key) {
  final rows = db.select('SELECT value FROM settings WHERE key = ?', [key]);
  final raw = rows.isEmpty ? null : '${rows.single['value']}';
  return switch (key) {
    'history_limit' =>
      '${int.tryParse(raw ?? '') ?? HistoryStore.defaultLimit}',
    historyExpirySetting => '${parseExpiryDays(raw) ?? 0}',
    'typed_shortcuts_on' => raw == '1' ? '1' : '0',
    'paste_mode' => PasteMode.parse(raw).stored,
    _ => raw ?? '',
  };
}

/// One history text from the file: repeated lines merge as Undo does.
class _Line {
  _Line(this.order, ExportHistoryItem h)
    : content = h.content,
      kind = h.kind,
      created = h.createdAt,
      last = h.lastCopiedAt;

  /// Where it first appears in the file.
  final int order;
  final String content;
  final ClipKind kind;
  int created;
  int last;

  void merge(ExportHistoryItem h) {
    created = min(created, h.createdAt);
    last = max(last, h.lastCopiedAt);
  }
}

/// Adds the file's history without deleting or changing anything shown
/// here (R1, PM decision 2026-11-13; R9, lead ruling 2026-11-13). A text
/// already shown is left as it is and counted as already here. Any other
/// text needs a free place under the limit; a hidden, expired item that
/// comes back counts as one, and is revived with the file's times merged
/// as Undo does. Those are taken newest first while there is room, and
/// written in the file's order.
({int added, int alreadyHere, int tooOld, int noRoom}) _addHistory(
  Database db,
  List<ExportHistoryItem> history, {
  required int? notBefore,
  required Uint8List Function(String content) hash,
}) {
  var tooOld = 0;
  final lines = <String, _Line>{};
  for (final h in history) {
    if (notBefore != null && h.lastCopiedAt < notBefore) {
      tooOld++;
      continue;
    }
    checkContent(h.content);
    final line = lines[h.content];
    if (line == null) {
      lines[h.content] = _Line(lines.length, h);
    } else {
      line.merge(h);
    }
  }
  if (lines.isEmpty) {
    return (added: 0, alreadyHere: 0, tooOld: tooOld, noRoom: 0);
  }

  final hashes = <_Line, Uint8List>{};
  var alreadyHere = 0;
  final needRoom = <_Line>[];
  final find = db.prepare(
    'SELECT last_copied_at FROM clip_items WHERE content_hash = ?',
  );
  try {
    for (final line in lines.values) {
      final h = hashes[line] = hash(line.content);
      final found = find.select([h]);
      final last = found.isEmpty ? null : found.single['last_copied_at'] as int;
      if (last != null && (notBefore == null || last >= notBefore)) {
        alreadyHere++; // shown: never written, so nothing it has changes
      } else {
        needRoom.add(line);
      }
    }
  } finally {
    find.close();
  }
  final limit =
      db
              .select("SELECT value FROM settings WHERE key = 'history_limit'")
              .single['value']
          as int;
  final room = max(0, limit - _shown(db, notBefore));
  final taken =
      (needRoom.toList()..sort((a, b) {
            final newer = b.last.compareTo(a.last);
            return newer != 0 ? newer : a.order.compareTo(b.order);
          }))
          .take(room)
          .toSet();

  final insert = db.prepare(
    'INSERT INTO clip_items '
    '(content, kind, content_hash, created_at, last_copied_at) '
    'VALUES (?, ?, ?, ?, ?) '
    'ON CONFLICT (content_hash) DO UPDATE SET '
    'last_copied_at = max(last_copied_at, excluded.last_copied_at), '
    'created_at = min(created_at, excluded.created_at)',
  );
  try {
    for (final line in lines.values) {
      if (!taken.contains(line)) continue;
      insert.execute([
        line.content,
        line.kind.name,
        hashes[line],
        line.created,
        line.last,
      ]);
    }
  } finally {
    insert.close();
  }
  return (
    added: taken.length,
    alreadyHere: alreadyHere,
    tooOld: tooOld,
    noRoom: needRoom.length - taken.length,
  );
}

/// Adds the apps not on the list yet; returns how many were added.
int _addIgnoredApps(Database db, List<IgnoredApp> apps) {
  final presets = {for (final p in presetIgnoredApps) p.appId};
  var added = 0;
  for (final a in apps) {
    checkIgnoredApp(a);
    db.execute(
      'INSERT INTO ignored_apps (app_id, display_name, preset) '
      'VALUES (?, ?, ?) ON CONFLICT (app_id) DO NOTHING',
      [a.appId, a.displayName, presets.contains(a.appId) ? 1 : 0],
    );
    added += db.updatedRows;
  }
  return added;
}

(int, int, int) _addSnippets(Database db, ExportBundle bundle, int nowMs) {
  // The file's order: by position, ties in the order they appear.
  final indexed = bundle.snippets.indexed.toList()
    ..sort((a, b) {
      final p = a.$2.position.compareTo(b.$2.position);
      return p != 0 ? p : a.$1.compareTo(b.$1);
    });
  var count =
      db.select('SELECT count(*) AS n FROM snippets').single['n'] as int;
  final owners = <ShortcutOwner>[
    for (final r in db.select(
      'SELECT id, name, shortcut FROM snippets WHERE shortcut IS NOT NULL',
    ))
      (
        id: r['id'] as int,
        name: r['name'] as String,
        shortcut: r['shortcut'] as String,
      ),
  ];
  var added = 0;
  var alreadyHere = 0;
  var dropped = 0;
  for (final (_, s) in indexed) {
    checkSnippetFields(s.name, s.content);
    checkShortcutField(s.shortcut);
    final same = db.select(
      'SELECT 1 FROM snippets WHERE name = ? AND content = ? LIMIT 1',
      [s.name, s.content],
    );
    if (same.isNotEmpty) {
      alreadyHere++;
      continue;
    }
    if (count >= SnippetStore.maxCount) throw SnippetCapReached();
    var shortcut = s.shortcut;
    if (shortcut != null && findShortcutClash(shortcut, owners) != null) {
      shortcut = null;
      dropped++;
    }
    final id =
        db.select(
              'INSERT INTO snippets '
              '(name, content, type, position, created_at, updated_at, '
              'shortcut) VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id',
              [s.name, s.content, s.type.name, count, nowMs, nowMs, shortcut],
            ).single['id']
            as int;
    if (shortcut != null) {
      owners.add((id: id, name: s.name, shortcut: shortcut));
    }
    count++;
    added++;
  }
  return (added, alreadyHere, dropped);
}
