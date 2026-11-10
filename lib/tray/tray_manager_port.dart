import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'tray_service.dart';

/// [TrayPort] backed by the `tray_manager` plugin.
class TrayManagerPort with TrayListener implements TrayPort {
  TrayManagerPort() {
    trayManager.addListener(this);
  }

  final _clicks = StreamController<String>.broadcast();

  @override
  Stream<String> get menuItemClicks => _clicks.stream;

  @override
  Future<void> setIcon(String path) => trayManager.setIcon(
    path,
    isTemplate: defaultTargetPlatform == TargetPlatform.macOS,
  );

  @override
  Future<void> setToolTip(String text) => trayManager.setToolTip(text);

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) =>
      trayManager.setContextMenu(_menu(entries));

  // tray_manager 0.5.3 draws submenus on both systems (NSMenu setSubmenu on
  // the Mac, MF_POPUP on Windows) and finds a clicked item inside them.
  static Menu _menu(List<TrayMenuEntry> entries) => Menu(
    items: [
      for (final e in entries)
        e.children == null
            ? MenuItem(key: e.key, label: e.label)
            : MenuItem.submenu(
                key: e.key,
                label: e.label,
                submenu: _menu(e.children!),
              ),
    ],
  );

  // tray_manager 0.5.3 only stores the menu in setContextMenu; the menu is
  // shown by popUpContextMenu, so a click on the icon must ask for it.
  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key != null) _clicks.add(key);
  }

  @override
  Future<void> destroy() => trayManager.destroy();

  @override
  Future<void> dispose() async {
    trayManager.removeListener(this);
    await _clicks.close();
  }
}
