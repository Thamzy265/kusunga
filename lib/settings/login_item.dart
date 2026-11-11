import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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

class LoginItemAnswer {
  const LoginItemAnswer(this.state, {this.error});
  final LoginItemState state;

  /// The OS error number, when there is one (for the log only).
  final int? error;
}

abstract interface class LoginItemPort {
  Future<LoginItemAnswer> status();

  /// Turns the login item on or off and answers the state afterwards.
  Future<LoginItemAnswer> set(bool on);

  /// Mac: opens System Settings › General › Login Items.
  Future<void> openSettings();
}

/// Method channel `com.wnasoni.kusunga/login_item` (LoginItemBridge.swift,
/// login_item_bridge.cpp). No path and no user data cross it:
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
    const failed = LoginItemAnswer(LoginItemState.failed);
    try {
      final reply = await _channel.invokeMethod<Object?>(method, arguments);
      if (reply is! Map) return failed;
      final state = _states[reply['state']];
      final error = reply['error'];
      if (state == null || (error != null && error is! int)) return failed;
      return LoginItemAnswer(state, error: error as int?);
    } on MissingPluginException {
      return failed;
    } on PlatformException {
      return failed;
    }
  }

  @override
  Future<LoginItemAnswer> status() => _call('loginItemStatus');

  @override
  Future<LoginItemAnswer> set(bool on) => _call('setLoginItem', on);

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<Object?>('openLoginItemsSettings');
    } on MissingPluginException {
      // Nothing to open.
    } on PlatformException {
      // Nothing to open.
    }
  }
}

/// Launch at login, as the Settings tab shows it. Off until the first read
/// (AC2). The state is read again when the Settings tab opens and when
/// Kusunga becomes active ([startListening]), so a change made in System
/// Settings or Task Manager shows up.
///
/// Logs codes only, for the user's own changes: `loginItemOn`,
/// `loginItemOff`, `loginItemFailed` (with the OS error number) and
/// `loginItemNeedsApproval`.
class LoginItemService extends ChangeNotifier {
  LoginItemService({required this._port, required this._log});

  final LoginItemPort _port;
  final ErrorLog _log;

  var _state = LoginItemState.off;
  bool? _pending;
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
      (_state == LoginItemState.on || _state == LoginItemState.needsApproval);

  /// False on macOS 12 (the switch is disabled).
  bool get enabled => _state != LoginItemState.unsupported;

  /// The note under the switch (UI spec, "Copy"), or null.
  String? get note => switch (_state) {
    LoginItemState.on || LoginItemState.off => null,
    LoginItemState.needsApproval =>
      'Allow Kusunga in System Settings › General › Login Items.',
    LoginItemState.failed => "Couldn't turn this on. Try again.",
    LoginItemState.unsupported => 'Needs macOS 13 or later.',
    LoginItemState.turnedOffInTaskManager => 'Turned off in Task Manager.',
  };

  /// The "Open Login Items" button shows (Mac, needs approval).
  bool get showOpenLoginItems => _state == LoginItemState.needsApproval;

  /// "Launch at login on" or "off" after the user's own change; null
  /// before any. [announceSerial] goes up with each one.
  String? get announcement => _announcement;
  int get announceSerial => _announceSerial;

  /// Reads the OS state. Ignored while a change runs.
  Future<void> refresh() async {
    if (_disposed || busy) return;
    final answer = await _port.status();
    if (_disposed || busy) return;
    _state = answer.state;
    notifyListeners();
  }

  /// Turns launch at login on or off. Ignored while another call runs and
  /// on macOS 12.
  Future<void> set(bool on) async {
    if (_disposed || busy || !enabled) return;
    _pending = on;
    notifyListeners();
    final answer = await _port.set(on);
    _pending = null;
    if (_disposed) return;
    _state = answer.state;
    switch (answer.state) {
      case LoginItemState.on:
        _log.log(LogCode.loginItemOn);
      case LoginItemState.off:
        _log.log(LogCode.loginItemOff);
      case LoginItemState.needsApproval:
        _log.log(LogCode.loginItemNeedsApproval);
      case LoginItemState.failed:
        _log.log(LogCode.loginItemFailed, answer.error);
      case LoginItemState.unsupported || LoginItemState.turnedOffInTaskManager:
        break;
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
