import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../log/app_log.dart';
import 'snippet.dart';
import 'snippet_shortcut.dart';
import 'snippet_store.dart';

/// Banners at the top of the Snippets tab (UI spec, "Snippets banner" and
/// the list's "Error" cell).
enum SnippetBanner {
  /// Memory-only or incompatible database: snippets can't be saved.
  unavailable,

  /// The list could not be read.
  readError,
}

/// Why snippets can't be opened in this session (UI spec, Copy, "Banners").
/// In every case the list is empty and editing is off.
enum SnippetsUnavailable {
  /// The keychain (or the data folder, or the cipher) can't be used.
  keychain,

  /// The file was saved by a newer Kusunga.
  newerFile,

  /// The update to this version (a migration) failed and was rolled back.
  updateFailed,

  /// The safety copy before the update could not be made.
  backupFailed,
}

enum SnippetSave {
  saved,

  /// A field is wrong; see [SnippetSaveResult.problems].
  invalid,

  /// 1,000 snippets already.
  capReached,

  /// The database refused the write (disk full, I/O). Nothing was changed.
  failed,

  /// Editing is off (memory-only or incompatible mode, or closed).
  unavailable,

  /// The shortcut clashes with another snippet's; see
  /// [SnippetSaveResult.clash]. Nothing was changed.
  shortcutTaken,
}

class SnippetSaveResult {
  const SnippetSaveResult(
    this.outcome, {
    this.id,
    this.problems = const {},
    this.clash,
  });
  final SnippetSave outcome;
  final int? id;
  final Set<SnippetProblem> problems;
  final ShortcutClash? clash;
}

