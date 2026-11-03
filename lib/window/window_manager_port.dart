import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'window_service.dart';

/// [WindowPort] backed by the `window_manager` plugin.
class WindowManagerPort with WindowListener implements WindowPort {
  final _closes = StreamController<void>.broadcast();

  @override
  Stream<void> get closeRequests => _closes.stream;

  @override
  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(360, 400));
    await windowManager.setSize(const Size(800, 632));
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  @override
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();

  @override
  void onWindowClose() => _closes.add(null);

  @override
  Future<void> dispose() async {
    windowManager.removeListener(this);
    await _closes.close();
  }
}
