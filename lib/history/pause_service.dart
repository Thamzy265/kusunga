import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
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

  /// A native call that has not answered by then counts as failed (N2): the
  /// usual retry and error rules apply, and the next call goes ahead.
  static const nativeTimeout = Duration(seconds: 2);

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

  /// A send the user did not ask for (at launch, a timer end or cut, or the
  /// re-send after a race) failed: retried on every tick until it works,
  /// and shown as [PauseError.apply] once the first retry fails too (R2).
  var _keepRetrying = false;

  /// The last value native code accepted; null when unknown (a call
  /// failed, or none was made yet).
  int? _nativeHas;

  /// Native calls run one at a time (R1): the user's in the order asked,
  /// ahead of a background send that has not started yet. When none is
  /// running, a call starts at once (synchronously).
  final _waiting = <_NativeJob>[];
  var _running = false;

  /// The background send that has not started yet; at most one (N2).
  _NativeJob? _backgroundWaiting;

  /// What listeners last saw (see [_seen]); a tick notifies only when it
  /// changed (R8).
  Object? _lastSeen;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  var _disposed = false;

  /// Goes up by one on each change worth announcing: a pause or resume by
  /// the user, and a timed pause that ended. A clock-back cut of the end
  /// time does not count (O6).
  int get announceSerial => _announceSerial;

  /// Goes up on every tick, whether or not anything changed. For a
  /// listener that retries its own failed update on the next tick (the tray,
  /// B2); the service itself notifies only on a visible change (R8).
  ValueListenable<int> get ticks => _ticks;
  final _ticks = ValueNotifier<int>(0);

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

  /// The user's last pause or resume failed, or native code could not be
  /// given the pause at launch or on a timer (R2). Kept until their next
  /// pause or resume, even when a tick puts native code back in step.
  PauseError? get error => _error;

  /// Reads the setting and sends it to native code. Called before the
  /// watcher starts: the native call is sent before [load] returns, so it
  /// reaches native code ahead of the event channel's listen (D3 A).
  ///
  /// A setting that can't be read (a database error, not a missing or
  /// garbled value) may hide "until I resume", so history stays paused
  /// until the user resumes, with the apply error showing (R2). The
  /// unread value is not overwritten.
  void load() {
    String? stored;
    var unreadable = false;
    try {
      stored = _read(historyPausedSetting);
    } catch (_) {
      unreadable = true;
    }
    if (unreadable) {
      _until = -1;
      _error = PauseError.apply;
    } else {
      final raw = int.tryParse(stored ?? '') ?? 0;
      _until = raw < -1 ? 0 : raw;
      _settle(fromTimer: false, log: false);
    }
    _lastSeen = _seen();
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

  /// A call that throws, answers false or does not answer within
  /// [nativeTimeout] has failed. A late answer is ignored: native code is
  /// then "unknown" and gets Dart's state again with the next send.
  Future<bool> _call(int until) {
    final answer = Completer<bool>();
    void settle(bool ok) {
      if (!answer.isCompleted) answer.complete(ok);
    }

    final timer = Timer(nativeTimeout, () => settle(false));
    try {
      _native(until).then(settle, onError: (Object _) => settle(false));
    } catch (_) {
      settle(false);
    }
    return answer.future.whenComplete(timer.cancel);
  }

  /// The user's own value, after the user's earlier calls and ahead of a
  /// background send that has not started (so a pause or resume waits at
  /// most one [nativeTimeout] behind a stuck background call).
  Future<bool> _sendUser(int until) {
    if (_disposed) return Future.value(false);
    final job = _NativeJob(() => until, ifNeeded: () => false);
    final at = _backgroundWaiting == null
        ? _waiting.length
        : _waiting.indexOf(_backgroundWaiting!);
    _waiting.insert(at, job);
    _pump();
    return job.done.future;
  }

  /// Dart's state, read when the send starts, so a send that waited sends
  /// the state as it is then. Requests while one waits share it (N2): ticks
  /// never pile up sends behind a stuck call. With [ifNeeded] (and no other
  /// request without it), nothing is sent when native already has it.
  Future<bool> _sendBackground({bool ifNeeded = false}) {
    if (_disposed) return Future.value(false);
    final waiting = _backgroundWaiting;
    if (waiting != null) {
      if (!ifNeeded) waiting.force = true;
      return waiting.done.future;
    }
    late final _NativeJob job;
    job = _NativeJob(
      () => _until,
      ifNeeded: () {
        if (identical(_backgroundWaiting, job)) _backgroundWaiting = null;
        return !job.force;
      },
    )..force = !ifNeeded;
    _backgroundWaiting = job;
    _waiting.add(job);
    _pump();
    return job.done.future;
  }

  /// Runs the waiting calls one by one. The first one starts synchronously
  /// when nothing is running, so [load]'s call leaves before it returns.
  void _pump() {
    if (_disposed || _running || _waiting.isEmpty) return;
    _running = true;
    final job = _waiting.removeAt(0);
    unawaited(_run(job));
  }

  Future<void> _run(_NativeJob job) async {
    final skipIfSame = job.ifNeeded();
    final until = job.value();
    var ok = true;
    if (!(skipIfSame && _nativeHas == until)) {
      ok = await _call(until);
      // After dispose the answer changes nothing (P1).
      if (!_disposed) _nativeHas = ok ? until : null;
    }
    _running = false;
    job.done.complete(ok);
    // After the caller has seen the answer (a pause sets its state first),
    // so the next send reads Dart's state as it is then.
    scheduleMicrotask(_pump);
  }

  /// Dart's state as it is now. Sent synchronously when nothing waits.
  Future<void> _sendState() async {
    if (!await _sendBackground() && !_disposed) _backgroundFailed();
  }

  /// After a user's pause or resume: a tick that ran while it waited may
  /// have sent an older value after it (R1). Native code gets Dart's state
  /// again once every waiting call is done, unless it already has it.
  Future<void> _resync() async {
    if (!await _sendBackground(ifNeeded: true) && !_disposed) {
      _backgroundFailed();
    }
  }

  void _backgroundFailed() {
    _outOfStep = true;
    _keepRetrying = true;
  }

  /// Pauses history for [length]. False if native code could not be told,
  /// and then nothing changes ("Couldn't apply the pause. Try again.").
  Future<bool> pause(PauseLength length) async {
    final minutes = length.minutes;
    final until = minutes == null ? -1 : _clock() + minutes * 60 * 1000;
    final ok = await _sendUser(until);
    if (_disposed) return false;
    if (!ok) {
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
    final ok = await _sendUser(0);
    if (_disposed) return false;
    if (!ok) {
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
    _keepRetrying = false;
  }

  /// The 15 s tick (and becoming active): ends or cuts a timed pause, and
  /// retries a failed native call: once after the user's own pause or
  /// resume failed, and on every tick after a send they did not ask for
  /// failed (R2).
  Future<void> tick() async {
    if (_disposed) return;
    _ticks.value++;
    final changed = _settle(fromTimer: true);
    if (changed) {
      final ok = await _sendBackground();
      if (_disposed) return;
      if (ok) {
        _nativeInStep();
      } else {
        _backgroundFailed();
      }
      _notifyIfSeenChanged();
      return;
    }
    if (_outOfStep && (_keepRetrying || !_retried)) {
      _retried = true;
      final ok = await _sendBackground();
      if (_disposed) return;
      if (ok) {
        _nativeInStep();
      } else if (_keepRetrying) {
        _error ??= PauseError.apply;
      }
    }
    _notifyIfSeenChanged();
  }

  /// Everything the banner, the Privacy tab and the tray show. The local
  /// date counts while a timed pause runs: "tomorrow 00:10" becomes "00:10"
  /// at midnight.
  Object _seen() {
    final now = _clock();
    final timed = isPausedAt(_until, now) && _until > 0;
    final day = timed ? DateTime.fromMillisecondsSinceEpoch(now) : null;
    return (
      paused: isPausedAt(_until, now),
      until: _until,
      error: _error,
      willLast: willLast,
      announce: _announceSerial,
      date: day == null ? null : (day.year, day.month, day.day),
    );
  }

  void _notifyIfSeenChanged() {
    if (_seen() != _lastSeen) _notify();
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

  /// True while the 15 s tick runs (after [startTicking]).
  bool get ticking => _timer != null;

  /// Stops the tick (Delete everything, M1.8); [startTicking] starts it
  /// again.
  void stopTicking() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _notify() {
    if (_disposed) return;
    _lastSeen = _seen();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // No queued call starts and none is accepted from now on (P1); their
    // callers get false and change nothing. A running call may finish.
    final queued = List.of(_waiting);
    _waiting.clear();
    _backgroundWaiting = null;
    for (final job in queued) {
      job.done.complete(false);
    }
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _ticks.dispose();
    super.dispose();
  }
}

/// One native call waiting its turn.
class _NativeJob {
  _NativeJob(this.value, {required this.ifNeeded});

  /// The value to send, read when the call starts.
  final int Function() value;

  /// Asked when the call starts: true to send nothing if native code
  /// already has the value.
  final bool Function() ifNeeded;

  /// A request that must send even when native seems to have the value.
  var force = false;
  final done = Completer<bool>();
}
