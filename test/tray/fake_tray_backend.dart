import 'package:kusunga/tray/tray_manager_port.dart';

/// A [TrayBackend] that records what the port asks of the native tray, so
/// no test calls the real plugin (that would build the C++ library and put a
/// real icon in the menu bar).
class FakeTrayBackend implements TrayBackend {
  final calls = <String>[];
  String? iconPath;
  bool? iconIsTemplate;
  String? tooltip;
  FakeTrayMenu? contextMenu;
  final menus = <FakeTrayMenu>[];
  void Function(TrayIconClick)? _onClick;

  /// What the native side would report for a click on the icon.
  void click(TrayIconClick button) => _onClick?.call(button);

  @override
  void listenIconClicks(void Function(TrayIconClick) onClick) {
    calls.add('listen');
    _onClick = onClick;
  }

  @override
  void setIcon(String assetPath, {required bool isTemplate}) {
    calls.add('setIcon');
    iconPath = assetPath;
    iconIsTemplate = isTemplate;
  }

  @override
  void setTooltip(String text) {
    calls.add('setTooltip');
    tooltip = text;
  }

  @override
  TrayBackendMenu createMenu() {
    final menu = FakeTrayMenu();
    menus.add(menu);
    return menu;
  }

  @override
  void setContextMenu(TrayBackendMenu menu) {
    calls.add('setContextMenu');
    contextMenu = menu as FakeTrayMenu;
  }

  @override
  void openContextMenu() => calls.add('openContextMenu');

  @override
  void destroy() => calls.add('destroy');
}

/// One item in a [FakeTrayMenu]: a plain item with its click handler, or a
/// submenu.
class FakeTrayItem {
  FakeTrayItem(this.label, {this.onClick, this.submenu});

  final String label;
  final void Function()? onClick;
  final FakeTrayMenu? submenu;
}

class FakeTrayMenu implements TrayBackendMenu {
  final items = <FakeTrayItem>[];
  var disposed = false;

  List<String> get labels => [for (final i in items) i.label];

  /// The native "item clicked" event for the item labelled [label].
  void clickItem(String label) =>
      items.singleWhere((i) => i.label == label).onClick!();

  @override
  void addItem(String label, void Function() onClick) =>
      items.add(FakeTrayItem(label, onClick: onClick));

  @override
  TrayBackendMenu addSubmenu(String label) {
    final submenu = FakeTrayMenu();
    items.add(FakeTrayItem(label, submenu: submenu));
    return submenu;
  }

  @override
  void dispose() {
    disposed = true;
    for (final i in items) {
      i.submenu?.dispose();
    }
  }
}