/// Holds the snippets the main window and the picker show, and makes every
/// change through the store. Failures are logged as codes only: never a name,
/// a type or any content (design note, "Observability").
class SnippetService extends ChangeNotifier {
  SnippetService({
    required this._store,
    required this._log,
    required bool editable,
    this.unavailableReason = SnippetsUnavailable.keychain,
    int Function()? clock,
    required this._writeClipboard,
  }) : _editable = editable,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (!editable) {
      _banners.add(SnippetBanner.unavailable);
      _log.log(LogCode.snippetsUnavailable);
    }
    _refresh();
  }

  final SnippetStore _store;
  final ErrorLog _log;
  final bool _editable;
  final int Function() _clock;
  final Future<bool> Function(String text) _writeClipboard;
  final _banners = <SnippetBanner>{};

  /// Which banner text the unavailable banner shows (when editing is off).
  final SnippetsUnavailable unavailableReason;
  List<SnippetItem> _items = const [];
  var _closed = false;
  var _disposed = false;

  /// In the user's order.
  List<SnippetItem> get items => _items;
  Set<SnippetBanner> get banners => Set.unmodifiable(_banners);

  /// New, Edit, Move, Delete and "Save as snippet" are allowed. False in
  /// memory-only and incompatible mode, so nothing the user types is lost on
  /// quit. Loaded snippets still copy and paste.
  bool get canEdit => _editable && !_closed;

  bool get atCap => _items.length >= SnippetStore.maxCount;

  /// New snippet and "Save as snippet" are allowed.
  bool get canCreate => canEdit && !atCap;

  /// Every snippet that has a typed shortcut: what the native matcher gets
  /// (ids and shortcuts only, never names or content; ADR 0004).
  List<({int id, String shortcut})> get shortcutTable => [
    for (final s in _items)
      if (s.shortcut != null) (id: s.id, shortcut: s.shortcut!),
  ];

  /// The live check for the editor's Shortcut field: a problem with the text,
  /// a clash with another snippet in the list, or null if it is fine (an
  /// empty field is no shortcut). [selfId] is the snippet being edited.
  ShortcutIssue? shortcutIssue(String raw, {int? selfId}) {
    final shortcut = shortcutOrNull(raw);
    if (shortcut == null) return null;
    final problem = checkShortcutText(shortcut);
    if (problem != null) return ShortcutIssue.problem(problem);
    final clash = findShortcutClash(shortcut, [
      for (final s in _items)
        if (s.shortcut != null) (id: s.id, name: s.name, shortcut: s.shortcut!),
    ], selfId: selfId);
    return clash == null ? null : ShortcutIssue.clash(clash);
  }

  /// Reads the list again ("Try again" on the read banner).
  void reload() => _refresh();

  void _refresh() {
    if (_closed) return;
    try {
      _items = _store.list();
      _banners.remove(SnippetBanner.readError);
    } catch (_) {
      _log.log(LogCode.readFailed);
      _banners.add(SnippetBanner.readError);
    }
    _notify();
  }

  String? textOf(int id) {
    if (_closed) return null;
    try {
      return _store.contentOf(id);
    } catch (_) {
      _log.log(LogCode.readFailed);
      return null;
    }
  }

  /// The whole text for Edit, or null (logged as snippetOpenFailed) if it
  /// cannot be read. The editor never edits from the short preview.
  String? fullTextForEdit(int id) {
    final text = textOf(id);
    if (text == null && !_closed) _log.log(LogCode.snippetOpenFailed);
    return text;
  }

  /// A text to save as a snippet could not be read (F10): logged only.
  void noteOpenFailed() {
    if (!_closed) _log.log(LogCode.snippetOpenFailed);
  }

  int? _code(Object error) =>
      error is SqliteException ? error.extendedResultCode : null;

  /// Creates a snippet, or with [id] changes that one. The name is made one
  /// line first. Every problem with the fields is reported at once. An empty
  /// [shortcut] is none; a clash is found by the store in the same
  /// transaction as the write (PM decision D1 A).
  SnippetSaveResult save({
    int? id,
    required String name,
    required String content,
    required SnippetType type,
    String? shortcut,
  }) {
    if (!canEdit) return const SnippetSaveResult(SnippetSave.unavailable);
    final clean = normaliseName(name);
    final code = shortcutOrNull(shortcut);
    final problems = {
      ...checkSnippet(clean, content),
      if (code != null)
        ...switch (checkShortcutText(code)) {
          ShortcutProblem.length => {SnippetProblem.shortcutLength},
          ShortcutProblem.spaces => {SnippetProblem.shortcutSpaces},
          null => <SnippetProblem>{},
        },
    };
    if (problems.isNotEmpty) {
      return SnippetSaveResult(SnippetSave.invalid, problems: problems);
    }
    try {
      final now = _clock();
      if (id == null) {
        if (atCap) throw SnippetCapReached();
        id = _store.insert(
          name: clean,
          content: content,
          type: type,
          nowMs: now,
          shortcut: code,
        );
      } else if (!_store.update(
        id,
        name: clean,
        content: content,
        type: type,
        nowMs: now,
        shortcut: code,
      )) {
        // Deleted meanwhile: nothing to change.
        _log.log(LogCode.snippetSaveFailed);
        _refresh();
        return const SnippetSaveResult(SnippetSave.failed);
      }
    } on SnippetCapReached {
      _log.log(LogCode.snippetCapReached);
      return const SnippetSaveResult(SnippetSave.capReached);
    } on ShortcutTaken catch (taken) {
      // The user's choice, not a failure: nothing to log. The list may be
      // out of date, so it is read again.
      _refresh();
      return SnippetSaveResult(SnippetSave.shortcutTaken, clash: taken.clash);
    } catch (error) {
      _log.log(LogCode.snippetSaveFailed, _code(error));
      return const SnippetSaveResult(SnippetSave.failed);
    }
    _refresh();
    return SnippetSaveResult(SnippetSave.saved, id: id);
  }

  /// Moves a snippet to [toIndex]. False if it failed (the old order stays)
  /// or editing is off.
  bool move(int id, int toIndex) {
    if (!canEdit) return false;
    try {
      final moved = _store.move(id, toIndex);
      _refresh();
      return moved;
    } catch (error) {
      _log.log(LogCode.snippetMoveFailed, _code(error));
      return false;
    }
  }

  /// Removes a snippet. The record is kept by the caller for Undo (in memory,
  /// 5 s). `failed` is true if the database refused, and the row stays.
  ({SnippetRecord? record, bool failed}) delete(int id) {
    if (!canEdit) return (record: null, failed: false);
    try {
      final record = _store.delete(id);
      _refresh();
      return (record: record, failed: false);
    } catch (error) {
      _log.log(LogCode.snippetDeleteFailed, _code(error));
      return (record: null, failed: true);
    }
  }

  /// Puts a deleted snippet back. False if that failed.
  bool undo(SnippetRecord record) {
    if (!canEdit) return false;
    try {
      _store.restore(record);
    } on SnippetCapReached {
      _log.log(LogCode.snippetCapReached);
      return false;
    } catch (error) {
      _log.log(LogCode.snippetSaveFailed, _code(error));
      return false;
    }
    _refresh();
    return true;
  }

  /// Puts the whole text on the clipboard as Kusunga's own change, so the
  /// watcher does not add it to history (PM decision D1).
  Future<bool> copy(int id) async {
    final text = textOf(id);
    if (text == null) return false;
    try {
      return await _writeClipboard(text);
    } catch (_) {
      return false;
    }
  }

  /// The connection belongs to the history; this only stops changes.
  void close() {
    if (_closed) return;
    _closed = true;
    _items = const [];
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closed = true;
    super.dispose();
  }
}
