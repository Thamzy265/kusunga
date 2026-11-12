import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../history/pause_service.dart';
import '../log/app_log.dart';

/// What the OS says about Kusunga's login item (M1.7,
/// `docs/design/settings-and-expiry.md`, "Launch at login"). The OS is the
/// source of truth: Kusunga stores nothing about it.
enum LoginItemState {
  /// Starts at login (Mac `.enabled`, Windows Run value there and allowed).
  on,

  /// Does not start at login (Mac `.notRegistered`, no Windows Run value).
  off,

  /// Mac `.requiresApproval`: registered, but the user must allow it in
  /// System Settings › General › Login Items.
  needsApproval,

  /// Mac `.notFound` or an error, a Windows registry error, or no answer.
  failed,

  /// macOS 12: `SMAppService` needs macOS 13 (PM decision D4 B).
  unsupported,

  /// Windows: the Run value is there but Task Manager has it turned off
  /// (`StartupApproved\Run`, which Kusunga only reads).
  turnedOffInTaskManager,
}

/// Why a call answered [LoginItemState.failed].
enum LoginItemFailure {
  /// macOS `.notFound`, with no error number: the app is not where macOS
  /// can register it (a debug build run from the build folder).
  notFound,

  /// An OS error (Windows can't read its Run value), or a reply that made
  /// no sense.
  error,

  /// No answer within [ChannelLoginItemPort.timeout].
  timeout,
}

class LoginItemAnswer {
  const LoginItemAnswer(this.state, {this.error, this._failure});
  final LoginItemState state;

  /// The OS error number, when there is one (for the log only).
  final int? error;

  final LoginItemFailure? _failure;

  /// Why a failed answer failed: as given; otherwise an error when there
  /// is an OS error number, and notFound when there is none. Null for any
  /// other state.
  LoginItemFailure? get failure => state != LoginItemState.failed
      ? null
      : _failure ??
            (error != null
                ? LoginItemFailure.error
                : LoginItemFailure.notFound);
}

abstract interface class LoginItemPort {
  Future<LoginItemAnswer> status();

  /// Turns the login item on or off and answers the state afterwards.
  Future<LoginItemAnswer> set(bool on);

  /// Mac: opens System Settings › General › Login Items.
  Future<void> openSettings();
}

