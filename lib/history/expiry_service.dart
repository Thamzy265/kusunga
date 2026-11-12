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
/// setting that is missing or not 0, 1, 7 or 30 (treated as Never), or
/// that can't be read (unknown until it can, see [load]).
class ExpiryService extends ChangeNotifier {
  ExpiryService({
    required this._store,
    required this._log,
    required this._onChanged,
    this._onUnchangedRun,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const cleanUpEvery = Duration(minutes: 15);
  static const checkEvery = Duration(minutes: 1);

  /// Failed runs in a row before the History tab shows a warning.
  static const failuresForWarning = 3;

  final HistoryStore Function() _store;
  final ErrorLog _log;

  /// Called after a change (a run that deleted items or whose warning came
  /// or went, a new time, the minute check starting): the history
  /// refreshes (the read filter) and updates its warning banner.
  final void Function() _onChanged;

  /// Called with the cut-off after a run that changed nothing for the
  /// listeners (see [cleanUp]): the history checks its list in memory
  /// (expired copies waiting to be saved, an item shown past the cut-off
  /// after a failed delete, a clock set back) and sets its expiry timer
  /// again from the wall clock, which may have jumped while the computer
  /// slept (reviewer RN2). Cheap: no store read unless the list must change.
  final void Function(int cutoff)? _onUnchangedRun;
  final int Function() _clock;

  var _days = 0;

  /// The setting could not be read (the store threw): unknown, not the
  /// user's Never. Read again at each check and clean-up (reviewer F4).
  var _unknown = false;
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

  /// Reads the setting. A missing value or anything but 0, 1, 7 or 30
  /// counts as Never. A read that throws leaves it unknown: nothing is
  /// hidden or deleted meanwhile, and it is read again at the next check or
  /// clean-up; `readFailed` is logged once until a read works.
  void load() {
    String? raw;
    try {
      raw = _store().readSetting(historyExpirySetting);
    } catch (_) {
      if (!_unknown) _log.log(LogCode.readFailed);
      _unknown = true;
      return;
    }
    _unknown = false;
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

  /// Reads the setting again while it is unknown. True when that changed
  /// the time, so the history must refresh.
  bool _reloadIfUnknown() {
    if (!_unknown) return false;
    final before = _days;
    load();
    return _days != before;
  }

  /// Deletes every expired item in one write transaction. A failure is
  /// logged and retried on the next run; the items stay hidden meanwhile.
  /// Listeners hear from a run only when it changed something: items
  /// deleted, the warning shown or gone, or the setting read at last
  /// (reviewer F11). Any other run calls the history's cheap check
  /// ([_onUnchangedRun]).
  void cleanUp() => _run(reloaded: _reloadIfUnknown());

  void _run({required bool reloaded}) {
    if (_disposed) return;
    final wasFailing = failing;
    _lastRun = _clock();
    final cut = cutoff;
    var n = 0;
    if (cut != null) {
      try {
        n = _store().deleteOlderThan(cut);
        if (n > 0) _log.log(LogCode.historyExpired, n);
        _failures = 0;
      } catch (_) {
        _failures++;
        _log.log(LogCode.historyExpiryFailed);
      }
    } else {
      _failures = 0;
    }
    if (reloaded || n > 0 || failing != wasFailing) {
      _changed();
    } else if (cut != null) {
      _onUnchangedRun?.call(cut);
    }
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
    // A setting that could be read only now applies at once, and the run
    // tells the listeners (reviewer RN1).
    final reloaded = _reloadIfUnknown();
    if (reloaded || jumped || due) _run(reloaded: reloaded);
  }

  bool _isShorter(int newDays) =>
      newDays != 0 && (_days == 0 || newDays < _days);

  /// How many items choosing [newDays] would delete now: every item older
  /// than the new time, also an expired one the clean-up has not removed
  /// yet, so the dialog's count is what [setDays] deletes and what its
  /// toast says (tester finding B2). 0 for a longer time or Never. Null
  /// when the count cannot be read: never 0 for "unknown".
  int? countRemovedBy(int newDays) {
    checkExpiryDays(newDays);
    if (_disposed) return null;
    if (!_isShorter(newDays)) return 0;
    try {
      return _store().countOlderThan(expiryCutoff(newDays, _clock())!);
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
    _unknown = false; // the user's own choice is now the setting
    if (n > 0) _log.log(LogCode.historyExpired, n);
    _failures = 0;
    if (deleteBefore != null) _lastRun = _clock();
    _changed();
    return n;
  }

  /// Starts the minute check, and with [listenToLifecycle] also runs the
  /// clean-up when Kusunga becomes active (once: coming back from hidden
  /// passes through "shown" first, reviewer F11). The history
  /// refreshes at once, so it arms its timer for the next item to expire
  /// (it only does while ticking; reviewer F2: the launch refresh in
  /// `HistoryService.start` comes before this).
  void startTicking({bool listenToLifecycle = true}) {
    if (_disposed || _timer != null) return;
    _lastCheck = _clock();
    _timer = Timer.periodic(checkEvery, (_) => check());
    if (listenToLifecycle) {
      _lifecycle = AppLifecycleListener(onResume: cleanUp);
    }
    _onChanged();
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
