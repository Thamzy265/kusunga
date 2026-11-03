import 'dart:async';

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

  Future<void> start() async {
    await port.setIcon(iconPath);
    await port.setToolTip('Kusunga');
    await port.setMenu(const [TrayMenuEntry(key: quitKey, label: 'Quit')]);
    _clicks = port.menuItemClicks.listen((key) {
      if (key == quitKey) onQuit();
    });
  }

  Future<void> dispose() async => _clicks?.cancel();
}
