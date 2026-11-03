import 'app_lifecycle.dart';

/// Every way out of the app ends with the history closed cleanly:
///  - tray Quit: [quitFromTray];
///  - Cmd+Q, Dock Quit, log out, shut down: native asks Dart to flush
///    ([listenForNativeFlush]) and waits for the answer.
class QuitFlow {
  QuitFlow({
    required this.lifecycle,
    required this.closeHistory,
    required this.stopTray,
    required this.stopWindow,
  });

  final AppLifecycle lifecycle;
  final Future<void> Function() closeHistory;
  final Future<void> Function() stopTray;
  final Future<void> Function() stopWindow;
  Future<void>? _closing;
  Future<void>? _quitting;

  /// Closes the history once, whichever exit path gets here first. A failure
  /// never stops the quit.
  Future<void> flush() => _closing ??= _flush();

  Future<void> _flush() async {
    try {
      await closeHistory();
    } catch (_) {
      // The history store logs its own failure; quitting must go on.
    }
  }

  void listenForNativeFlush() => lifecycle.onFlush(flush);

  /// The tray Quit item.
  Future<void> quitFromTray() => _quitting ??= _quit();

  Future<void> _quit() async {
    // A tray or window that fails to stop must not keep the history open or
    // stop the app from quitting.
    try {
      await stopTray();
    } catch (_) {}
    try {
      await stopWindow();
    } catch (_) {}
    await flush();
    try {
      await lifecycle.quit();
    } catch (_) {
      // Native could not quit: forget this attempt so choosing Quit again
      // tries again.
      _quitting = null;
      rethrow;
    }
  }
}
