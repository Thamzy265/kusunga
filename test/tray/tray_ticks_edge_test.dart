// M1.6 tester, round 3 (R8): the tray still retries a failed update on a
// tick now that PauseService no longer notifies on every tick, and shows the
// right "until" text across midnight.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/tray/tray_service.dart';

import '../support/fakes.dart';
import 'fake_tray_port.dart';

void main() {
  late FakeTrayPort port;
  late PauseService pause;
  late int now;
  late TrayService tray;

  setUp(() {
    port = FakeTrayPort();
    now = DateTime(2026, 11, 10, 23, 50).millisecondsSinceEpoch;
    pause = PauseService(
      setNativePause: (_) async => true,
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
      use24Hour: () => true,
      onOpenPicker: () {},
      onOpen: () {},
      onQuit: () {},
    );
  });

  tearDown(() async {
    await tray.dispose();
    pause.dispose();
  });

  test('a failed tooltip, icon and menu update is each set again on the '
      'next tick alone (no pause change, no notification)', () async {
    await tray.start();
    tray.attachPause(pause);
    for (final what in ['menu', 'tooltip', 'icon']) {
      port.failOn = what;
      await pause.pause(PauseLength.untilResumed);
      await pumpEventQueue();
      port.failOn = null;
      var notified = 0;
      pause.addListener(() => notified++);
      await pause.tick();
      await pumpEventQueue();
      expect(notified, 0, reason: 'the tick is quiet ($what)');
      expect(port.menu![2].key, 'resume', reason: what);
      expect(port.iconPath, 'icon_paused.png', reason: what);
      expect(port.toolTip, 'Kusunga — history paused', reason: what);
      await pause.resume();
      await pumpEventQueue();
    }
  });

  test('across midnight the tooltip loses "tomorrow" on the tick that '
      'crosses it', () async {
    await tray.start();
    tray.attachPause(pause);
    port.clicks.add('pause15');
    await pumpEventQueue();
    expect(port.toolTip, 'Kusunga — history paused until tomorrow 00:05');
    now = DateTime(2026, 11, 11, 0, 0, 1).millisecondsSinceEpoch;
    await pause.tick();
    await pumpEventQueue();
    expect(port.toolTip, 'Kusunga — history paused until 00:05');
  });

  test('dispose removes the tick listener too', () async {
    await tray.start();
    tray.attachPause(pause);
    await tray.dispose();
    final n = port.calls.length;
    await pause.tick();
    await pumpEventQueue();
    expect(port.calls.length, n);
  });
}
