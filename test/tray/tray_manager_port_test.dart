// M1.10c: the port runs on an injected backend (ADR 0009), so these tests
// never touch the real tray_manager / nativeapi plugin.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

import 'fake_tray_backend.dart';

void main() {
  late FakeTrayBackend backend;

  setUp(() => backend = FakeTrayBackend());

  test('C1: left click on the icon pops up the menu', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);

    backend.click(TrayIconClick.left);

    expect(backend.calls, ['listen', 'openContextMenu']);
  });

  test('C1: right click on the icon pops up the menu', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);

    backend.click(TrayIconClick.right);

    expect(backend.calls, ['listen', 'openContextMenu']);
  });

  test('C3: setToolTip is sent on every platform', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);

    await port.setToolTip('Kusunga');

    expect(backend.tooltip, 'Kusunga');
  });

  test('the icon is a template image on the Mac only', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await port.setIcon('assets/tray/tray_icon.png');
    expect(backend.iconPath, 'assets/tray/tray_icon.png');
    expect(backend.iconIsTemplate, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await port.setIcon('assets/tray/tray_icon.ico');
    expect(backend.iconPath, 'assets/tray/tray_icon.ico');
    expect(backend.iconIsTemplate, isFalse);
  });

  test('a failing icon load reaches the caller', () async {
    final port = TrayManagerPort(backend: _FailingIconBackend());
    addTearDown(port.dispose);

    expect(port.setIcon('assets/tray/missing.png'), throwsArgumentError);
  });

  test('destroy asks the plugin to remove the icon', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);

    await port.destroy();

    expect(backend.calls, ['listen', 'destroy']);
  });

  test('F2: after dispose the port no longer reacts to the icon', () async {
    final port = TrayManagerPort(backend: backend);
    await port.dispose();

    backend.click(TrayIconClick.left);
    backend.click(TrayIconClick.right);

    expect(backend.calls, ['listen']);
  });

  test('a menu click after dispose is dropped without an error', () async {
    final port = TrayManagerPort(backend: backend);
    await port.setMenu(const [TrayMenuEntry(key: 'quit', label: 'Quit')]);
    await port.dispose();

    backend.contextMenu!.clickItem('Quit');
  });

  test('a new menu replaces the old one, which is freed afterwards', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    await port.setMenu(const [TrayMenuEntry(key: 'open', label: 'Open')]);
    final first = backend.contextMenu!;

    await port.setMenu(const [TrayMenuEntry(key: 'quit', label: 'Quit')]);

    expect(backend.contextMenu, isNot(same(first)));
    expect(backend.contextMenu!.labels, ['Quit']);
    // A click handler may still be running inside the old menu's item (the
    // pause items rebuild the menu), so it is freed after the current event.
    expect(first.disposed, isFalse);
    await pumpEventQueue();
    expect(first.disposed, isTrue);
    expect(backend.contextMenu!.disposed, isFalse);
  });

  test('destroy frees the current menu', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    await port.setMenu(const [TrayMenuEntry(key: 'quit', label: 'Quit')]);
    final menu = backend.contextMenu!;

    await port.destroy();
    await pumpEventQueue();

    expect(menu.disposed, isTrue);
  });

  test('menu items keep their order and labels', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);

    await port.setMenu(const [
      TrayMenuEntry(key: 'picker', label: 'Open picker'),
      TrayMenuEntry(key: 'open', label: 'Open Kusunga'),
      TrayMenuEntry(key: 'quit', label: 'Quit'),
    ]);

    expect(backend.contextMenu!.labels, [
      'Open picker',
      'Open Kusunga',
      'Quit',
    ]);
  });
}

class _FailingIconBackend extends FakeTrayBackend {
  @override
  void setIcon(String assetPath, {required bool isTemplate}) =>
      throw ArgumentError.value(assetPath, 'assetPath', 'Unable to load');
}
