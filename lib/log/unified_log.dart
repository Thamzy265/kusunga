import 'package:flutter/services.dart';

import 'app_log.dart';

/// Mirrors every log code to the macOS unified log (`log show --predicate
/// 'subsystem == "com.wnasoni.kusunga"'`), through the native side, because a
/// signed sandboxed app's own log file cannot be read from outside. Codes and
/// numbers only, as in the file log. A missing native side (Windows) or an
/// error is ignored.
class ChannelUnifiedLog implements ErrorLog {
  ChannelUnifiedLog({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.wnasoni.kusunga/diag');

  final MethodChannel _channel;

  @override
  void log(LogCode code, [int? detail]) {
    try {
      _channel
          .invokeMethod<void>('log', {'code': code.name, 'detail': detail})
          .catchError((Object _) {});
    } catch (_) {
      // Never throw from the log.
    }
  }
}
