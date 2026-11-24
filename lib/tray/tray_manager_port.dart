import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'tray_service.dart';

/// Which mouse button clicked the tray icon.
enum TrayIconClick { left, right }

/// The native tray calls [TrayManagerPort] makes, one for one with
/// tray_manager's native API (ADR 0009). Tests pass a fake, so no test calls
/// the real plugin.
abstract interface class TrayBackend {
  /// Reports every left or right click on the icon to [onClick].
  void listenIconClicks(void Function(TrayIconClick) onClick);

  /// Shows the bundled asset [assetPath] as the icon. Throws when the image
  /// cannot be loaded.
  void setIcon(String assetPath, {required bool isTemplate});
  void setTooltip(String text);
  TrayBackendMenu createMenu();

  /// Makes [menu] the icon's menu. The previous menu is not freed.
  void setContextMenu(TrayBackendMenu menu);
  void openContextMenu();

  /// Removes the icon.
  void destroy();
}

/// A native menu under construction.
abstract interface class TrayBackendMenu {
  void addItem(String label, void Function() onClick);

  /// Adds an item that opens a submenu, and returns that submenu.
  TrayBackendMenu addSubmenu(String label);

  /// Frees the menu, its items, their listeners and its submenus.
  void dispose();
}

/// [TrayPort] backed by the `tray_manager` plugin through [TrayBackend].
class TrayManagerPort implements TrayPort {
  TrayManagerPort({TrayBackend? backend})
    : _backend = backend ?? NativeTrayBackend() {
    _backend.listenIconClicks(_onIconClick);
  }

  final TrayBackend _backend;
  final _clicks = StreamController<String>.broadcast();
  TrayBackendMenu? _menu;
  var _disposed = false;

  @override
  Stream<String> get menuItemClicks => _clicks.stream;

  // After dispose, icon, tooltip and menu updates are dropped: a late one (a
  // tray update still in flight when TrayService disposed) would make the
  // native icon again after destroy, or build a menu that nothing frees.

  @override
  Future<void> setIcon(String path) async {
    if (_disposed) return;
    _backend.setIcon(
      path,
      isTemplate: defaultTargetPlatform == TargetPlatform.macOS,
    );
  }

  @override
  Future<void> setToolTip(String text) async {
    if (!_disposed) _backend.setTooltip(text);
  }

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async {
    if (_disposed) return;
    final menu = _backend.createMenu();
    try {
      _fill(menu, entries);
      _backend.setContextMenu(menu);
    } catch (_) {
      // The new menu was never the icon's, so nothing native can be inside
      // it: free it now. The old menu stays set.
      _free(menu);
      rethrow;
    }
    _freeLater(_menu);
    _menu = menu;
  }

  void _fill(TrayBackendMenu menu, List<TrayMenuEntry> entries) {
    for (final e in entries) {
      final children = e.children;
      if (children == null) {
        menu.addItem(e.label, () => _onItemClick(e.key));
      } else {
        _fill(menu.addSubmenu(e.label), children);
      }
    }
  }

  // A menu item's click handler can replace the menu (pause) or remove the
  // icon (Quit) while the native side is still inside that item's callback,
  // so the old menu lives until the current event is done.
  void _freeLater(TrayBackendMenu? menu) {
    if (menu != null) Timer.run(() => _free(menu));
  }

  // A free that throws is logged (error type only): it must not escape the
  // free timer, nor hide the error of a setMenu that failed.
  void _free(TrayBackendMenu menu) {
    try {
      menu.dispose();
    } catch (error) {
      debugPrint('Kusunga: tray menu free failed (${error.runtimeType})');
    }
  }

  void _onItemClick(String key) {
    if (!_clicks.isClosed) _clicks.add(key);
  }

  // The native menu opens on its own only for one button, but Kusunga opens
  // it on a left and a right click, as before.
  void _onIconClick(TrayIconClick _) {
    if (!_disposed) _backend.openContextMenu();
  }

  @override
  Future<void> destroy() async {
    _backend.destroy();
    _freeLater(_menu);
    _menu = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _clicks.close();
  }
}

/// The real [TrayBackend]: one nativeapi [TrayIcon], created on first use.
/// Every native object is kept here: nativeapi frees a handle, and stops its
/// listeners, when the Dart object is collected.
class NativeTrayBackend implements TrayBackend {
  TrayIcon? _tray;
  ListenerId? _trayListener;
  Image? _image;
  void Function(TrayIconClick)? _onClick;

  TrayIcon get _icon {
    final existing = _tray;
    if (existing != null) return existing;
    final tray = TrayIcon.create();
    if (tray == null) throw StateError('Unable to create the tray icon');
    // Kusunga opens the menu itself, on either button (TrayManagerPort).
    tray.setContextMenuTrigger(ContextMenuTrigger.none);
    _trayListener = tray.addListener((event) {
      switch (event) {
        case TrayIconClickedEvent():
          _onClick?.call(TrayIconClick.left);
        case TrayIconRightClickedEvent():
          _onClick?.call(TrayIconClick.right);
        case TrayIconDoubleClickedEvent():
          break;
      }
    });
    return _tray = tray;
  }

  @override
  void listenIconClicks(void Function(TrayIconClick) onClick) =>
      _onClick = onClick;

  @override
  void setIcon(String assetPath, {required bool isTemplate}) {
    final image = ImageAsset.fromAsset(assetPath);
    if (image == null) {
      throw ArgumentError.value(assetPath, 'assetPath', 'Unable to load');
    }
    _icon
      ..isIconTemplate = isTemplate
      ..icon = image
      ..setVisible(true);
    _image?.dispose();
    _image = image;
  }

  @override
  void setTooltip(String text) => _icon.setTooltip(text);

  @override
  TrayBackendMenu createMenu() => _NativeTrayMenu();

  @override
  void setContextMenu(TrayBackendMenu menu) =>
      _icon.setContextMenu((menu as _NativeTrayMenu).menu);

  @override
  void openContextMenu() => _tray?.openContextMenu();

  @override
  void destroy() {
    final tray = _tray;
    final listener = _trayListener;
    if (tray != null && listener != null) tray.removeListener(listener);
    tray?.dispose();
    _tray = null;
    _trayListener = null;
    _image?.dispose();
    _image = null;
  }
}

class _NativeTrayMenu implements TrayBackendMenu {
  _NativeTrayMenu() : menu = Menu.create() ?? _fail('the menu');

  final Menu menu;
  final _items = <(MenuItem, ListenerId?)>[];
  final _submenus = <_NativeTrayMenu>[];

  static Never _fail(String what) => throw StateError('Unable to create $what');

  MenuItem _add(String label, MenuItemType type) {
    final item =
        MenuItem.createWithLabelAndType(label, type) ??
        _fail('the menu item $label');
    menu.addItem(item);
    return item;
  }

  @override
  void addItem(String label, void Function() onClick) {
    final item = _add(label, MenuItemType.normal);
    final listener = item.addListener((event) {
      if (event is MenuItemClickedEvent) onClick();
    });
    _items.add((item, listener));
  }

  @override
  TrayBackendMenu addSubmenu(String label) {
    final item = _add(label, MenuItemType.submenu);
    final submenu = _NativeTrayMenu();
    item.submenu = submenu.menu;
    _items.add((item, null));
    _submenus.add(submenu);
    return submenu;
  }

  @override
  void dispose() {
    for (final (item, listener) in _items) {
      if (listener != null) item.removeListener(listener);
      item.dispose();
    }
    _items.clear();
    for (final submenu in _submenus) {
      submenu.dispose();
    }
    _submenus.clear();
    menu.dispose();
  }
}
