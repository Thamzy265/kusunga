import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../clipboard/clipboard_source.dart';
import '../log/app_log.dart';
import 'clip_classifier.dart';
import 'clip_item.dart';
import 'history_opener.dart';
import 'history_store.dart';

/// Banners at the top of the history list (UI spec, "Banner" row).
enum HistoryBanner { memoryOnly, readError, writeError, clearError }

/// Takes what the clipboard watcher reports, keeps the history, and holds the
/// state the history window shows.
class HistoryService extends ChangeNotifier {
  HistoryService({
    required this._store,
    required this._source,
    required this._log,
    Set<HistoryNotice> notices = const {},
    int Function()? clock,
    Future<void> Function(String text)? writeClipboard,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _writeClipboard =
           writeClipboard ??
           ((text) => Clipboard.setData(ClipboardData(text: text))),
       _banners = {
         if (notices.contains(HistoryNotice.memoryOnly))
           HistoryBanner.memoryOnly,
         if (notices.contains(HistoryNotice.readError)) HistoryBanner.readError,
       };

  /// Copies that could not be saved are kept in memory, up to this many.
  static const maxWaiting = 20;

  final HistoryStore _store;
  final ClipboardSource _source;
  final ErrorLog _log;
  final int Function() _clock;
  final Future<void> Function(String text) _writeClipboard;
  final Set<HistoryBanner> _banners;
  final _waiting = <_Waiting>[]; // oldest first
  var _nextWaitingId = -1;
  StreamSubscription<ClipboardEvent>? _subscription;
  List<ClipItem> _items = const [];
  var _pasteAccess = PasteAccess.notApplicable;
  var _closed = false;
  var _disposed = false;

  /// Newest first, with copies that are waiting to be saved on top.
  List<ClipItem> get items => _items;
  int get limit => _store.limit;
  Set<HistoryBanner> get banners => Set.unmodifiable(_banners);
  PasteAccess get pasteAccess => _pasteAccess;

  /// Starts listening for copies and shows what is already saved.
  void start() {
    _refresh();
    _subscription = _source.events.listen(
      _onEvent,
      onError: (Object _) => _log.log(LogCode.clipboardChannelError),
    );
    unawaited(recheckPasteAccess());
  }

  Future<void> recheckPasteAccess() async {
    final access = await _source.pasteAccess();
    if (_closed || access == _pasteAccess) return;
    _pasteAccess = access;
    _notify();
  }

  void _onEvent(ClipboardEvent event) {
    if (_closed) return;
    switch (event) {
      case ClipboardSkipped(:final reason):
        if (reason == SkipReason.tooLarge) _log.log(LogCode.clipboardTooLarge);
      case ClipboardReadError(:final code):
        _log.log(
          code == 'locked'
              ? LogCode.clipboardLocked
              : LogCode.clipboardChannelError,
        );
      case ClipboardText(:final text):
        _capture(text);
    }
  }

  void _capture(String text) {
    if (text.trim().isEmpty) return;
    if (text.length > ClipItem.maxContentLength) {
      _log.log(LogCode.clipboardTooLarge);
      return;
    }
    // Retry what is waiting first (oldest first), so order is kept.
    _flushWaiting();
    final entry = _Waiting(_nextWaitingId--, text, classify(text), _clock());
    if (_waiting.isEmpty) {
      _save(entry);
    } else {
      _addWaiting(entry);
    }
    _refresh();
  }

  void _flushWaiting() {
    while (_waiting.isNotEmpty) {
      if (!_trySave(_waiting.first)) return;
      _waiting.removeAt(0);
    }
    _banners.remove(HistoryBanner.writeError);
  }

  void _save(_Waiting entry) {
    if (!_trySave(entry)) _addWaiting(entry);
  }

  void _addWaiting(_Waiting entry) {
    _waiting.add(entry);
    if (_waiting.length > maxWaiting) _waiting.removeAt(0);
    _banners.add(HistoryBanner.writeError);
  }

  bool _trySave(_Waiting e) {
    try {
      _store.insertOrBump(e.text, e.kind, e.time);
      return true;
    } catch (error) {
      _log.log(
        LogCode.writeFailed,
        error is SqliteException ? error.extendedResultCode : null,
      );
      return false;
    }
  }

  void _refresh() {
    try {
      final saved = _store.list();
      _items = [
        for (final w in _waiting.reversed)
          ClipItem(
            id: w.id,
            kind: w.kind,
            preview: previewOf(w.text),
            isTruncated: w.text.length > ClipItem.previewLength,
            createdAt: w.time,
            lastCopiedAt: w.time,
          ),
        ...saved,
      ];
    } catch (_) {
      _log.log(LogCode.readFailed);
    }
    _notify();
  }

  /// Puts the whole text of an item on the clipboard. Returns false if that
  /// failed. The watcher then sees the copy and moves the item to the top.
  Future<bool> copy(int id) async {
    try {
      final text = _contentOf(id);
      if (text == null) return false;
      await _writeClipboard(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _contentOf(int id) {
    if (id < 0) {
      for (final w in _waiting) {
        if (w.id == id) return w.text;
      }
      return null;
    }
    return _store.contentOf(id);
  }

  /// Removes one item and returns it so Undo can put it back.
  ClipRecord? delete(int id) {
    ClipRecord? removed;
    if (id < 0) {
      final i = _waiting.indexWhere((w) => w.id == id);
      if (i >= 0) {
        final w = _waiting.removeAt(i);
        removed = ClipRecord(
          content: w.text,
          kind: w.kind,
          createdAt: w.time,
          lastCopiedAt: w.time,
        );
        if (_waiting.isEmpty) _banners.remove(HistoryBanner.writeError);
      }
    } else {
      try {
        removed = _store.delete(id);
      } catch (_) {
        _log.log(LogCode.writeFailed);
      }
    }
    _refresh();
    return removed;
  }

  void undo(ClipRecord record) {
    try {
      _store.restore(record);
    } catch (_) {
      _log.log(LogCode.writeFailed);
    }
    _refresh();
  }

  /// Removes everything. Returns how many items went, or null if it failed.
  int? clear() {
    try {
      final waiting = _waiting.length;
      final removed = _store.clear() + waiting;
      _waiting.clear();
      _banners
        ..remove(HistoryBanner.clearError)
        ..remove(HistoryBanner.writeError);
      _refresh();
      return removed;
    } catch (_) {
      _log.log(LogCode.writeFailed);
      _banners.add(HistoryBanner.clearError);
      _notify();
      return null;
    }
  }

  /// How many items lowering the limit to [newLimit] would delete.
  int countRemovedBy(int newLimit) => _store.countRemovedBy(newLimit);

  /// Saves a new limit. Returns false if it is outside 10 to 5,000 or could
  /// not be saved.
  bool setLimit(int newLimit) {
    if (newLimit < HistoryStore.minLimit || newLimit > HistoryStore.maxLimit) {
      return false;
    }
    try {
      _store.setLimit(newLimit);
    } catch (_) {
      _log.log(LogCode.writeFailed);
      return false;
    }
    _refresh();
    return true;
  }

  void dismiss(HistoryBanner banner) {
    if (_banners.remove(banner)) _notify();
  }

  /// Stops listening and closes the database cleanly. Safe to call more than
  /// once. Called on every exit path.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    try {
      _store.close();
    } catch (_) {
      _log.log(LogCode.flushFailed);
    }
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
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class _Waiting {
  _Waiting(this.id, this.text, this.kind, this.time);
  final int id;
  final String text;
  final ClipKind kind;
  final int time;
}
