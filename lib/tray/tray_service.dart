import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../history/pause_service.dart';

/// One entry in the tray / menu-bar menu. With [children] it opens a
/// submenu ("Pause history ▸").
class TrayMenuEntry {
  const TrayMenuEntry({required this.key, required this.label, this.children});

  final String key;
  final String label;
  final List<TrayMenuEntry>? children;
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
/// Kusunga and Quit items, and (M1.6, once the history has opened) "Pause
/// history ▸" or "Resume history", with the tooltip and a paused icon.
class TrayService {
  TrayService({
    required this.port,
    required this.iconPath,
    required this.onOpenPicker,
    required this.onOpen,
    required this.onQuit,
    String? pausedIconPath,
    bool Function()? use24Hour,
  }) : pausedIconPath = pausedIconPath ?? iconPath,
       _use24Hour =
           use24Hour ??
           (() => WidgetsBinding
               .instance
               .platformDispatcher
               .alwaysUse24HourFormat);

  static const pickerKey = 'picker';
  static const openKey = 'open';
  static const quitKey = 'quit';
  static const pauseKey = 'pause';
  static const pause15Key = 'pause15';
  static const pause60Key = 'pause60';
  static const pauseUntilKey = 'pauseUntil';
  static const resumeKey = 'resume';

  final TrayPort port;
  final String iconPath;

  /// The same icon with a pause mark (Mac template image, Windows .ico).
  final String pausedIconPath;
  final void Function() onOpenPicker;
  final void Function() onOpen;
  final void Function() onQuit;
  final bool Function() _use24Hour;
  PauseService? _pause;
  var _started = false;

  /// What the tray shows now: (paused, tooltip). Set again only on change.
  (bool, String)? _shown;
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
      final (paused, tip) = _state();
      await port.setIcon(paused ? pausedIconPath : iconPath);
      if (await _stopIfDisposed()) return;
      await port.setToolTip(tip);
      if (await _stopIfDisposed()) return;
      await port.setMenu(_menu(paused));
      _menuHasPause = _pause != null;
      _shown = (paused, tip);
      if (await _stopIfDisposed()) return;
      _clicks = port.menuItemClicks.listen((key) {
        final pause = _pause;
        switch (key) {
          case pickerKey:
            onOpenPicker();
          case openKey:
            onOpen();
          case quitKey:
            onQuit();
          case pause15Key:
            if (pause != null) unawaited(pause.pause(PauseLength.quarterHour));
          case pause60Key:
            if (pause != null) unawaited(pause.pause(PauseLength.hour));
          case pauseUntilKey:
            if (pause != null) {
              unawaited(pause.pause(PauseLength.untilResumed));
            }
          case resumeKey:
            if (pause != null) unawaited(pause.resume());
        }
      });
      _started = true;
      // A change while the tray was being built.
      await _update();
    } catch (error) {
      debugPrint('Kusunga: tray setup failed: $error');
      await _safeDestroy();
      await _disposePort();
    }
  }

  /// Shows the pause state from now on (M1.6). Called once the history has
  /// opened.
  void attachPause(PauseService pause) {
    if (_disposed || _pause != null) return;
    _pause = pause;
    pause.addListener(_onPauseChanged);
    // A tray update that threw is tried again on the next tick (B2), even
    // when nothing about the pause changed.
    pause.ticks.addListener(_onPauseChanged);
    _onPauseChanged();
  }

  void _onPauseChanged() => unawaited(_update());

  (bool, String) _state() {
    final pause = _pause;
    if (pause == null || !pause.isPaused) return (false, 'Kusunga');
    final end = pause.endsAt;
    if (end == null) return (true, 'Kusunga — history paused');
    final time = formatPauseEnd(end, pause.now, use24Hour: _use24Hour());
    return (true, 'Kusunga — history paused until $time');
  }

  List<TrayMenuEntry> _menu(bool paused) => [
    const TrayMenuEntry(key: pickerKey, label: 'Open picker'),
    const TrayMenuEntry(key: openKey, label: 'Open Kusunga'),
    if (_pause != null)
      paused
          ? const TrayMenuEntry(key: resumeKey, label: 'Resume history')
          : const TrayMenuEntry(
              key: pauseKey,
              label: 'Pause history',
              children: [
                TrayMenuEntry(key: pause15Key, label: 'For 15 minutes'),
                TrayMenuEntry(key: pause60Key, label: 'For 1 hour'),
                TrayMenuEntry(key: pauseUntilKey, label: 'Until I resume'),
              ],
            ),
    const TrayMenuEntry(key: quitKey, label: 'Quit'),
  ];

  /// Sets the icon, tooltip and menu again when the pause state changed.
  /// A failure is logged and swallowed: the tray keeps its last state.
  Future<void> _update() async {
    if (!_started || _disposed) return;
    final state = _state();
    final menuChanged = _shown?.$1 != state.$1 || _menuLacksPause();
    if (_shown == state && !menuChanged) return;
    final was = _shown;
    // Marked shown only once every step worked: a step that throws leaves
    // the tray "unknown", so the next change sets all of it again (B2).
    _shown = null;
    try {
      // A dispose during any step has destroyed the tray: stop, so a late
      // step does not make the native icon again or build a menu that
      // nothing frees.
      if (was?.$1 != state.$1) {
        await port.setIcon(state.$1 ? pausedIconPath : iconPath);
        if (_disposed) return;
      }
      if (was?.$2 != state.$2) {
        await port.setToolTip(state.$2);
        if (_disposed) return;
      }
      if (menuChanged || was == null) await port.setMenu(_menu(state.$1));
      _menuHasPause = _pause != null;
      _shown = state;
    } catch (error) {
      _menuHasPause = false;
      debugPrint('Kusunga: tray update failed: $error');
    }
  }

  var _menuHasPause = false;
  bool _menuLacksPause() => _pause != null && !_menuHasPause;

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
    _pause?.removeListener(_onPauseChanged);
    _pause?.ticks.removeListener(_onPauseChanged);
    await _clicks?.cancel();
    await _safeDestroy();
    await _disposePort();
  }
}
