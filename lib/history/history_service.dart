import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../clipboard/clipboard_source.dart';
import '../data/export_format.dart';
import '../log/app_log.dart';
import 'clip_classifier.dart';
import 'clip_item.dart';
import 'expiry_service.dart';
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

  /// Auto-delete failed 3 runs in a row (M1.7); gone after a good run.
  expiryFailed,
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
       keychainUnusable = notices.contains(HistoryNotice.memoryOnly),
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
      // A read error reaches the pause as an error, not as "no setting":
      // it must not quietly undo "until I resume" (R2).
      readSetting: _readPauseSetting,
      writeSetting: saveSetting,
      log: _log,
      persists: _persists,
      clock: _clock,
    );
    expiry = ExpiryService(
      store: () => _store,
      log: _log,
      onChanged: _onExpiryChanged,
      onUnchangedRun: _afterUnchangedExpiryRun,
      clock: _clock,
    );
  }

  /// Auto-delete (M1.7), kept in the same settings table. Its cut-off is
  /// the read filter of every list this service gives out (R1).
  late final ExpiryService expiry;

  /// "Pause history" (M1.6), kept in the same settings table.
  late final PauseService pause;

  /// The saved snippets, on the same database (M1.4). Editing is off when
  /// this session is memory only.
  late final SnippetService snippets;

  /// The typed-shortcut ignore list, on the same database (M1.5).
  final IgnoredAppStore ignoredApps;

  /// The keychain or the data folder could not be used, so this session is
  /// memory only (not a newer or failed file). Delete everything then only
  /// tries the key delete (M1.8 design note, "Memory-only mode").
  final bool keychainUnusable;

  /// Import is offered only while history is saved (lead ruling G2).
  bool get canImport => _persists && !_closed;

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

  /// Goes up with each [setCaptureIgnored] call; a retry is sent only while
  /// its call is still the newest (R3).
  var _ignoredSerial = 0;

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
    // Auto-delete first (after the migration, which ran at open): nothing
    // expired is ever shown, and the clean-up runs at launch.
    expiry.load();
    expiry.cleanUp();
    _refresh(); // the first list
    pause.load();
    List<String> ids;
    try {
      ids = [for (final a in ignoredApps.list()) a.appId];
    } catch (_) {
      // Never an empty list: the presets keep password managers out (R4).
      _log.log(LogCode.readFailed);
      ids = [for (final a in presetIgnoredApps) a.appId];
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
  ///
  /// A call that fails is tried once more; if that fails too, the code
  /// `captureIgnoredSendFailed` is logged (never an app id) and the watcher
  /// keeps its last list until the next change (O2).
  ///
  /// A newer call takes over from an older one: the older one's retry is
  /// dropped (answering false, with nothing logged), so an older list never
  /// reaches the watcher after a newer one (R3).
  Future<bool> setCaptureIgnored(List<String> appIds) async {
    final serial = ++_ignoredSerial;
    Future<bool> once() async {
      try {
        return await _source.setCaptureIgnored(appIds);
      } catch (_) {
        return false;
      }
    }

    if (await once()) return true;
    if (serial != _ignoredSerial) return false;
    if (await once()) return true;
    if (serial != _ignoredSerial) return false;
    _log.log(LogCode.captureIgnoredSendFailed);
    return false;
  }

  Future<void> recheckPasteAccess() async {
    final access = await _source.pasteAccess();
    if (_closed || access == _pasteAccess) return;
    _pasteAccess = access;
    _notify();
  }

  void _onEvent(ClipboardEvent event) {
    if (_closed || _captureStopped) return;
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

  /// Drops copies still waiting to be saved that were copied before
  /// [cutoff]: an expired copy is never written (reviewer F6). True when
  /// any went.
  bool _dropExpiredWaiting(int? cutoff) {
    if (cutoff == null || _waiting.isEmpty) return false;
    final before = _waiting.length;
    _waiting.removeWhere((w) => w.time < cutoff);
    if (_waiting.length == before) return false;
    if (_waiting.isEmpty) _banners.remove(HistoryBanner.writeError);
    return true;
  }

  void _flushWaiting() {
    _dropExpiredWaiting(expiry.cutoff);
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

  void _onExpiryChanged() {
    if (_closed) return;
    // An expired copy waiting to be saved is never written (F6).
    _dropExpiredWaiting(expiry.cutoff);
    if (expiry.failing) {
      _banners.add(HistoryBanner.expiryFailed);
    } else {
      _banners.remove(HistoryBanner.expiryFailed);
    }
    _refresh();
  }

  /// After an auto-delete run that changed nothing for the listeners: drops
  /// expired copies waiting to be saved (F6), and reads the list again only
  /// when it must change (one of them went, an item shown is past the
  /// cut-off because its delete failed, or the clock was set back so hidden
  /// items may show again). Otherwise only the expiry timer is set again
  /// from the wall clock, which may have jumped during a sleep (RN2).
  void _afterUnchangedExpiryRun(int cutoff) {
    if (_closed) return;
    final dropped = _dropExpiredWaiting(cutoff);
    final listed = _listedCutoff;
    if (dropped ||
        (listed != null && cutoff < listed) ||
        _items.any((i) => i.lastCopiedAt < cutoff)) {
      _refresh();
    } else {
      _scheduleExpiryRefresh(cutoff);
    }
  }

  /// The cut-off the list was last read with (null: Never, or not read).
  int? _listedCutoff;

  /// Refreshes the list when its oldest item expires, so it leaves History
  /// and the picker on time, between clean-ups (R1). Only while the
  /// expiry check runs (the app, not a test that never starts it).
  Timer? _expiryRefresh;

  /// After a failed read the next refresh waits at least one minute check,
  /// so a store that can't be read is not tried (and logged) every second
  /// (reviewer F3).
  void _scheduleExpiryRefresh(int? cutoff, {bool afterFailure = false}) {
    _expiryRefresh?.cancel();
    _expiryRefresh = null;
    if (cutoff == null || !expiry.ticking || _items.isEmpty || _closed) return;
    var oldest = _items.first.lastCopiedAt;
    for (final i in _items) {
      if (i.lastCopiedAt < oldest) oldest = i.lastCopiedAt;
    }
    // Shown while lastCopiedAt >= cutoff; the cut-off moves with the clock.
    final wait = oldest - cutoff + 1;
    final least = afterFailure ? ExpiryService.checkEvery.inMilliseconds : 1000;
    _expiryRefresh = Timer(
      Duration(milliseconds: wait < least ? least : wait),
      _refresh,
    );
  }

  void _refresh() {
    final cutoff = expiry.cutoff;
    _listedCutoff = cutoff;
    var failed = false;
    try {
      final waitingTexts = {for (final w in _waiting) w.text};
      final saved = [
        for (final i
            in cutoff == null ? _store.list() : _store.listSince(cutoff))
          if (!_isWaiting(i, waitingTexts)) i,
      ];
      _items = [
        for (final w in _waiting.reversed)
          if (cutoff == null || w.time >= cutoff)
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
      failed = true;
      // The list in memory still loses what has expired (R1, reviewer F3).
      if (cutoff != null) {
        _items = [
          for (final i in _items)
            if (i.lastCopiedAt >= cutoff) i,
        ];
      }
    }
    _scheduleExpiryRefresh(cutoff, afterFailure: failed);
    _notify();
  }

  /// Puts the whole text of an item on the clipboard. Returns false if that
  /// failed, or the item is gone or expired. The watcher then sees the copy
  /// and moves the item to the top.
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
  /// if it is gone or expired (R1: the read filter holds for an id kept
  /// from before, too).
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

  /// The pause setting for [PauseService]: like [setting], but a read
  /// error is logged and thrown, not answered as "no setting" (R2).
  String? _readPauseSetting(String key) {
    if (_closed) return null;
    try {
      return _store.readSetting(key);
    } catch (_) {
      _log.log(LogCode.readFailed);
      rethrow;
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
    final cutoff = expiry.cutoff;
    if (id < 0) {
      for (final w in _waiting) {
        if (w.id != id) continue;
        return cutoff == null || w.time >= cutoff ? w.text : null;
      }
      return null;
    }
    return _store.contentOf(id, notBefore: cutoff);
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
  ///
  /// Only items that are shown count: expired ones the clean-up has not
  /// removed yet are the oldest, so the trim takes them too, but they were
  /// never the user's to see (M1.7 reviewer F5).
  int? countRemovedBy(int newLimit) {
    if (_closed) return null;
    try {
      final all = _store.countRemovedBy(newLimit);
      final cutoff = expiry.cutoff;
      if (cutoff == null || all == 0) return all;
      final shown = _store.count - _store.countOlderThan(cutoff);
      return shown > newLimit ? shown - newLimit : 0;
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

  // ---- Your data (M1.8) ----

  /// Everything to export: the snippets, the settings that travel (G1),
  /// the ignore list and, with [includeHistory], the items shown now (an
  /// expired item is never exported, R1 of M1.7). Throws if the store
  /// can't be read.
  ExportBundle exportBundle({required bool includeHistory}) {
    final cutoff = expiry.cutoff;
    String? read(String key) => _store.readSetting(key);
    final typed = read('typed_shortcuts_on');
    final paste = read('paste_mode');
    final days = int.tryParse(read(historyExpirySetting) ?? '');
    return ExportBundle(
      snippets: [
        for (final s in snippets.records())
          ExportSnippet(
            name: s.name,
            content: s.content,
            type: s.type,
            position: s.position,
            shortcut: s.shortcut,
          ),
      ],
      history: includeHistory
          ? [
              for (final w in _waiting.reversed)
                if (cutoff == null || w.time >= cutoff)
                  ExportHistoryItem(
                    content: w.text,
                    kind: w.kind,
                    createdAt: w.time,
                    lastCopiedAt: w.time,
                  ),
              for (final r in _store.records(notBefore: cutoff))
                if (!_waiting.any((w) => w.text == r.content))
                  ExportHistoryItem(
                    content: r.content,
                    kind: r.kind,
                    createdAt: r.createdAt,
                    lastCopiedAt: r.lastCopiedAt,
                  ),
            ]
          : null,
      settings: ExportSettings(
        historyLimit: _store.limit,
        historyExpiryDays: days != null && historyExpiryChoices.contains(days)
            ? days
            : null,
        typedShortcutsOn: typed == null ? null : typed == '1',
        pasteMode: paste == 'auto' || paste == 'copy_only' ? paste : null,
      ),
      ignoredApps: ignoredApps.list(),
    );
  }

  /// How many of the file's history items an import would add: those not
  /// older than the auto-delete time (lead ruling G5).
  int importableHistory(ExportBundle bundle) {
    final cutoff = expiry.cutoff;
    final history = bundle.history ?? const [];
    if (cutoff == null) return history.length;
    return history.where((h) => h.lastCopiedAt >= cutoff).length;
  }

  /// Adds a checked file in one transaction (R2, R3) and shows the result
  /// at once: the list, the snippets and, with [applySettings], the limit,
  /// auto-delete and the ignore list sent to the clipboard watcher. Throws
  /// if it failed; then nothing changed.
  ImportCounts importBundle(
    ExportBundle bundle, {
    required bool applySettings,
  }) {
    if (!canImport) throw StateError('import needs a saved history');
    final counts = _store.importBundle(
      bundle,
      applySettings: applySettings,
      notBefore: expiry.cutoff,
      nowMs: _clock(),
    );
    if (applySettings) {
      expiry.load();
      expiry.cleanUp();
      try {
        unawaited(
          setCaptureIgnored([for (final a in ignoredApps.list()) a.appId]),
        );
      } catch (_) {
        _log.log(LogCode.readFailed);
      }
    }
    snippets.reload();
    _refresh();
    return counts;
  }

  /// "Delete all history" (D4 A): Clear history, then VACUUM so the freed
  /// pages are gone from the file. The key, snippets and settings stay.
  /// Returns how many items went, or null if the clear failed.
  int? deleteAllHistory() {
    final n = clear();
    if (n == null) return null;
    try {
      _store.compact();
    } catch (error) {
      final code = error is SqliteException ? error.extendedResultCode : null;
      _log.log(LogCode.writeFailed, code);
    }
    return n;
  }

  var _captureStopped = false;
  var _expiryWasTicking = false;
  var _pauseWasTicking = false;

  /// Delete everything stops capture and the timers before the key goes
  /// (lead ruling 2026-11-12): no copy is written after that.
  void stopCapture() {
    if (_captureStopped) return;
    _captureStopped = true;
    _expiryWasTicking = expiry.ticking;
    _pauseWasTicking = pause.ticking;
    expiry.stopTicking();
    pause.stopTicking();
    _expiryRefresh?.cancel();
    _expiryRefresh = null;
  }

  /// The key could not be deleted: recording carries on as before.
  void resumeCapture() {
    if (!_captureStopped || _closed) return;
    _captureStopped = false;
    if (_expiryWasTicking) expiry.startTicking();
    if (_pauseWasTicking) pause.startTicking();
    _refresh();
  }

  void dismiss(HistoryBanner banner) {
    if (_banners.remove(banner)) _notify();
  }

  /// Stops listening and closes the database cleanly. Safe to call more than
  /// once. Called on every exit path.
  ///
  /// [saveWaiting] false (Delete everything): copies still waiting are
  /// dropped, not written to a file that is about to be deleted.
  Future<void> close({bool saveWaiting = true}) async {
    if (_closed) return;
    _closed = true;
    pause.dispose();
    expiry.dispose();
    _expiryRefresh?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    try {
      // One last try to save copies that are still waiting, so a quit does
      // not lose them (but never one that has expired).
      if (!saveWaiting) _waiting.clear();
      _dropExpiredWaiting(expiry.cutoff);
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
    expiry.dispose();
    _expiryRefresh?.cancel();
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
