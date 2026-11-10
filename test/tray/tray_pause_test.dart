// M1.6 tray / menu bar (UI spec "Tray menu" and "Tray tooltip"): "Pause
// history ▸" with three lengths when not paused, "Resume history" when
// paused, the tooltip saying until when, and the paused icon variant.
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

  setUp(() {
    port = FakeTrayPort();
    now = DateTime(2026, 11, 10, 14, 15).millisecondsSinceEpoch;
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

  List<(String, String)> top() => [
    for (final e in port.menu!) (e.key, e.label),
  ];

  Future<void> click(String key) async {
    port.clicks.add(key);
    await pumpEventQueue();
  }

  test('not paused: Pause history with its three lengths', () async {
    await tray.start();
    tray.attachPause(pause);
    await pumpEventQueue();
    expect(top(), [
      ('picker', 'Open picker'),
      ('open', 'Open Kusunga'),
      ('pause', 'Pause history'),
      ('quit', 'Quit'),
    ]);
    final sub = port.menu![2].children!;
    expect(
      [for (final e in sub) (e.key, e.label)],
      [
        ('pause15', 'For 15 minutes'),
        ('pause60', 'For 1 hour'),
        ('pauseUntil', 'Until I resume'),
      ],
    );
    expect(port.toolTip, 'Kusunga');
    expect(port.iconPath, 'icon.png');
  });

  test('For 15 minutes: Resume history, the tooltip says until when, the '
      'paused icon', () async {
    await tray.start();
    tray.attachPause(pause);
    await click('pause15');
    expect(pause.pausedUntil, now + 15 * _min);
    expect(top(), [
      ('picker', 'Open picker'),
      ('open', 'Open Kusunga'),
      ('resume', 'Resume history'),
      ('quit', 'Quit'),
    ]);
    expect(port.menu![2].children, isNull);
    expect(port.toolTip, 'Kusunga — history paused until 14:30');
    expect(port.iconPath, 'icon_paused.png');
  });

  test('For 1 hour and Until I resume', () async {
    await tray.start();
    tray.attachPause(pause);
    await click('pause60');
    expect(pause.pausedUntil, now + 60 * _min);
    expect(port.toolTip, 'Kusunga — history paused until 15:15');
    await click('resume');
    await click('pauseUntil');
    expect(pause.untilResumed, isTrue);
    expect(port.toolTip, 'Kusunga — history paused');
  });

  test(
    'Resume history goes back to the normal menu, tooltip and icon',
    () async {
      await tray.start();
      tray.attachPause(pause);
      await click('pauseUntil');
      await click('resume');
      expect(pause.isPaused, isFalse);
      expect(top().map((e) => e.$1), ['picker', 'open', 'pause', 'quit']);
      expect(port.toolTip, 'Kusunga');
      expect(port.iconPath, 'icon.png');
    },
  );

  test('a pause that fails keeps "Pause history"', () async {
    await tray.start();
    tray.attachPause(pause);
    nativeOk = false;
    await click('pause15');
    expect(pause.isPaused, isFalse);
    expect(top().map((e) => e.$1), ['picker', 'open', 'pause', 'quit']);
    expect(port.iconPath, 'icon.png');
  });

  test(
    'a pause made in the app shows in the tray, and so does its end',
    () async {
      await tray.start();
      tray.attachPause(pause);
      await pause.pause(PauseLength.quarterHour);
      await pumpEventQueue();
      expect(top().map((e) => e.$1), contains('resume'));
      now += 15 * _min;
      await pause.tick();
      await pumpEventQueue();
      expect(top().map((e) => e.$1), contains('pause'));
      expect(port.toolTip, 'Kusunga');
    },
  );

  test('the tooltip uses the 12-hour format when the system does', () async {
    final twelve = TrayService(
      port: port,
      iconPath: 'icon.png',
      pausedIconPath: 'icon_paused.png',
      use24Hour: () => false,
      onOpenPicker: () {},
      onOpen: () {},
      onQuit: () {},
    );
    await twelve.start();
    twelve.attachPause(pause);
    await pause.pause(PauseLength.quarterHour);
    await pumpEventQueue();
    expect(port.toolTip, 'Kusunga — history paused until 2:30 PM');
    await twelve.dispose();
  });

  test('attached before start: start shows the pause state', () async {
    await pause.pause(PauseLength.untilResumed);
    tray.attachPause(pause);
    await tray.start();
    await pumpEventQueue();
    expect(top().map((e) => e.$1), contains('resume'));
    expect(port.toolTip, 'Kusunga — history paused');
    expect(port.iconPath, 'icon_paused.png');
  });

  test('the menu is only set again when the state changes', () async {
    await tray.start();
    tray.attachPause(pause);
    await pumpEventQueue();
    final menus = port.count('menu');
    await pause.tick(); // nothing changed
    await pumpEventQueue();
    expect(port.count('menu'), menus);
  });

  test('without a pause service the menu is as before', () async {
    await tray.start();
    expect(top().map((e) => e.$1), ['picker', 'open', 'quit']);
  });
}
