// M1.10c tester (re-check): the error paths the developer added to the tray
// port, attacked from the sides the first tests did not: logs that carry
// only an error type, a failing free during destroy, and the old menu still
// answering after a failed setMenu.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

import 'fake_tray_backend.dart';

class _Backend extends FakeTrayBackend {
  bool freeFails = false;
  bool openFails = false;
  bool contextMenuFails = false;

  @override
  TrayBackendMenu createMenu() {
    final menu = _Menu(this);
    menus.add(menu);
    return menu;
  }

  @override
  void setContextMenu(TrayBackendMenu menu) {
    if (contextMenuFails) throw StateError('SECRET label text');
    super.setContextMenu(menu);
  }

  @override
  void openContextMenu() {
    super.openContextMenu();
    if (openFails) throw StateError('SECRET label text');
  }
}

class _Menu extends FakeTrayMenu {
  _Menu(this.backend);

  final _Backend backend;

  @override
  void dispose() {
    super.dispose();
    if (backend.freeFails) throw StateError('SECRET label text');
  }
}

const _entries = [TrayMenuEntry(key: 'quit', label: 'Quit')];

void main() {
  late _Backend backend;
  late TrayManagerPort port;
  late List<String> logs;

  setUp(() {
    backend = _Backend();
    port = TrayManagerPort(backend: backend);
    addTearDown(port.dispose);
    logs = [];
    final old = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = old);
  });

  test('destroy whose menu free throws logs the error type only, not the '
      'error text, and the port keeps working', () async {
    await port.setMenu(_entries);
    backend.freeFails = true;

    await port.destroy();
    await pumpEventQueue();

    expect(logs, hasLength(1));
    expect(logs.single, contains('StateError'));
    expect(logs.single, isNot(contains('SECRET')));
    backend.freeFails = false;
    await port.setMenu(_entries);
    expect(backend.contextMenu!.labels, ['Quit']);
  });

  test('a menu that cannot open on a click is logged without the error text, '
      'and the next click still tries', () async {
    backend.openFails = true;

    backend.click(TrayIconClick.left);
    backend.click(TrayIconClick.right);

    expect(backend.calls.where((c) => c == 'openContextMenu'), hasLength(2));
    expect(logs, hasLength(2));
    expect(logs.join(), isNot(contains('SECRET')));
  });

  test('after a failed setMenu the old menu still reports its clicks and '
      'is not freed', () async {
    await port.setMenu(_entries);
    final old = backend.contextMenu!;
    final keys = <String>[];
    port.menuItemClicks.listen(keys.add);
    backend.contextMenuFails = true;

    await expectLater(port.setMenu(_entries), throwsStateError);
    await pumpEventQueue();
    old.clickItem('Quit');
    await pumpEventQueue();

    expect(keys, ['quit']);
    expect(old.disposed, isFalse);
  });

  test('a failed setMenu whose free also throws surfaces the first error '
      'once and logs the free failure once', () async {
    await port.setMenu(_entries);
    backend
      ..contextMenuFails = true
      ..freeFails = true;

    await expectLater(port.setMenu(_entries), throwsStateError);
    await pumpEventQueue();

    expect(logs, hasLength(1));
  });

  test(
    'every menu replaced while frees throw is still attempted once',
    () async {
      backend.freeFails = true;
      for (var i = 0; i < 4; i++) {
        await port.setMenu(_entries);
      }
      await pumpEventQueue();

      expect(
        [for (final m in backend.menus) m.disposed],
        [true, true, true, false],
      );
      expect(logs, hasLength(3));
    },
  );

  test('dispose then destroy (the service order is destroy then dispose, '
      'but a late destroy must still be safe) does not throw', () async {
    await port.setMenu(_entries);
    await port.dispose();

    await port.destroy();
    await pumpEventQueue();

    expect(backend.menus.single.disposed, isTrue);
  });
}
