import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The quit flow shared with native code.
///
/// Native code calls `flush` on `uk.org.cgatechnologies.kusunga/lifecycle`
/// when the system or the user is ending the app (Cmd+Q, Dock Quit, log out,
/// shut down) and waits for the answer. Dart calls `quit` when the tray Quit
/// item is chosen, after it has flushed.
class AppLifecycle {
  AppLifecycle({MethodChannel? channel, void Function(int code)? exitFallback})
    : _channel =
          channel ??
          const MethodChannel('uk.org.cgatechnologies.kusunga/lifecycle'),
      _exit = exitFallback ?? exit;

  final MethodChannel _channel;
  final void Function(int code) _exit;

  /// [handler] flushes and closes the data store. It is called whenever
  /// native asks, and its failure never blocks the quit.
  void onFlush(Future<void> Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'flush') throw MissingPluginException();
      try {
        await handler();
      } catch (error) {
        debugPrint('Kusunga: flush failed');
      }
      return null;
    });
  }

  /// Asks native to end the app. If there is no native side, exits.
  Future<void> quit() async {
    try {
      await _channel.invokeMethod<void>('quit');
    } on MissingPluginException {
      _exit(0);
    }
  }
}
