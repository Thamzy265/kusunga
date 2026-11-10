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
  var _announceSerial = 0;
  var _saveFailed = false;
  PauseError? _error;
  var _outOfStep = false;
  var _retried = false;

  /// The last value native code accepted; null when unknown (a call
  /// failed, or none was made yet).
  int? _nativeHas;

  /// Native calls run one at a time, in the order asked (R1). Null when
  /// none is waiting, so a call made then starts at once.
  Future<void>? _tail;
  var _queued = 0;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  var _disposed = false;

  /// Goes up by one on each change worth announcing: a pause or resume by
  /// the user, and a timed pause that ended. A clock-back cut of the end
  /// time does not count (O6).
  int get announceSerial => _announceSerial;

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

  /// The user's last pause or resume failed. Kept until their next pause or
  /// resume, even when a tick puts native code back in step.
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
      if (fromTimer) _announceSerial++;
      return true;
    }
    if (_until > now + maxTimedMs) {
      _until = now + maxTimedMs;
      _save();
      return true;
    }
    return false;
  }

  /// A later save that works clears "won't last" again (B3).
  void _save() {
    _saveFailed = !_write(historyPausedSetting, '$_until');
  }

  Future<bool> _call(int until) async {
    try {
      return await _native(until);
    } catch (_) {
      return false;
    }
  }

  /// Sends a value to native code after every call asked before it has
  /// finished (R1). [value] is read when the call starts, so a call that
  /// waited sends the state as it is then. With [ifNeeded], nothing is sent
  /// when native code already has that value.
  Future<bool> _send(int Function() value, {bool ifNeeded = false}) {
    Future<bool> run() async {
      final until = value();
      if (ifNeeded && _nativeHas == until) return true;
      final ok = await _call(until);
      _nativeHas = ok ? until : null;
      return ok;
    }

    _queued++;
    final before = _tail;
    final result = before == null ? run() : before.then((_) => run());
    _tail = result.then((_) {
      if (--_queued == 0) _tail = null;
    });
    return result;
  }

  /// Dart's state as it is now. Sent synchronously when nothing waits.
  Future<void> _sendState() async {
    if (!await _send(() => _until)) _outOfStep = true;
  }

  /// After a user's pause or resume: a tick that ran while it waited may
  /// have sent an older value after it (R1). Native code gets Dart's state
  /// again once every waiting call is done, unless it already has it.
  Future<void> _resync() async {
    if (!await _send(() => _until, ifNeeded: true)) _outOfStep = true;
  }

  /// Pauses history for [length]. False if native code could not be told,
  /// and then nothing changes ("Couldn't apply the pause. Try again.").
  Future<bool> pause(PauseLength length) async {
    final minutes = length.minutes;
    final until = minutes == null ? -1 : _clock() + minutes * 60 * 1000;
    if (!await _send(() => until)) {
      _failed(PauseError.apply);
      return false;
    }
    _until = until;
    _inStep();
    _announceSerial++;
    _save();
    _log.log(LogCode.capturePaused, minutes ?? -1);
    _notify();
    await _resync();
    return true;
  }

  /// Resumes history. False if native code could not be told, and then it
  /// stays paused ("Couldn't resume. Try again.").
  Future<bool> resume() async {
    if (!await _send(() => 0)) {
      _failed(PauseError.resume);
      return false;
    }
    _until = 0;
    _inStep();
    _announceSerial++;
    _save();
    _log.log(LogCode.captureResumed, 0);
    _notify();
    await _resync();
    return true;
  }

  void _failed(PauseError error) {
    _error = error;
    _outOfStep = true;
    _retried = false;
    _notify();
  }

  /// After a user's pause or resume that native code accepted.
  void _inStep() {
    _error = null;
    _nativeInStep();
  }

  /// Native code has Dart's state again. The error stays: it is about the
  /// user's own request, which did not apply, and goes with their next
  /// pause or resume (PM decision 2026-11-10, O5).
  void _nativeInStep() {
    _outOfStep = false;
    _retried = false;
  }

  /// The 15 s tick (and becoming active): ends or cuts a timed pause, and
  /// retries a failed native call once.
  Future<void> tick() async {
    if (_disposed) return;
    final changed = _settle(fromTimer: true);
    if (changed) {
      if (await _send(() => _until)) {
        if (_outOfStep && !_retried) _nativeInStep();
      } else {
        _outOfStep = true;
      }
      _notify();
      return;
    }
    if (_outOfStep && !_retried) {
      _retried = true;
      if (await _send(() => _until)) {
        _outOfStep = false;
      }
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
