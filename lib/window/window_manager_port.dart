import 'dart:async';
// dart:ffi's Size is C's size_t; the window sizes here are dart:ui's.
import 'dart:ffi' hide Size;
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:ffi/ffi.dart' show using;
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart'
    show
        ArenaExtension,
        EnumWindows,
        GetClassName,
        GetCurrentProcessId,
        GetWindowThreadProcessId,
        HWND,
        LPARAM,
        PWSTR,
        WNDENUMPROC;
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
      return;
    }
    try {
      if (_find() == null) _retryLater();
    } catch (_) {
      // A lookup that throws still reaches the caller, but the window is
      // looked for again, as after a miss: otherwise it would not be set up
      // (close-to-hide) until a show or hide.
      _retryLater();
      rethrow;
    }
  }

  /// Never throws: a set-up step that fails must not stop what comes after
  /// it (the other steps, a pending show, the caller's own show or hide, or
  /// the app's close listener). Each step is tried on its own, above all
  /// close-to-hide: without it the close button would really close the
  /// window for the whole session. Each failure is logged once, with the
  /// error type only. The window is kept, and only a later [init] sets it up
  /// again.
  ///
  /// On Windows the runner sets the 360 x 400 minimum itself and lifts it
  /// while the picker or the toast shows (windows/runner/picker_bridge.cpp,
  /// WM_GETMINMAXINFO). A minimum set here would be nativeapi's, which
  /// answers that message before the runner sees it (reviewer F2).
  void _setUp(WindowHandle window) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      _trySetUpStep(() => window.setMinimumSize(const Size(360, 400)));
    }
    _trySetUpStep(() => window.setSize(const Size(800, 632)));
    _trySetUpStep(() => window.preventClose(_onCloseRequested));
  }

  static void _trySetUpStep(void Function() step) {
    try {
      step();
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
    // A window already found (a pending show that threw inside init) needs
    // no retry.
    if (_retry != null || _disposed || _window != null) return;
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

/// The window class of the Windows runner's window
/// (windows/runner/win32_window.cpp, `kWindowClassName`).
const runnerWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// A top-level window of this process: its handle (HWND) and the name of its
/// window class.
typedef TopLevelWindow = ({int handle, String className});

/// The app's window on Windows, from this process's top-level [windows] in
/// z-order, hidden ones included: the first of the runner's class
/// ([runnerWindowClass]), or null while there is none, so the port looks
/// again. No other window is ever picked, however high in the z-order. The
/// runner's window is hidden until its first frame (after a login start,
/// until "Open Kusunga"), and meanwhile nativeapi's own pick, getCurrent(),
/// can be another hidden window of the process, such as Windows' "Default
/// IME" (reviewer F3).
int? pickRunnerWindow(Iterable<TopLevelWindow> windows) {
  for (final window in windows) {
    if (window.className == runnerWindowClass) return window.handle;
  }
  return null;
}

/// The real [WindowBackend]. Windows: the runner's window, hidden or not
/// ([pickRunnerWindow]). macOS: nativeapi's current window (the main window,
/// else the first one).
class NativeWindowBackend implements WindowBackend {
  @override
  WindowHandle? findWindow() {
    final window = Platform.isWindows
        ? _runnerWindow()
        : WindowManager.instance.getCurrent();
    return window == null ? null : _NativeWindow(window);
  }

  static Window? _runnerWindow() {
    final handle = pickRunnerWindow(_topLevelWindows());
    // nativeapi's own lists (getAll) leave hidden windows out, so the window
    // is wrapped from its handle, as window_manager's legacy layer does for
    // a hidden window.
    return handle == null
        ? null
        : Window.createWithNativeWindow(Pointer<Void>.fromAddress(handle));
  }

  /// This process's top-level windows, hidden ones included, in z-order
  /// (EnumWindows), each with its window class. Windows only.
  static List<TopLevelWindow> _topLevelWindows() {
    final handles = <int>[];
    final collect = NativeCallable<WNDENUMPROC>.isolateLocal((
      Pointer hwnd,
      int _,
    ) {
      handles.add(hwnd.address);
      return 1; // TRUE: go on.
    }, exceptionalReturn: 0);
    try {
      EnumWindows(collect.nativeFunction, const LPARAM(0));
    } finally {
      collect.close();
    }
    final self = GetCurrentProcessId();
    return using((arena) {
      final processId = arena<Uint32>();
      final name = arena.pwstrBuffer(256);
      return [
        for (final handle in handles)
          if (_classOfOwnWindow(handle, self, processId, name)
              case final className?)
            (handle: handle, className: className),
      ];
    });
  }

  /// The window class of [handle], or null when the window is not this
  /// process's ([self]) or is gone.
  static String? _classOfOwnWindow(
    int handle,
    int self,
    Pointer<Uint32> processId,
    PWSTR name,
  ) {
    final hwnd = HWND(Pointer.fromAddress(handle));
    processId.value = 0;
    if (GetWindowThreadProcessId(hwnd, processId) == 0) return null;
    if (processId.value != self) return null;
    final length = GetClassName(hwnd, name, 256).value;
    return length > 0 ? name.toDartString(length: length) : null;
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
