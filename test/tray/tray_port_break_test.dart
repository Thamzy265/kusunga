// M1.10c tester: ways to break the tray port on its injected backend
// (ADR 0009). The risk is native memory: a menu freed while the native side
// is still inside one of its items, a menu that is never freed, or a stale
// item that reports something after its menu is gone. No test calls the real
// plugin.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

import 'fake_tray_backend.dart';

/// A backend whose menus count how often they are freed and whose native
/// calls can be made to throw.
class _CountingBackend extends FakeTrayBackend {
  int? addItemFailsAt;
  bool setContextMenuFails = false;
  bool setIconFails = false;
  final order = <String>[];

  @override
  TrayBackendMenu createMenu() {
    final menu = _CountingMenu(this, menus.length);
    menus.add(menu);
    return menu;
  }

  @override
  void setContextMenu(TrayBackendMenu menu) {
    if (setContextMenuFails) throw StateError('native setContextMenu failed');
    order.add('set ${(menu as _CountingMenu).id}');
    super.setContextMenu(menu);
  }

  @override
  void setIcon(String assetPath, {required bool isTemplate}) {
    if (setIconFails) throw ArgumentError('Unable to load');
    super.setIcon(assetPath, isTemplate: isTemplate);
  }
}

class _CountingMenu extends FakeTrayMenu {
  _CountingMenu(this._backend, this.id);

  final _CountingBackend _backend;
  final int id;
  var frees = 0;

  @override
  void addItem(String label, void Function() onClick) {
    if (_backend.addItemFailsAt == items.length) {
      throw StateError('native addItem failed');
    }
    super.addItem(label, onClick);
  }

  @override
  void dispose() {
    frees++;
    _backend.order.add('free $id');
    super.dispose();
  }
}

const _two = [
  TrayMenuEntry(key: 'open', label: 'Open'),
  TrayMenuEntry(key: 'quit', label: 'Quit'),
];

