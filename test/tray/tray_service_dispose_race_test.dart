// M1.10c developer: a tray update still in flight when TrayService disposes
// must not reach the native tray after destroy. On the real backend a late
// icon, tooltip or menu call makes the tray icon again, and a late menu is
// never freed. The real TrayManagerPort runs on the fake backend, so no test
// calls the real plugin.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

import '../support/fakes.dart';
import 'fake_tray_backend.dart';

/// The real port, with a gate after setIcon (an update held mid-await) and a
/// gate before dispose (the gap between destroy and dispose held open).
class _GatedPort implements TrayPort {
  _GatedPort(this.inner);

  final TrayManagerPort inner;
  Completer<void>? iconGate;
  Completer<void>? disposeGate;

  @override
  Stream<String> get menuItemClicks => inner.menuItemClicks;

  @override
  Future<void> setIcon(String path) async {
    await inner.setIcon(path);
    await iconGate?.future;
  }

  @override
  Future<void> setToolTip(String text) => inner.setToolTip(text);

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) => inner.setMenu(entries);

  @override
  Future<void> destroy() => inner.destroy();

  @override
  Future<void> dispose() async {
    await disposeGate?.future;
    await inner.dispose();
  }
}

void main() {
  test('dispose while a pause update waits on setIcon: once destroy has run, '
      'no icon, tooltip or menu call reaches the native tray', () async {
    final backend = FakeTrayBackend();
    final port = _GatedPort(TrayManagerPort(backend: backend));
    final pause = PauseService(
      setNativePause: (_) async => true,
      readSetting: (_) => null,
      writeSetting: (_, _) => true,
      log: FakeLog(),
      persists: true,
      clock: () => DateTime(2026, 11, 24, 12).millisecondsSinceEpoch,
    )..load();
    addTearDown(pause.dispose);
    final tray = TrayService(
      port: port,
      iconPath: 'icon.png',
      pausedIconPath: 'icon_paused.png',
      use24Hour: () => true,
      onOpenPicker: () {},
      onOpen: () {},
      onQuit: () {},
    );
    tray.attachPause(pause);
    await tray.start();
    await pumpEventQueue();
    final menusBefore = backend.menus.length;

    port
      ..iconGate = Completer<void>()
      ..disposeGate = Completer<void>();
    unawaited(pause.pause(PauseLength.quarterHour));
    await pumpEventQueue();
    expect(backend.calls.last, 'setIcon', reason: 'the update is mid-await');

    final disposing = tray.dispose();
    await pumpEventQueue();
    expect(backend.calls.last, 'destroy');

    port.iconGate!.complete();
    await pumpEventQueue();
    port.disposeGate!.complete();
    await disposing;
    await pumpEventQueue();

    final afterDestroy = backend.calls.sublist(
      backend.calls.lastIndexOf('destroy') + 1,
    );
    expect(afterDestroy, isEmpty);
    expect(backend.menus, hasLength(menusBefore), reason: 'a late menu');
  });
}
