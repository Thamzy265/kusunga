import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'window_service.dart';

/// The app's window, as far as [WindowManagerPort] needs it: one for one with
/// window_manager's native API (ADR 0009). Tests pass a fake.
abstract interface class WindowHandle {
  void setMinimumSize(Size size);
  void setSize(Size size);

  /// Cancels every close request (close button) and calls
  /// [onCloseRequested] instead.
  void preventClose(void Function() onCloseRequested);
  void show();
  void focus();
  void hide();

  /// Removes the close listener.
  void dispose();
}

abstract interface class WindowBackend {
  /// The app's window, or null while the platform cannot name it yet.
  WindowHandle? findWindow();
}

/// [WindowPort] backed by the `window_manager` plugin through
/// [WindowBackend].
///
/// The window is looked up once and then kept. On a hidden start (Windows
/// `--login`) the platform may not name it at first (design note API-A), so
/// the lookup is tried again every [retryEvery], up to [maxRetries] times, and
/// on every [show] and [hide]. A [show] asked for before then is done as soon
/// as the window is found.
class WindowManagerPort implements WindowPort {
  WindowManagerPort({
    WindowBackend? backend,
    this.retryEvery = const Duration(milliseconds: 250),
    this.maxRetries = 120,
  }) : _backend = backend ?? NativeWindowBackend();

  final WindowBackend _backend;
  final Duration retryEvery;
  final int maxRetries;
  final _closes = StreamController<void>.broadcast();
  WindowHandle? _window;
  Timer? _retry;
  var _initRequested = false;
  var _showPending = false;
  var _disposed = false;

  @override
  Stream<void> get closeRequests => _closes.stream;

  @override
  Future<void> init() async {
    _initRequested = true;
    final window = _window;
    if (window != null) {
      _setUp(window);
    } else if (_find() == null) {
      _retryLater();
    }
  }

  /// Never throws: a set-up that fails must not stop what comes after it (a
  /// pending show, the caller's own show or hide, or the app's close
  /// listener). Only the error type is logged. The window is kept, and only
  /// a later [init] sets it up again.
  void _setUp(WindowHandle window) {
    try {
      window
        ..setMinimumSize(const Size(360, 400))
        ..setSize(const Size(800, 632))
        ..preventClose(_onCloseRequested);
    } catch (error) {
      debugPrint('Kusunga: window set-up failed (${error.runtimeType})');
    }
  }

  WindowHandle? _find() {
    final known = _window;
    if (known != null || _disposed) return known;
    final window = _backend.findWindow();
    if (window != null) _adopt(window);
    return window;
  }

  void _adopt(WindowHandle window) {
    _window = window;
    _retry?.cancel();
    _retry = null;
    if (_initRequested) _setUp(window);
    if (_showPending) {
      _showPending = false;
      window
        ..show()
        ..focus();
    }
  }

  void _retryLater() {
    if (_retry != null || _disposed) return;
    var tries = 0;
    var failed = 0;
    _retry = Timer.periodic(retryEvery, (timer) {
      tries++;
      // While this timer runs there is no window yet and the port is not
      // disposed: finding the window or dispose cancels it.
      WindowHandle? window;
      try {
        window = _backend.findWindow();
      } catch (_) {
        // A lookup that throws is a miss, not an uncaught error on every tick.
        failed++;
      }
      if (window != null) {
        try {
          _adopt(window);
        } catch (error) {
          // The set-up logs its own failures, so only a pending show can
          // throw here. The window is kept and the retry is over. Only the
          // error type is logged.
          debugPrint('Kusunga: window show failed (${error.runtimeType})');
        }
        return;
      }
      if (tries >= maxRetries) {
        timer.cancel();
        _retry = null;
        debugPrint(
          'Kusunga: window not found; retried $tries times'
          '${failed > 0 ? '; $failed failed' : ''}',
        );
      }
    });
  }

  void _onCloseRequested() {
    if (!_closes.isClosed) _closes.add(null);
  }

  @override
  Future<void> show() async {
    _showPending = false;
    final window = _find();
    if (window == null) {
      _showPending = true;
      return;
    }
    window
      ..show()
      ..focus();
  }

  @override
  Future<void> hide() async {
    _showPending = false;
    _find()?.hide();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    _retry = null;
    final window = _window;
    _window = null;
    try {
      window?.dispose();
    } finally {
      await _closes.close();
    }
  }
}

/// The real [WindowBackend]: nativeapi's current window (macOS: the main
/// window, else the first one; Windows: the active window, else this
/// process's titled top-level window, hidden or not).
class NativeWindowBackend implements WindowBackend {
  @override
  WindowHandle? findWindow() {
    final window = WindowManager.instance.getCurrent();
    return window == null ? null : _NativeWindow(window);
  }
}

class _NativeWindow implements WindowHandle {
  _NativeWindow(this._window);

  // Kept for as long as the port lives: nativeapi stops a listener when its
  // Dart object is collected.
  final Window _window;
  ListenerId? _closeListener;

  @override
  void setMinimumSize(Size size) => _window.minimumSize = size.toNative();

  @override
  void setSize(Size size) => _window.setSize(size.toNative(), false);

  @override
  void preventClose(void Function() onCloseRequested) {
    final old = _closeListener;
    if (old != null) _window.removeListener(old);
    _closeListener = _window.addListener((event) {
      if (event is WindowCloseRequestedEvent) {
        event.request.cancel();
        onCloseRequested();
      }
    });
  }

  @override
  void show() => _window.show();

  @override
  void focus() => _window.focus();

  @override
  void hide() => _window.hide();

  @override
  void dispose() {
    final listener = _closeListener;
    if (listener != null) _window.removeListener(listener);
    _closeListener = null;
  }
}
