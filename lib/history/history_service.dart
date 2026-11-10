import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../clipboard/clipboard_source.dart';
import '../log/app_log.dart';
import 'clip_classifier.dart';
import 'clip_item.dart';
import '../shortcuts/ignored_apps.dart';
import '../snippets/memory_snippet_store.dart';
import '../snippets/snippet_service.dart';
import '../snippets/snippet_store.dart';
import 'history_opener.dart';
import 'history_store.dart';
import 'pause_service.dart';

/// Banners at the top of the history list (UI spec, "Banner" row).
enum HistoryBanner {
  memoryOnly,
  readError,
  incompatible,
  backupFailed,
  writeError,
  clearError,
}

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
    SnippetStore? snippetStore,
    SnippetsUnavailable? snippetsUnavailable,
    IgnoredAppStore? ignoredAppStore,
  }) : ignoredApps = ignoredAppStore ?? MemoryIgnoredAppStore(),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _writeClipboard =
           writeClipboard ??
           ((text) => Clipboard.setData(ClipboardData(text: text))),
       _persists =
           !notices.contains(HistoryNotice.memoryOnly) &&
           !notices.contains(HistoryNotice.incompatible) &&
           !notices.contains(HistoryNotice.backupFailed),
       _banners = {
         if (notices.contains(HistoryNotice.memoryOnly))
           HistoryBanner.memoryOnly,
         if (notices.contains(HistoryNotice.readError)) HistoryBanner.readError,
         if (notices.contains(HistoryNotice.incompatible))
           HistoryBanner.incompatible,
         if (notices.contains(HistoryNotice.backupFailed))
           HistoryBanner.backupFailed,
       } {
    snippets = SnippetService(
      store: snippetStore ?? MemorySnippetStore(),
      log: _log,
      editable: _persists,
      unavailableReason:
          snippetsUnavailable ??
          (notices.contains(HistoryNotice.backupFailed)
              ? SnippetsUnavailable.backupFailed
              : notices.contains(HistoryNotice.incompatible)
              ? SnippetsUnavailable.newerFile
              : SnippetsUnavailable.keychain),
      clock: _clock,
      writeClipboard: _source.writeOwn,
    );
    pause = PauseService(
      setNativePause: _source.setCapturePause,
      readSetting: setting,
      writeSetting: saveSetting,
      log: _log,
      persists: _persists,
      clock: _clock,
    );
  }

  /// "Pause history" (M1.6), kept in the same settings table.
  late final PauseService pause;

  /// The saved snippets, on the same database (M1.4). Editing is off when
  /// this session is memory only.
  late final SnippetService snippets;

  /// The typed-shortcut ignore list, on the same database (M1.5).
  final IgnoredAppStore ignoredApps;

  /// Copies that could not be saved are kept in memory, up to this many.
  static const maxWaiting = 20;

  final HistoryStore _store;
  final ClipboardSource _source;
  final ErrorLog _log;
  final int Function() _clock;
  final Future<void> Function(String text) _writeClipboard;
  final Set<HistoryBanner> _banners;
  final bool _persists;
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

  /// False when this session is memory only (keychain or file problem): what
  /// is saved, settings included, is gone after a quit.
  bool get persistsSettings => _persists;
  Set<HistoryBanner> get banners => Set.unmodifiable(_banners);
  PasteAccess get pasteAccess => _pasteAccess;

  /// Starts listening for copies and shows what is already saved.
  ///
  /// The pause and the ignore list are sent to the native watcher first
  /// (M1.6): their messages leave before the event channel's listen, which
  /// starts the watcher, so no copy slips in at launch while history is
  /// paused.
  void start() {
    _refresh();
    pause.load();
    List<String> ids;
    try {
      ids = [for (final a in ignoredApps.list()) a.appId];
    } catch (_) {
      _log.log(LogCode.readFailed);
      ids = const [];
    }
    unawaited(setCaptureIgnored(ids));
    _subscription = _source.events.listen(
      _onEvent,
      onError: (Object _) => _log.log(LogCode.clipboardChannelError),
    );
    unawaited(recheckPasteAccess());
  }

  /// Sends the ignore list to the native watcher (M1.6): at start, and each
  /// time the list changes (typed shortcuts get the same list).
  Future<bool> setCaptureIgnored(List<String> appIds) async {
    try {
      return await _source.setCaptureIgnored(appIds);
    } catch (_) {
      return false;
    }
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
        switch (reason) {
          case SkipReason.tooLarge:
            _log.log(LogCode.clipboardTooLarge);
          case SkipReason.ignoredApp:
            _log.log(LogCode.captureSkippedIgnoredApp);
          case SkipReason.concealed:
            break;
        }
      case ClipboardSourceUnknown():
        _log.log(LogCode.captureSourceUnknown);
      case ClipboardReadError(:final code):
        _log.log(
          code == 'locked'
              ? LogCode.clipboardLocked
              : LogCode.clipboardChannelError,
        );
      case ClipboardText(:final text, :final ownMarker):
        // Native code already skips copies while paused, before reading
        // them. If one still arrives (native code out of step after a
        // failed call), it is not kept.
        if (pause.isPaused) return;
        _capture(text, ownMarker: ownMarker);
    }
  }

  void _capture(String text, {bool ownMarker = false}) {
    if (text.trim().isEmpty) return;
    if (isOverCap(text)) {
      _log.log(LogCode.clipboardTooLarge);
      return;
    }
    // Retry what is waiting first (oldest first), so order is kept.
    _flushWaiting();
    // Our own marker (the picker pasted this) only moves text that is already
    // saved. Any app can add the marker, so text we do not know is an
    // ordinary copy and is saved like one.
    if (ownMarker && _bumpSaved(text)) {
      _refresh();
      return;
    }
    final entry = _Waiting(_nextWaitingId--, text, classify(text), _clock());
    if (_waiting.isEmpty) {
      _save(entry);
    } else {
      _addWaiting(entry);
    }
    _refresh();
  }

  bool _bumpSaved(String text) {
    try {
      return _store.bumpIfPresent(text, _clock());
    } catch (error) {
      final code = error is SqliteException ? error.extendedResultCode : null;
      _log.log(LogCode.writeFailed, code);
      return false;
    }
  }

  void _flushWaiting() {
    while (_waiting.isNotEmpty) {
      final result = _trySave(_waiting.first);
      if (result == _Save.retryLater) return;
      _waiting.removeAt(0); // saved, or can never be saved: not kept
    }
    _banners.remove(HistoryBanner.writeError);
  }

  void _save(_Waiting entry) {
    if (_trySave(entry) == _Save.retryLater) _addWaiting(entry);
  }

  void _addWaiting(_Waiting entry) {
    // The same text again replaces its earlier waiting copy (newest wins).
    _waiting.removeWhere((w) => w.text == entry.text);
    _waiting.add(entry);
    if (_waiting.length > maxWaiting) _waiting.removeAt(0);
    _banners.add(HistoryBanner.writeError);
  }

  _Save _trySave(_Waiting e) {
    try {
      _store.insertOrBump(e.text, e.kind, e.time);
      return _Save.saved;
    } catch (error) {
      final code = error is SqliteException ? error.extendedResultCode : null;
      _log.log(LogCode.writeFailed, code);
      // A copy the database refuses for good (a constraint, bad text) must not
      // sit at the head of the queue and block every later copy.
      final forever =
          error is ArgumentError ||
          (error is SqliteException &&
              error.extendedResultCode == 275); // CHECK
      return forever ? _Save.neverSavable : _Save.retryLater;
    }
  }

  /// A saved item whose text is also waiting is shown once, as the newer
  /// waiting copy.
  bool _isWaiting(ClipItem item, Set<String> waitingTexts) {
    if (waitingTexts.isEmpty) return false;
    if (!item.isTruncated) return waitingTexts.contains(item.preview);
    if (!waitingTexts.any((t) => t.length > ClipItem.previewLength)) {
      return false;
    }
    final full = _store.contentOf(item.id);
    return full != null && waitingTexts.contains(full);
  }

  void _refresh() {
    try {
      final waitingTexts = {for (final w in _waiting) w.text};
      final saved = [
        for (final i in _store.list())
          if (!_isWaiting(i, waitingTexts)) i,
      ];
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
    if (_closed) return false;
    try {
      final text = _contentOf(id);
      if (text == null) return false;
      await _writeClipboard(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The whole text of an item (also one still waiting to be saved), or null
  /// if it is gone.
  String? textOf(int id) {
    if (_closed) return null;
    try {
      return _contentOf(id);
    } catch (_) {
      _log.log(LogCode.readFailed);
      return null;
    }
  }

  /// A saved setting (`picker_shortcut`, `paste_mode`), or null if it was
  /// never saved or cannot be read.
  String? setting(String key) {
    if (_closed) return null;
    try {
      return _store.readSetting(key);
    } catch (_) {
      return null;
    }
  }

  /// Saves a setting. Returns false if it could not be saved.
  bool saveSetting(String key, String value) {
    if (_closed) return false;
    try {
      _store.writeSetting(key, value);
      return true;
    } catch (error) {
      final code = error is SqliteException ? error.extendedResultCode : null;
      _log.log(LogCode.writeFailed, code);
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
    if (_closed) return null;
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
    if (_closed) return;
    try {
      _store.restore(record);
    } catch (_) {
      _log.log(LogCode.writeFailed);
    }
    _refresh();
  }

  /// Removes everything. Returns how many items went, or null if it failed.
  int? clear() {
    if (_closed) return null;
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

  /// How many items lowering the limit to [newLimit] would delete, or null
  /// when that cannot be read (the store failed, or the history is closed).
  /// Never 0 for "unknown": the Keep dialog must not show a count it could
  /// not read (reviewer W2).
  int? countRemovedBy(int newLimit) {
    if (_closed) return null;
    try {
      return _store.countRemovedBy(newLimit);
    } catch (_) {
      return null;
    }
  }

  /// Saves a new limit. Returns false if it is outside 10 to 5,000 or could
  /// not be saved.
  bool setLimit(int newLimit) {
    if (_closed) return false;
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
    pause.dispose();
    await _subscription?.cancel();
    _subscription = null;
    try {
      // One last try to save copies that are still waiting, so a quit does
      // not lose them.
      for (final w in List.of(_waiting)) {
        if (_trySave(w) != _Save.retryLater) _waiting.remove(w);
      }
    } catch (_) {}
    snippets.close();
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
    snippets.dispose();
    pause.dispose();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

enum _Save { saved, retryLater, neverSavable }

class _Waiting {
  _Waiting(this.id, this.text, this.kind, this.time);
  final int id;
  final String text;
  final ClipKind kind;
  final int time;
}
