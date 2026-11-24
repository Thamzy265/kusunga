// M1.10c developer: the tray port's error paths (the same kind of bug as
// tester finding T1: cleanup when a native call throws, errors escaping a
// timer or a listener, and native work after dispose). The backend is a
// fake, so no test calls the real plugin.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

import 'fake_tray_backend.dart';

class _Backend extends FakeTrayBackend {
  bool setContextMenuFails = false;

  /// The menus made from now on fail to free.
  bool newMenusFailToFree = false;

  @override
  TrayBackendMenu createMenu() {
    final menu = _Menu()..disposeFails = newMenusFailToFree;
    menus.add(menu);
    return menu;
  }

  @override
  void setContextMenu(TrayBackendMenu menu) {
    if (setContextMenuFails) throw StateError('native setContextMenu failed');
    super.setContextMenu(menu);
  }
}

class _Menu extends FakeTrayMenu {
  bool disposeFails = false;

  @override
  void dispose() {
    super.dispose();
    if (disposeFails) throw UnsupportedError('native free failed');
  }
}

const _two = [
  TrayMenuEntry(key: 'open', label: 'Open'),
  TrayMenuEntry(key: 'quit', label: 'Quit'),
];

List<String> _captureLogs() {
  final logs = <String>[];
  final old = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  addTearDown(() => debugPrint = old);
  return logs;
}

void main() {
  late _Backend backend;
  late TrayManagerPort port;

  setUp(() {
    backend = _Backend();
    port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
  });

  _Menu menu(int i) => backend.menus[i] as _Menu;

  test('a replaced menu whose free throws is not an uncaught error in the '
      'free timer: it is logged once', () async {
    final logs = _captureLogs();
    await port.setMenu(_two);
    menu(0).disposeFails = true;

    await port.setMenu(_two);
    await pumpEventQueue();

    expect(menu(0).disposed, isTrue);
    expect(logs, ['Kusunga: tray menu free failed (UnsupportedError)']);
  });

  test('a failed setMenu whose new menu also fails to free reports the '
      'setMenu error, not the free error', () async {
    final logs = _captureLogs();
    await port.setMenu(_two);
    backend
      ..setContextMenuFails = true
      ..newMenusFailToFree = true;

    await expectLater(port.setMenu(_two), throwsStateError);
    expect(menu(1).disposed, isTrue);
    expect(logs, ['Kusunga: tray menu free failed (UnsupportedError)']);
    expect(backend.contextMenu, same(menu(0)));
  });
}