void main() {
  late _CountingBackend backend;
  late TrayManagerPort port;

  setUp(() {
    backend = _CountingBackend();
    port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
  });

  _CountingMenu menu(int i) => backend.menus[i] as _CountingMenu;

  test('a click handler that replaces the menu and removes the icon (pause, '
      'then Quit) leaves the menu it runs in alive until its event is done, '
      'and frees every menu exactly once', () async {
    await port.setMenu(_two);
    final running = menu(0);
    port.menuItemClicks.listen((_) async {
      // What TrayService does on a pause click, then on Quit.
      await port.setMenu(const [TrayMenuEntry(key: 'quit', label: 'Quit')]);
      expect(running.frees, 0, reason: 'freed inside its own click handler');
      await port.destroy();
      expect(running.frees, 0, reason: 'freed inside its own click handler');
    });

    running.clickItem('Open');
    await pumpEventQueue();

    expect([for (final m in backend.menus) (m as _CountingMenu).frees], [1, 1]);
  });

  test('the new menu is set on the icon before the old one is freed', () async {
    await port.setMenu(_two);
    await port.setMenu(_two);
    await pumpEventQueue();

    expect(backend.order, ['set 0', 'set 1', 'free 0']);
  });

  test('many repeated setMenu calls free every replaced menu exactly once '
      'and never the current one', () async {
    for (var i = 0; i < 25; i++) {
      await port.setMenu(_two);
    }
    await pumpEventQueue();

    for (var i = 0; i < 24; i++) {
      expect(menu(i).frees, 1, reason: 'menu $i');
    }
    expect(menu(24).frees, 0);
    expect(backend.contextMenu, same(menu(24)));
  });

  test('setMenu twice in one event frees the first menu once, after both '
      'calls', () async {
    final a = port.setMenu(_two);
    final b = port.setMenu(_two);
    await Future.wait([a, b]);
    expect(menu(0).frees, 0);
    await pumpEventQueue();

    expect(menu(0).frees, 1);
    expect(menu(1).frees, 0);
  });

  test('destroy twice frees the menu once and does not throw', () async {
    await port.setMenu(_two);

    await port.destroy();
    await port.destroy();
    await pumpEventQueue();

    expect(menu(0).frees, 1);
    expect(backend.calls.where((c) => c == 'destroy'), hasLength(2));
  });

  test('dispose while a free is pending still frees that menu, and a '
      'later destroy frees the current one', () async {
    await port.setMenu(_two);
    await port.setMenu(_two);
    await port.dispose();
    await pumpEventQueue();
    expect(menu(0).frees, 1);

    await port.destroy();
    await pumpEventQueue();

    expect(menu(1).frees, 1);
    expect(menu(0).frees, 1);
  });

  test(
    'a menu built after destroy is a normal menu, and is freed on the '
    'next replace (TrayService can call setMenu after a failed cleanup)',
    () async {
      await port.setMenu(_two);
      await port.destroy();
      await port.setMenu(_two);
      await port.setMenu(_two);
      await pumpEventQueue();

      expect(
        [for (final m in backend.menus) (m as _CountingMenu).frees],
        [1, 1, 0],
      );
    },
  );

  test('a setMenu whose native build throws midway frees the half-built '
      'menu and keeps the old one set and alive (no native leak)', () async {
    await port.setMenu(_two);
    backend.addItemFailsAt = 1;

    await expectLater(port.setMenu(_two), throwsStateError);
    await pumpEventQueue();

    expect(backend.contextMenu, same(menu(0)));
    expect(menu(0).frees, 0, reason: 'the old menu is still the icon\'s');
    expect(menu(1).frees, 1, reason: 'the half-built menu was never freed');
  });

  test('a setMenu whose setContextMenu throws frees the new menu and keeps '
      'the old one alive', () async {
    await port.setMenu(_two);
    backend.setContextMenuFails = true;

    await expectLater(port.setMenu(_two), throwsStateError);
    await pumpEventQueue();

    expect(menu(0).frees, 0);
    expect(menu(1).frees, 1, reason: 'the unused menu was never freed');
  });

  test('after a failed setMenu the next one still works and frees the '
      'menu that was current', () async {
    await port.setMenu(_two);
    backend.setContextMenuFails = true;
    await expectLater(port.setMenu(_two), throwsStateError);
    backend.setContextMenuFails = false;

    await port.setMenu(_two);
    await pumpEventQueue();

    expect(backend.contextMenu, same(menu(2)));
    expect(menu(0).frees, 1);
    expect(menu(2).frees, 0);
  });

  test('a click on an item of a replaced menu, still inside its own '
      'handler, reports that item once', () async {
    await port.setMenu(_two);
    final old = menu(0);
    final keys = <String>[];
    port.menuItemClicks.listen(keys.add);
    await port.setMenu(_two);

    old.clickItem('Quit');
    await pumpEventQueue();

    expect(keys, ['quit']);
  });

  test('a click on an item of a menu that is already freed does not '
      'throw and does not reach a disposed port', () async {
    await port.setMenu(_two);
    final old = menu(0);
    await port.dispose();

    old.clickItem('Open');
    await pumpEventQueue();
  });

  test('every item of a submenu tree reports its own key, even when two '
      'entries share a label', () async {
    final keys = <String>[];
    port.menuItemClicks.listen(keys.add);
    await port.setMenu(const [
      TrayMenuEntry(
        key: 'pause',
        label: 'Pause history',
        children: [
          TrayMenuEntry(key: 'pause_15m', label: 'Same'),
          TrayMenuEntry(key: 'pause_1h', label: 'Same'),
        ],
      ),
      TrayMenuEntry(key: 'quit', label: 'Quit'),
    ]);

    final sub = menu(0).items.first.submenu!;
    sub.items[0].onClick!();
    sub.items[1].onClick!();
    await pumpEventQueue();

    expect(keys, ['pause_15m', 'pause_1h']);
  });

  test('an empty entry list sets an empty menu without throwing', () async {
    await port.setMenu(const []);

    expect(backend.contextMenu!.items, isEmpty);
  });

  test('a failed icon load leaves the old icon, and a later good one '
      'replaces it', () async {
    await port.setIcon('assets/tray/a.png');
    backend.setIconFails = true;

    await expectLater(port.setIcon('assets/tray/b.png'), throwsArgumentError);
    expect(backend.iconPath, 'assets/tray/a.png');

    backend.setIconFails = false;
    await port.setIcon('assets/tray/b.png');
    expect(backend.iconPath, 'assets/tray/b.png');
  });

  test('tooltip and label text goes to the native side unchanged '
      '(empty, long, accents, newline)', () async {
    final long = 'x' * 5000;
    for (final text in ['', long, 'Kusunga é — 履歴\nline two']) {
      await port.setToolTip(text);
      expect(backend.tooltip, text);
    }
    await port.setMenu([TrayMenuEntry(key: 'k', label: long)]);
    expect(backend.contextMenu!.labels, [long]);
  });

  test('tooltip and menu updates after dispose do not throw', () async {
    await port.dispose();

    await port.setToolTip('late');
    await port.setMenu(_two);
  });
}
