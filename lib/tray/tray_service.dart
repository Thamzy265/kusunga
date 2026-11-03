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

/// Shows the menu-bar icon (Mac) or tray icon (Windows) with Open picker, Open
/// Kusunga and Quit items.
class TrayService {
  TrayService({
    required this.port,
    required this.iconPath,
    required this.onOpenPicker,
    required this.onOpen,
    required this.onQuit,
  });

  static const pickerKey = 'picker';
  static const openKey = 'open';
  static const quitKey = 'quit';

  final TrayPort port;
  final String iconPath;
  final void Function() onOpenPicker;
  final void Function() onOpen;
  final void Function() onQuit;
  StreamSubscription<String>? _clicks;
  Future<void>? _starting;
  bool _disposed = false;
  bool _portDisposed = false;

  /// Sets up the tray. A second call is a no-op. A tray failure never reaches
  /// the caller: it is logged, the half-built tray is removed and the port is
  /// disposed, so the app still opens and there is never an icon without a Quit
  /// item. A failed start is final: retrying needs a new port.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      if (await _stopIfDisposed()) return;
      await port.setIcon(iconPath);
      if (await _stopIfDisposed()) return;
      await port.setToolTip('Kusunga');
      if (await _stopIfDisposed()) return;
      await port.setMenu(const [
        TrayMenuEntry(key: pickerKey, label: 'Open picker'),
        TrayMenuEntry(key: openKey, label: 'Open Kusunga'),
        TrayMenuEntry(key: quitKey, label: 'Quit'),
      ]);
      if (await _stopIfDisposed()) return;
      _clicks = port.menuItemClicks.listen((key) {
        switch (key) {
          case pickerKey:
            onOpenPicker();
          case openKey:
            onOpen();
          case quitKey:
            onQuit();
        }
      });
    } catch (error) {
      debugPrint('Kusunga: tray setup failed: $error');
      await _safeDestroy();
      await _disposePort();
    }
  }

  /// If [dispose] ran while a step was in flight, remove what was built.
  Future<bool> _stopIfDisposed() async {
    if (!_disposed) return false;
    await _safeDestroy();
    return true;
  }

  Future<void> _safeDestroy() async {
    try {
      await port.destroy();
    } catch (error) {
      debugPrint('Kusunga: tray cleanup failed: $error');
    }
  }

  Future<void> _disposePort() async {
    if (_portDisposed) return;
    _portDisposed = true;
    await port.dispose();
  }

  /// Removes the tray icon and releases the port.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _clicks?.cancel();
    await _safeDestroy();
    await _disposePort();
  }
}
