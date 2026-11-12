import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../history/history_store.dart';
import '../shortcuts/ignored_apps.dart';
import '../snippets/snippet.dart';
import '../snippets/snippet_shortcut.dart';
import '../snippets/snippet_store.dart';
import 'export_format.dart';

/// Writes a checked import into [db]. The caller holds one write
/// transaction around it, so a failure anywhere changes nothing (R2).
///
/// Merge rules (D3 A, D5 A, lead ruling G5, 2026-11-12):
///  - snippets are added after the existing ones; one with the same name and
///    content as a snippet already here is skipped; a shortcut that clashes
///    is dropped and the snippet added without it;
///  - history items keep their times and merge with an item already here as
///    Undo does (the newer last copy, the older creation); items older than
///    [notBefore] (the auto-delete time) are not added; then the history is
///    trimmed to the limit;
///  - settings and ignored apps only with [applySettings]; apps are only
///    ever added.
ImportCounts importIntoDatabase(
  Database db,
  ExportBundle bundle, {
  required bool applySettings,
  required int? notBefore,
  required int nowMs,
  required Uint8List Function(String content) hash,
}) {
  if (applySettings) {
    _applySettings(db, bundle.settings);
    _addIgnoredApps(db, bundle.ignoredApps ?? const []);
  }
  final (added, alreadyHere, dropped) = _addSnippets(db, bundle, nowMs);

  var historyAdded = 0;
  var tooOld = 0;
  final history = bundle.history ?? const [];
  final insert = db.prepare(
    'INSERT INTO clip_items '
    '(content, kind, content_hash, created_at, last_copied_at) '
    'VALUES (?, ?, ?, ?, ?) '
    'ON CONFLICT (content_hash) DO UPDATE SET '
    'last_copied_at = max(last_copied_at, excluded.last_copied_at), '
    'created_at = min(created_at, excluded.created_at)',
  );
  try {
    for (final h in history) {
      if (notBefore != null && h.lastCopiedAt < notBefore) {
        tooOld++;
        continue;
      }
      checkContent(h.content);
      insert.execute([
        h.content,
        h.kind.name,
        hash(h.content),
        h.createdAt,
        h.lastCopiedAt,
      ]);
      historyAdded++;
    }
  } finally {
    insert.close();
  }
  final limit =
      db
              .select("SELECT value FROM settings WHERE key = 'history_limit'")
              .single['value']
          as int;
  db.execute(
    'DELETE FROM clip_items WHERE id IN (SELECT id FROM clip_items '
    'ORDER BY last_copied_at DESC, id DESC LIMIT -1 OFFSET ?)',
    [limit],
  );
  return ImportCounts(
    snippetsAdded: added,
    snippetsAlreadyHere: alreadyHere,
    shortcutsDropped: dropped,
    historyAdded: historyAdded,
    historyTooOld: tooOld,
  );
}

void _applySettings(Database db, ExportSettings? s) {
  if (s == null) return;
  void put(String key, Object? value) {
    if (value == null) return;
    db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  final limit = s.historyLimit;
  if (limit != null) checkLimit(limit);
  final days = s.historyExpiryDays;
  if (days != null) checkExpiryDays(days);
  put('history_limit', limit);
  put(historyExpirySetting, days);
  final typed = s.typedShortcutsOn;
  put('typed_shortcuts_on', typed == null ? null : (typed ? 1 : 0));
  put('paste_mode', s.pasteMode);
}

void _addIgnoredApps(Database db, List<IgnoredApp> apps) {
  final presets = {for (final p in presetIgnoredApps) p.appId};
  for (final a in apps) {
    checkIgnoredApp(a);
    db.execute(
      'INSERT INTO ignored_apps (app_id, display_name, preset) '
      'VALUES (?, ?, ?) ON CONFLICT (app_id) DO NOTHING',
      [a.appId, a.displayName, presets.contains(a.appId) ? 1 : 0],
    );
  }
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
