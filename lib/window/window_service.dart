import 'dart:async';

import 'package:flutter/foundation.dart';

/// The part of the window plugin that Kusunga uses. Kept small so tests can
/// replace the real plugin with a fake.
abstract interface class WindowPort {
  /// Emits when the user asks to close the window (close button).
  Stream<void> get closeRequests;

  /// Makes the close button send [closeRequests] instead of closing.
  Future<void> init();
  Future<void> show();
  Future<void> hide();
  Future<void> dispose();
}

/// Closing the window hides it; the app stays in the menu bar / tray and
/// Quit is the only way out.
class WindowService {
  WindowService({required this.port});

  final WindowPort port;
  StreamSubscription<void>? _closes;
  bool _disposed = false;

  /// A window setup failure is logged and never stops the app. Close
  /// requests are listened to even then: the port can still set the window
  /// up later (a show or hide that finds it), and a close it cancels must
  /// still hide the window.
  Future<void> start() async {
    try {
      await port.init();
    } catch (error) {
      debugPrint('Kusunga: window setup failed: $error');
    }
    if (_disposed) return;
    _closes = port.closeRequests.listen(
      // Nothing awaits this hide, so its error is logged here (error type
      // only) rather than left uncaught.
      (_) => port.hide().catchError((Object error) {
        debugPrint('Kusunga: window hide failed (${error.runtimeType})');
      }),
    );
  }

  Future<void> show() => port.show();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _closes?.cancel();
      await port.dispose();
    } catch (error) {
      debugPrint('Kusunga: window cleanup failed');
    }
  }
}
