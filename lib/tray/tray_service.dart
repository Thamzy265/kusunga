import 'dart:async';

import 'package:flutter/foundation.dart';

/// One entry in the tray / menu-bar menu.
class TrayMenuEntry {
  const TrayMenuEntry({required this.key, required this.label});

  final String key;
  final String label;
}

/// The part of the tray plugin that Kusunga uses. Kept small so tests can
/// replace the real plugin with a fake.
abstract interface class TrayPort {
  Stream<String> get menuItemClicks;
  Future<void> setIcon(String path);
  Future<void> setToolTip(String text);
  Future<void> setMenu(List<TrayMenuEntry> entries);

  /// Removes the tray icon.
  Future<void> destroy();

  /// Releases plugin listeners and streams. The port is unusable afterwards.
  Future<void> dispose();
}

/// Shows the menu-bar icon (Mac) or tray icon (Windows) with a Quit item.
class TrayService {
  TrayService({
    required this.port,
    required this.iconPath,
    required this.onQuit,
  });

  static const quitKey = 'quit';

  final TrayPort port;
  final String iconPath;
  final void Function() onQuit;
  StreamSubscription<String>? _clicks;
  Future<void>? _starting;
  bool _disposed = false;

  /// Sets up the tray. A second call is a no-op. A tray failure never reaches
  /// the caller: it is logged and the half-built tray is removed, so the app
  /// still opens and there is never an icon without a Quit item.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      await port.setIcon(iconPath);
      await port.setToolTip('Kusunga');
      await port.setMenu(const [TrayMenuEntry(key: quitKey, label: 'Quit')]);
      if (_disposed) return;
      _clicks = port.menuItemClicks.listen((key) {
        if (key == quitKey) onQuit();
      });
    } catch (error) {
      debugPrint('Kusunga: tray setup failed: $error');
      try {
        await port.destroy();
      } catch (cleanupError) {
        debugPrint('Kusunga: tray cleanup failed: $cleanupError');
      }
      _starting = null; // allow a later retry
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _clicks?.cancel();
    await port.dispose();
  }
}
