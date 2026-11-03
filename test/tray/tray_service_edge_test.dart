import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_service.dart';

class _Port implements TrayPort {
  final clicks = StreamController<String>.broadcast();
  final calls = <String>[];
  Object? failOn; // 'icon' | 'tooltip' | 'menu'

  @override
  Stream<String> get menuItemClicks => clicks.stream;

  @override
  Future<void> setIcon(String path) async {
    calls.add('icon');
    if (failOn == 'icon') throw StateError('icon failed');
  }

  @override
  Future<void> setToolTip(String text) async {
    calls.add('tooltip');
    if (failOn == 'tooltip') throw StateError('tooltip failed');
  }

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async {
    calls.add('menu');
    if (failOn == 'menu') throw StateError('menu failed');
  }
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late _Port port;
  late int quits;
  late TrayService service;

  setUp(() {
    port = _Port();
    quits = 0;
    service = TrayService(port: port, iconPath: 'i.png', onQuit: () => quits++);
  });

  test('REPRO: start called twice still quits only once per click', () async {
    // Finding: start() subscribes every time and overwrites _clicks, so the
    // first subscription leaks and onQuit fires twice. Expected to fail today.
    await service.start();
    await service.start();

    port.clicks.add(TrayService.quitKey);
    await _pump();

    expect(quits, 1);
  });

  test(
    'Quit clicked twice calls onQuit twice (service does not latch)',
    () async {
      // Regression lock: the service passes each click through; callers decide
      // whether a second quit matters.
      await service.start();

      port.clicks.add(TrayService.quitKey);
      port.clicks.add(TrayService.quitKey);
      await _pump();

      expect(quits, 2);
    },
  );

  test('dispose stops Quit from firing', () async {
    await service.start();
    await service.dispose();

    port.clicks.add(TrayService.quitKey);
    await _pump();

    expect(quits, 0);
  });

  test('dispose before start and dispose twice do not throw', () async {
    await service.dispose();
    await service.start();
    await service.dispose();
    await service.dispose();
  });

  test('menu key matching is exact (case and whitespace)', () async {
    await service.start();

    for (final k in ['Quit', 'QUIT', 'quit ', '', ' quit']) {
      port.clicks.add(k);
    }
    await _pump();

    expect(quits, 0);
  });

  for (final stage in ['icon', 'tooltip', 'menu']) {
    test('start propagates a plugin failure in set$stage', () async {
      // Behaviour on plugin failure is not specified by the developer; this
      // only locks that the error is not silently swallowed.
      port.failOn = stage;

      await expectLater(service.start(), throwsStateError);
    });
  }

  test('FINDING: after setIcon fails nothing else is attempted', () async {
    port.failOn = 'icon';
    await expectLater(service.start(), throwsStateError);

    expect(port.calls, ['icon']);
  });

  test('FINDING: failure in setMenu leaves no Quit listener', () async {
    // Icon may be showing with no menu and no way to quit; documents current
    // behaviour so a deliberate fix has to update this test.
    port.failOn = 'menu';
    await expectLater(service.start(), throwsStateError);

    port.clicks.add(TrayService.quitKey);
    await _pump();

    expect(quits, 0);
  });
}