/// Method channel `com.wnasoni.kusunga/login_item` (LoginItemBridge.swift,
/// login_item_bridge.cpp). No path and no user data cross it, and a call
/// with no answer within [timeout] counts as failed:
///  - `loginItemStatus` (no arguments) and `setLoginItem` (a bool) answer
///    `{state, error?}`: state is `enabled`, `notRegistered`,
///    `requiresApproval`, `notFound`, `error`, `unsupported` or
///    `disabledByUser`; error an OS error number;
///  - `openLoginItemsSettings` (no arguments, Mac only).
class ChannelLoginItemPort implements LoginItemPort {
  ChannelLoginItemPort({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.wnasoni.kusunga/login_item');

  final MethodChannel _channel;

  /// A call with no answer by then has failed: the native-call limit of
  /// M1.6 ([PauseService.nativeTimeout], tester finding B4). A late answer
  /// is ignored.
  static const timeout = PauseService.nativeTimeout;

  static const _states = {
    'enabled': LoginItemState.on,
    'notRegistered': LoginItemState.off,
    'requiresApproval': LoginItemState.needsApproval,
    'notFound': LoginItemState.failed,
    'error': LoginItemState.failed,
    'unsupported': LoginItemState.unsupported,
    'disabledByUser': LoginItemState.turnedOffInTaskManager,
  };

  Future<LoginItemAnswer> _call(String method, [Object? arguments]) async {
    const failed = LoginItemAnswer(
      LoginItemState.failed,
      failure: LoginItemFailure.error,
    );
    try {
      final reply = await _channel
          .invokeMethod<Object?>(method, arguments)
          .timeout(timeout);
      if (reply is! Map) return failed;
      final state = _states[reply['state']];
      final error = reply['error'];
      if (state == null || (error != null && error is! int)) return failed;
      return LoginItemAnswer(
        state,
        error: error as int?,
        failure: switch (reply['state']) {
          'notFound' => LoginItemFailure.notFound,
          'error' => LoginItemFailure.error,
          _ => null,
        },
      );
    } on MissingPluginException {
      return failed;
    } on PlatformException {
      return failed;
    } on TimeoutException {
      return const LoginItemAnswer(
        LoginItemState.failed,
        failure: LoginItemFailure.timeout,
      );
    }
  }

  @override
  Future<LoginItemAnswer> status() => _call('loginItemStatus');

  @override
  Future<LoginItemAnswer> set(bool on) => _call('setLoginItem', on);

  @override
  Future<void> openSettings() async {
    try {
      await _channel
          .invokeMethod<Object?>('openLoginItemsSettings')
          .timeout(timeout);
    } on MissingPluginException {
      // Nothing to open.
    } on PlatformException {
      // Nothing to open.
    } on TimeoutException {
      // Nothing more to do.
    }
  }
}

/// Launch at login, as the Settings tab shows it. Off until the first read
/// (AC2). The state is read again when the Settings tab opens and when
/// Kusunga becomes active ([startListening]), so a change made in System
/// Settings or Task Manager shows up, and straight after a change that
/// failed, so the switch shows what the OS still has (R4, tester finding
/// B3).
///
/// Logs codes only: for the user's own changes `loginItemOn`,
/// `loginItemOff`, `loginItemFailed` (with the OS error number) and
/// `loginItemNeedsApproval`; and `loginItemFailed` (with its number, none
/// for notFound or no answer) for the first plain read in a row that fails
/// (reviewer P2).
class LoginItemService extends ChangeNotifier {
  LoginItemService({required this._port, required this._log});

  final LoginItemPort _port;
  final ErrorLog _log;

  var _state = LoginItemState.off;

  /// Why the state shown is [LoginItemState.failed].
  LoginItemFailure? _failure;

  /// The last position the OS reported in this run (off until it reports
  /// one; notFound reports off), shown when a plain read can't tell: an
  /// error or no answer (lead's ruling 2026-11-12, reviewer P1). Windows
  /// can fail to read its Run value while it is there.
  var _lastReportedOn = false;

  /// A plain read failed and was logged; a read that works ends the run
  /// (reviewer P2).
  var _readFailing = false;
  bool? _pending;

  /// The position the user asked for when that change failed and did not
  /// happen (the read after it failed too, or shows the switch elsewhere):
  /// kept until a read answers a state of its own, or the next change.
  bool? _failedTo;
  var _announceSerial = 0;
  String? _announcement;
  AppLifecycleListener? _lifecycle;
  var _disposed = false;

  LoginItemState get state => _state;

  /// True while an OS call runs: other input is ignored until it returns.
  bool get busy => _pending != null;

  /// The switch position. While a change runs, the new position.
  bool get isOn =>
      _pending ??
      switch (_state) {
        LoginItemState.on || LoginItemState.needsApproval => true,
        LoginItemState.failed => switch (_failedTo) {
          // A change failed and the OS could not be read either: the switch
          // stays where it was ("Where it was", PM 2026-11-11).
          final failedTo? => !failedTo,
          // A plain read: notFound shows off (QA-M17-1); an error or no
          // answer keeps what the OS last reported (P1).
          null => _failure != LoginItemFailure.notFound && _lastReportedOn,
        },
        _ => false,
      };

  /// False on macOS 12 (the switch is disabled).
  bool get enabled => _state != LoginItemState.unsupported;

  /// The note under the switch (UI spec, "Copy"), or null. A failure note
  /// shows only after a change the user asked for has failed: while the
  /// switch is not where the user asked, or the OS could not be read. A
  /// plain read that answers notFound or an error (at launch, on tab open,
  /// on becoming active; a debug build run from the build folder) shows the
  /// switch off with no note (QA-M17-1, lead's ruling 2026-11-12). While
  /// the next change runs, no failure note shows; a note about the OS state
  /// (approval, Task Manager) stays.
  String? get note {
    final failedTo = _failedTo;
    if (failedTo != null &&
        _state != LoginItemState.unsupported &&
        (_state == LoginItemState.failed || isOn != failedTo)) {
      return failedTo ? _cantTurnOn : _cantTurnOff;
    }
    return switch (_state) {
      LoginItemState.on || LoginItemState.off || LoginItemState.failed => null,
      LoginItemState.needsApproval =>
        'Allow Kusunga in System Settings › General › Login Items.',
      LoginItemState.unsupported => 'Needs macOS 13 or later.',
      LoginItemState.turnedOffInTaskManager => 'Turned off in Task Manager.',
    };
  }

  static const _cantTurnOn = "Couldn't turn this on. Try again.";
  static const _cantTurnOff = "Couldn't turn this off. Try again.";

  /// The "Open Login Items" button shows (Mac, needs approval).
  bool get showOpenLoginItems => _state == LoginItemState.needsApproval;

  /// "Launch at login on" or "off" after the user's own change; null
  /// before any. [announceSerial] goes up with each one.
  String? get announcement => _announcement;
  int get announceSerial => _announceSerial;

  /// Reads the OS state. Ignored while a change runs. A read that fails
  /// keeps the note of a failed change; any other answer clears it. The
  /// first read in a row that fails is logged (P2).
  Future<void> refresh() async {
    if (_disposed || busy) return;
    final answer = await _port.status();
    if (_disposed || busy) return;
    if (answer.state == LoginItemState.failed) {
      if (!_readFailing) _log.log(LogCode.loginItemFailed, answer.error);
      _readFailing = true;
    } else {
      _failedTo = null;
    }
    _show(answer);
    notifyListeners();
  }

  /// Takes [answer] as what the switch shows; a real state is also the
  /// last position the OS reported, and ends a run of failing reads. A
  /// notFound answer counts as the OS reporting off (lead's ruling
  /// 2026-11-12, tester finding N4), but is still a failing read.
  void _show(LoginItemAnswer answer) {
    _state = answer.state;
    _failure = answer.failure;
    if (answer.failure == LoginItemFailure.notFound) _lastReportedOn = false;
    if (answer.state == LoginItemState.failed) return;
    _readFailing = false;
    _lastReportedOn =
        answer.state == LoginItemState.on ||
        answer.state == LoginItemState.needsApproval;
  }

  /// Turns launch at login on or off. Ignored while another call runs and
  /// on macOS 12. A change that fails is followed by a read, still counted
  /// as part of the change (input stays ignored), and the switch shows what
  /// that read says.
  Future<void> set(bool on) async {
    if (_disposed || busy || !enabled) return;
    _pending = on;
    _failedTo = null;
    notifyListeners();
    final answer = await _port.set(on);
    if (_disposed) return;
    var shown = answer;
    if (answer.state == LoginItemState.failed) {
      _log.log(LogCode.loginItemFailed, answer.error);
      shown = await _port.status();
      if (_disposed) return;
      final state = shown.state;
      // When the OS already has what the user asked (applied late, or the
      // error came after the change), nothing failed for the user: no note
      // now, and a later unreadable read can't bring one back or move the
      // switch (tester finding TN2, R4).
      final shownOn =
          state == LoginItemState.on || state == LoginItemState.needsApproval;
      if (state == LoginItemState.failed || shownOn != on) _failedTo = on;
    }
    _pending = null;
    _show(shown);
    switch (answer.state) {
      case LoginItemState.on:
        _log.log(LogCode.loginItemOn);
      case LoginItemState.off:
        _log.log(LogCode.loginItemOff);
      case LoginItemState.needsApproval:
        _log.log(LogCode.loginItemNeedsApproval);
      case LoginItemState.failed ||
          LoginItemState.unsupported ||
          LoginItemState.turnedOffInTaskManager:
        break; // a failure is logged before the read
    }
    _announcement = isOn ? 'Launch at login on' : 'Launch at login off';
    _announceSerial++;
    notifyListeners();
  }

  Future<void> openLoginItems() => _port.openSettings();

  /// Reads the state again whenever Kusunga becomes active.
  void startListening() {
    if (_disposed || _lifecycle != null) return;
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(refresh()),
      onShow: () => unawaited(refresh()),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycle?.dispose();
    super.dispose();
  }
}
