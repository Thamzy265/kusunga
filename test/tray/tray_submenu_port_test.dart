// M1.6 / M1.10c: the port builds "Pause history ▸" as a native submenu, and a
// click on any item, inside a submenu or not, reports that item's key. Runs
// on a fake backend (ADR 0009): no test calls the real plugin.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

import 'fake_tray_backend.dart';

void main() {
  late FakeTrayBackend backend;

  setUp(() => backend = FakeTrayBackend());

  test('an entry with children is sent as a submenu', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    await port.setMenu(const [
      TrayMenuEntry(key: 'open', label: 'Open Kusunga'),
      TrayMenuEntry(
        key: 'pause',
        label: 'Pause history',
        children: [
          TrayMenuEntry(key: 'pause15', label: 'For 15 minutes'),
          TrayMenuEntry(key: 'pauseUntil', label: 'Until I resume'),
        ],
      ),
    ]);
    final items = backend.contextMenu!.items;
    expect(items[0].label, 'Open Kusunga');
    expect(items[0].submenu, isNull);
    expect(items[0].onClick, isNotNull);
    expect(items[1].label, 'Pause history');
    expect(items[1].submenu!.labels, ['For 15 minutes', 'Until I resume']);
  });

  test('a click on a submenu item reports its key', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    await port.setMenu(const [
      TrayMenuEntry(
        key: 'pause',
        label: 'Pause history',
        children: [TrayMenuEntry(key: 'pause60', label: 'For 1 hour')],
      ),
    ]);
    final keys = <String>[];
    final sub = port.menuItemClicks.listen(keys.add);

    backend.contextMenu!.items.single.submenu!.clickItem('For 1 hour');
    await pumpEventQueue();

    expect(keys, ['pause60']);
    await sub.cancel();
  });

  test('a click on a top-level item reports its key', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    await port.setMenu(const [
      TrayMenuEntry(key: 'open', label: 'Open Kusunga'),
      TrayMenuEntry(key: 'quit', label: 'Quit'),
    ]);
    final keys = <String>[];
    final sub = port.menuItemClicks.listen(keys.add);

    backend.contextMenu!.clickItem('Quit');
    backend.contextMenu!.clickItem('Open Kusunga');
    await pumpEventQueue();

    expect(keys, ['quit', 'open']);
    await sub.cancel();
  });

  test('replacing the menu frees its submenus too', () async {
    final port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    await port.setMenu(const [
      TrayMenuEntry(
        key: 'pause',
        label: 'Pause history',
        children: [TrayMenuEntry(key: 'pause15', label: 'For 15 minutes')],
      ),
    ]);
    final submenu = backend.contextMenu!.items.single.submenu!;

    await port.setMenu(const [
      TrayMenuEntry(key: 'resume', label: 'Resume history'),
    ]);
    await pumpEventQueue();

    expect(submenu.disposed, isTrue);
  });
}
