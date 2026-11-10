import 'dart:async';

import 'package:flutter/widgets.dart';

import '../log/app_log.dart';

/// The setting that keeps a pause across a restart (PM decision D3 A): "0"
/// not paused, "-1" paused until resumed, otherwise the end time in ms since
/// 1970 (UTC).
const historyPausedSetting = 'history_paused_until';

/// The three lengths the tray and the Privacy tab offer.
enum PauseLength {
  quarterHour(15),
  hour(60),
  untilResumed(null);

  const PauseLength(this.minutes);

  /// Null for "until I resume".
  final int? minutes;
}

/// A native call failed, so native code and Dart may be out of step.
enum PauseError {
  /// "Couldn't apply the pause. Try again."
  apply,

  /// "Couldn't resume. Try again."
  resume,
}

/// True while [until] says paused at [nowMs]. At the end time the pause is
/// over (the same rule as the native watchers).
bool isPausedAt(int until, int nowMs) => until == -1 || until > nowMs;

/// "14:30", "2:30 PM", or "tomorrow 00:10" when [end] is not today (UI spec,
/// "Long content"). A pause is at most an hour, so it never ends later than
/// tomorrow.
String formatPauseEnd(DateTime end, DateTime now, {required bool use24Hour}) {
  final String time;
  if (use24Hour) {
    time =
        '${end.hour.toString().padLeft(2, '0')}:'
        '${end.minute.toString().padLeft(2, '0')}';
  } else {
    final hour = end.hour % 12 == 0 ? 12 : end.hour % 12;
    time =
        '$hour:${end.minute.toString().padLeft(2, '0')} '
        '${end.hour < 12 ? 'AM' : 'PM'}';
  }
  final sameDay =
      end.year == now.year && end.month == now.month && end.day == now.day;
  return sameDay ? time : 'tomorrow $time';
}

/// "Pause history" (M1.6, design note "Pause clock"). Holds the pause end
/// time, keeps it in the setting and in native code, and ends a timed pause.
///
/// Native code compares the end time with the wall clock on every copy
/// (ADR 0005), so capture stops and starts on time even if this service's
/// timer runs late. This service only keeps the UI and the setting in step:
/// on a 15 s tick and when Kusunga becomes active.
///
/// Logs codes only: `capturePaused` (15, 60, or -1 for until resumed) and
/// `captureResumed` (0 the user, 1 the timer).
class PauseService extends ChangeNotifier {
  PauseService({
    required Future<bool> Function(int until) setNativePause,
    required String? Function(String key) readSetting,
    required bool Function(String key, String value) writeSetting,
    required this._log,
    required this.persists,
    int Function()? clock,
  }) : _native = setNativePause,
       _read = readSetting,
       _write = writeSetting,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// The longest a timed pause can still have to run. A longer one means the
  /// clock was set back; it is cut to now + 60 minutes.
  static const maxTimedMs = 60 * 60 * 1000;
  static const tickEvery = Duration(seconds: 15);

  /// False in memory-only mode: a pause applies for this session only.
  final bool persists;

  final Future<bool> Function(int until) _native;
  final String? Function(String key) _read;
  final bool Function(String key, String value) _write;
  final ErrorLog _log;
  final int Function() _clock;

  var _until = 0;
  var _saveFailed = false;
  PauseError? _error;
  var _outOfStep = false;
  var _retried = false;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  var _disposed = false;

  /// The wall clock this service uses, in local time.
  DateTime get now => DateTime.fromMillisecondsSinceEpoch(_clock());

  /// 0, -1 or an end time in ms (see [historyPausedSetting]).
  int get pausedUntil => _until;

  bool get isPaused => isPausedAt(_until, _clock());
  bool get untilResumed => _until == -1;

  /// When a timed pause ends, in local time; null otherwise.
  DateTime? get endsAt => isPaused && _until > 0
      ? DateTime.fromMillisecondsSinceEpoch(_until)
      : null;

  /// False when the pause won't last after Kusunga quits (memory-only mode,
  /// or the setting could not be saved).
  bool get willLast => persists && !_saveFailed;

  /// The last native call failed and has not been put right yet.
  PauseError? get error => _error;

  /// Reads the setting and sends it to native code. Called before the
  /// watcher starts: the native call is sent before [load] returns, so it
  /// reaches native code ahead of the event channel's listen (D3 A).
  void load() {
    final raw = int.tryParse(_read(historyPausedSetting) ?? '') ?? 0;
    _until = raw < -1 ? 0 : raw;
    _settle(fromTimer: false, log: false);
    unawaited(_sendState());
  }

  /// Ends a timed pause that is over, and cuts one that runs too long.
  /// Returns true if [_until] changed.
  bool _settle({required bool fromTimer, bool log = true}) {
    if (_until <= 0) return false;
    final now = _clock();
    if (!isPausedAt(_until, now)) {
      _until = 0;
      _save();
      if (log && fromTimer) _log.log(LogCode.captureResumed, 1);
      return true;
    }
    if (_until > now + maxTimedMs) {
      _until = now + maxTimedMs;
      _save();
      return true;
    }
    return false;
  }

  void _save() {
    if (!_write(historyPausedSetting, '$_until')) _saveFailed = true;
  }

  Future<bool> _call(int until) async {
    try {
      return await _native(until);
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendState() async {
    final ok = await _call(_until);
    if (!ok) _outOfStep = true;
  }

  /// Pauses history for [length]. False if native code could not be told,
  /// and then nothing changes ("Couldn't apply the pause. Try again.").
  Future<bool> pause(PauseLength length) async {
    final minutes = length.minutes;
    final until = minutes == null ? -1 : _clock() + minutes * 60 * 1000;
    if (!await _call(until)) {
      _failed(PauseError.apply);
      return false;
    }
    _until = until;
    _inStep();
    _save();
    _log.log(LogCode.capturePaused, minutes ?? -1);
    _notify();
    return true;
  }

  /// Resumes history. False if native code could not be told, and then it
  /// stays paused ("Couldn't resume. Try again.").
  Future<bool> resume() async {
    if (!await _call(0)) {
      _failed(PauseError.resume);
      return false;
    }
    _until = 0;
    _inStep();
    _save();
    _log.log(LogCode.captureResumed, 0);
    _notify();
    return true;
  }

  void _failed(PauseError error) {
    _error = error;
    _outOfStep = true;
    _retried = false;
    _notify();
  }

  void _inStep() {
    _error = null;
    _outOfStep = false;
    _retried = false;
  }

  /// The 15 s tick (and becoming active): ends or cuts a timed pause, and
  /// retries a failed native call once.
  Future<void> tick() async {
    if (_disposed) return;
    final changed = _settle(fromTimer: true);
    if (changed) {
      if (await _call(_until)) {
        if (_outOfStep && !_retried) _inStep();
      } else {
        _outOfStep = true;
      }
      _notify();
      return;
    }
    if (_outOfStep && !_retried) {
      _retried = true;
      if (await _call(_until)) _inStep();
    }
    _notify();
  }

  /// Starts the 15 s tick, and with [listenToLifecycle] also ticks when
  /// Kusunga becomes active or is shown again (after sleep the tick also
  /// comes within 15 s, since Dart timers resume on wake).
  void startTicking({bool listenToLifecycle = true}) {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(tickEvery, (_) => unawaited(tick()));
    if (listenToLifecycle) {
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(tick()),
        onShow: () => unawaited(tick()),
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
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
