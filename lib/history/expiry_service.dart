import 'dart:async';

import 'package:flutter/widgets.dart';

import '../log/app_log.dart';
import 'history_store.dart';

/// The first moment an item is kept under [days] of auto-delete at [nowMs]:
/// items last copied before it have expired. Null for Never (0). The wall
/// clock decides (design note, "Clock"): a clock set forward deletes early,
/// one set back keeps items longer.
int? expiryCutoff(int days, int nowMs) =>
    days == 0 ? null : nowMs - days * Duration.millisecondsPerDay;

/// Auto-delete (M1.7, `docs/design/settings-and-expiry.md`, "Auto-delete").
///
/// Holds the chosen time ([days]) and runs the clean-up: once at launch
/// (after the migration, from `HistoryService.start`), on a check every
/// minute that runs it every 15 minutes or at once after a wake or a clock
/// change, when Kusunga becomes active, and right after a shorter time is
/// chosen. It runs while history is paused too. The read filter itself is
/// in `HistoryService`, which asks for [cutoff].
///
/// Logs codes only: `historyExpired` (how many items went),
/// `historyExpiryFailed`, `settingSaveFailed`, and `readFailed` for a
/// setting that is missing, unreadable or not 0, 1, 7 or 30 (treated as
/// Never).
class ExpiryService extends ChangeNotifier {
  ExpiryService({
    required this._store,
    required this._log,
    required this._onChanged,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const cleanUpEvery = Duration(minutes: 15);
  static const checkEvery = Duration(minutes: 1);

  /// Failed runs in a row before the History tab shows a warning.
  static const failuresForWarning = 3;

  final HistoryStore Function() _store;
  final ErrorLog _log;

  /// Called after every run and every change: the history refreshes (the
  /// read filter) and updates its warning banner.
  final void Function() _onChanged;
  final int Function() _clock;

  var _days = 0;
  var _failures = 0;
  int? _lastRun;
  int? _lastCheck;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  var _disposed = false;

  /// 0 (Never), 1, 7 or 30.
  int get days => _days;

  /// Items last copied before this are expired; null for Never.
  int? get cutoff => expiryCutoff(_days, _clock());

  /// True after [failuresForWarning] failed runs in a row, until a good one.
  bool get failing => _failures >= failuresForWarning;

  /// True while the minute check runs (after [startTicking]).
  bool get ticking => _timer != null;

  /// Reads the setting. Anything but 0, 1, 7 or 30 counts as Never.
  void load() {
    String? raw;
    try {
      raw = _store().readSetting(historyExpirySetting);
    } catch (_) {
      raw = null;
    }
    final days = int.tryParse(raw ?? '');
    if (raw == null ||
        days == null ||
        '$days' != raw ||
        !historyExpiryChoices.contains(days)) {
      _log.log(LogCode.readFailed);
      _days = 0;
    } else {
      _days = days;
    }
  }

  /// Deletes every expired item in one write transaction. A failure is
  /// logged and retried on the next run; the items stay hidden meanwhile.
  void cleanUp() {
    if (_disposed) return;
    _lastRun = _clock();
    final cut = cutoff;
    if (cut != null) {
      try {
        final n = _store().deleteOlderThan(cut);
        if (n > 0) _log.log(LogCode.historyExpired, n);
        _failures = 0;
      } catch (_) {
        _failures++;
        _log.log(LogCode.historyExpiryFailed);
      }
    } else {
      _failures = 0;
    }
    _changed();
  }

  /// The minute check: runs the clean-up when 15 minutes have passed since
  /// the last run, or at once when the wall clock jumped (a wake from sleep,
  /// or the clock was changed).
  void check() {
    if (_disposed) return;
    final now = _clock();
    final last = _lastCheck;
    _lastCheck = now;
    final jumped =
        last != null &&
        (now < last || now - last > 2 * checkEvery.inMilliseconds);
    final lastRun = _lastRun;
    final due =
        lastRun == null ||
        now < lastRun ||
        now - lastRun >= cleanUpEvery.inMilliseconds;
    if (jumped || due) cleanUp();
  }

  bool _isShorter(int newDays) =>
      newDays != 0 && (_days == 0 || newDays < _days);

  /// How many items choosing [newDays] would delete now: the ones still
  /// shown that are older than the new time. 0 for a longer time or Never.
  /// Null when the count cannot be read: never 0 for "unknown".
  int? countRemovedBy(int newDays) {
    checkExpiryDays(newDays);
    if (_disposed) return null;
    if (!_isShorter(newDays)) return 0;
    final now = _clock();
    try {
      return _store().countOlderThan(
        expiryCutoff(newDays, now)!,
        notBefore: expiryCutoff(_days, now),
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves [newDays]. A shorter time also deletes the expired items, in the
  /// same transaction. Returns how many items went, or null when nothing
  /// was saved (the old setting stays; `settingSaveFailed` is logged).
  /// A good save starts the failure count again, so Never (nothing left to
  /// clean up) removes the warning (tester finding B1).
  /// Throws [ArgumentError] for anything but 0, 1, 7 or 30.
  int? setDays(int newDays) {
    checkExpiryDays(newDays);
    if (_disposed) return null;
    final deleteBefore = _isShorter(newDays)
        ? expiryCutoff(newDays, _clock())
        : null;
    final int n;
    try {
      n = _store().setExpiryDays(newDays, deleteBefore: deleteBefore);
    } catch (_) {
      _log.log(LogCode.settingSaveFailed);
      return null;
    }
    _days = newDays;
    if (n > 0) _log.log(LogCode.historyExpired, n);
    _failures = 0;
    if (deleteBefore != null) _lastRun = _clock();
    _changed();
    return n;
  }

  /// Starts the minute check, and with [listenToLifecycle] also runs the
  /// clean-up when Kusunga becomes active or is shown again.
  void startTicking({bool listenToLifecycle = true}) {
    if (_disposed || _timer != null) return;
    _lastCheck = _clock();
    _timer = Timer.periodic(checkEvery, (_) => check());
    if (listenToLifecycle) {
      _lifecycle = AppLifecycleListener(onResume: cleanUp, onShow: cleanUp);
    }
  }

  void _changed() {
    if (_disposed) return;
    _onChanged();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    super.dispose();
  }
}
