import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_service.dart';

import 'fake_tray_port.dart';

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeTrayPort port;
  late int quits;
  late TrayService service;

  setUp(() {
    port = FakeTrayPort();
    quits = 0;
    service = TrayService(
      port: port,
      iconPath: 'i.png',
      onOpen: () {},
      onQuit: () => quits++,
    );
  });

  test('start called twice still quits only once per click', () async {
    // B1: a second start() is a no-op, so there is only one subscription.
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
    test('start does not throw when set$stage fails; tray is removed', () async {
      // F1: a tray failure must not stop the app. The error is logged and any
      // half-built tray icon is destroyed so there is never an icon without Quit.
      port.failOn = stage;

      await service.start();

      expect(port.calls, contains('destroy'));
    });
  }

  test('after setIcon fails only the cleanup is attempted', () async {
    port.failOn = 'icon';
    await service.start();

    expect(port.calls, ['icon', 'destroy', 'dispose']);
  });

  test(
    'C4: a failed start disposes the port (no retry on the same port)',
    () async {
      port.failOn = 'menu';
      await service.start();
      await service.start();

      expect(port.count('dispose'), 1);
      expect(port.count('menu'), 1, reason: 'a failed start is final');
    },
  );

  test('failure in setMenu leaves no Quit listener', () async {
    port.failOn = 'menu';
    await service.start();

    port.clicks.add(TrayService.quitKey);
    await _pump();

    expect(quits, 0);
  });

  test('a failing destroy during cleanup does not throw either', () async {
    final s = TrayService(
      port: _DestroyAlsoFails(),
      iconPath: 'i.png',
      onOpen: () {},
      onQuit: () {},
    );

    await s.start();
  });

  test(
    'C2: dispose removes the tray icon and disposes the port once',
    () async {
      await service.start();
      await service.dispose();
      await service.dispose();

      expect(port.count('destroy'), 1);
      expect(port.count('dispose'), 1);
    },
  );

  test(
    'C2: dispose while start is in flight stops later steps and destroys',
    () async {
      port.gateIcon = Completer<void>();
      final starting = service.start();
      await _pump();

      await service.dispose();
      port.gateIcon!.complete();
      await starting;

      expect(port.calls, ['icon', 'destroy', 'dispose', 'destroy']);
      expect(port.calls, isNot(contains('tooltip')));
      expect(port.calls, isNot(contains('menu')));
    },
  );
}

/// A port whose setIcon and destroy both throw.
class _DestroyAlsoFails extends FakeTrayPort {
  @override
  Future<void> setIcon(String path) async => throw StateError('icon failed');

  @override
  Future<void> destroy() async => throw StateError('destroy failed');
}
