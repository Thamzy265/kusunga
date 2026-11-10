// M1.6 tester: tray edge cases (UI spec "Tray menu" and "Tray tooltip": the
// paused state must always be visible).
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/tray/tray_service.dart';

import '../support/fakes.dart';
import 'fake_tray_port.dart';

const _min = 60 * 1000;

void main() {
  late FakeTrayPort port;
  late PauseService pause;
  late int now;
  late bool nativeOk;
  late TrayService tray;
  var use24 = true;

  setUp(() {
    use24 = true;
    port = FakeTrayPort();
    now = DateTime(2026, 11, 10, 23, 50).millisecondsSinceEpoch;
    nativeOk = true;
    pause = PauseService(
      setNativePause: (_) async => nativeOk,
      readSetting: (_) => null,
      writeSetting: (_, _) => true,
      log: FakeLog(),
      persists: true,
      clock: () => now,
    )..load();
    tray = TrayService(
      port: port,
      iconPath: 'icon.png',
      pausedIconPath: 'icon_paused.png',
      use24Hour: () => use24,
      onOpenPicker: () {},
      onOpen: () {},
      onQuit: () {},
    );
  });

  tearDown(() async {
    await tray.dispose();
    pause.dispose();
  });

  Future<void> click(String key) async {
    port.clicks.add(key);
    await pumpEventQueue();
  }

  test('no pause entries before the history has opened', () async {
    await tray.start();
    expect([for (final e in port.menu!) e.key], ['picker', 'open', 'quit']);
    expect(port.toolTip, 'Kusunga');
    // Pause / Resume clicks do nothing without a service.
    await click('pause15');
    await click('resume');
    expect(port.iconPath, 'icon.png');
  });

  test('paused at launch: the first menu, icon and tooltip are already the '
      'paused ones', () async {
    final p = PauseService(
      setNativePause: (_) async => true,
      readSetting: (_) => '-1',
      writeSetting: (_, _) => true,
      log: FakeLog(),
      persists: true,
      clock: () => now,
    )..load();
    addTearDown(p.dispose);
    tray.attachPause(p);
    await tray.start();
    await pumpEventQueue();
    expect(port.iconPath, 'icon_paused.png');
    expect(port.toolTip, 'Kusunga — history paused');
    expect(
      [for (final e in port.menu!) e.key],
      ['picker', 'open', 'resume', 'quit'],
    );
  });

  test('across midnight the tooltip says tomorrow', () async {
    await tray.start();
    tray.attachPause(pause);
    await click('pause15'); // 23:50 + 15 min = 00:05 the next day
    expect(port.toolTip, 'Kusunga — history paused until tomorrow 00:05');
  });

  test('12-hour format in the tooltip', () async {
    use24 = false;
    now = DateTime(2026, 11, 10, 13, 0).millisecondsSinceEpoch;
    await tray.start();
    tray.attachPause(pause);
    await click('pause60');
    expect(port.toolTip, 'Kusunga — history paused until 2:00 PM');
  });

  test(
    'a timed pause that ends on a tick: menu, icon and tooltip swap back',
    () async {
      await tray.start();
      tray.attachPause(pause);
      await click('pause15');
      expect(port.iconPath, 'icon_paused.png');
      now += 16 * _min;
      await pause.tick();
      await pumpEventQueue();
      expect(port.iconPath, 'icon.png');
      expect(port.toolTip, 'Kusunga');
      expect(port.menu![2].key, 'pause');
    },
  );

  test('a failed native pause leaves the menu on "Pause history"', () async {
    await tray.start();
    tray.attachPause(pause);
    nativeOk = false;
    await click('pause60');
    expect(port.menu![2].key, 'pause');
    expect(port.iconPath, 'icon.png');
    expect(port.toolTip, 'Kusunga');
  });

  test('repeated notifications with no change set nothing again', () async {
    await tray.start();
    tray.attachPause(pause);
    await click('pauseUntil');
    final before = port.calls.length;
    await pause.tick();
    await pause.tick();
    await pumpEventQueue();
    expect(port.calls.length, before);
  });

  test('a tray update that throws is tried again on the next change, so the '
      'paused state does not stay hidden', () async {
    await tray.start();
    tray.attachPause(pause);
    port.failOn = 'menu';
    await click('pauseUntil'); // pause applies, the tray update throws
    expect(pause.isPaused, isTrue);
    port.failOn = null;
    // A later tick with the pause still on must put the tray right.
    await pause.tick();
    await pumpEventQueue();
    expect(
      port.menu![2].key,
      'resume',
      reason: 'the menu still offers "Pause history" while paused',
    );
    expect(port.iconPath, 'icon_paused.png');
  });

  test(
    'dispose removes the listener: later pause changes touch no tray call',
    () async {
      await tray.start();
      tray.attachPause(pause);
      await tray.dispose();
      final n = port.calls.length;
      await pause.pause(PauseLength.hour);
      await pumpEventQueue();
      expect(port.calls.length, n);
    },
  );
}
