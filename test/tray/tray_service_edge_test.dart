import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_service.dart';

class _Port implements TrayPort {
  final clicks = StreamController<String>.broadcast();
  final calls = <String>[];
  Object? failOn; // 'icon' | 'tooltip' | 'menu' | 'destroy'

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

  @override
  Future<void> destroy() async {
    calls.add('destroy');
    if (failOn == 'destroy') throw StateError('destroy failed');
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
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

      expect(port.calls.last, 'destroy');
    });
  }

  test('after setIcon fails only the cleanup is attempted', () async {
    port.failOn = 'icon';
    await service.start();

    expect(port.calls, ['icon', 'destroy']);
  });

  test('failure in setMenu leaves no Quit listener', () async {
    port.failOn = 'menu';
    await service.start();

    port.clicks.add(TrayService.quitKey);
    await _pump();

    expect(quits, 0);
  });

  test('a failing destroy during cleanup does not throw either', () async {
    final s = TrayService(port: _FailBoth(), iconPath: 'i.png', onQuit: () {});

    await s.start();
  });

  test('dispose also disposes the port', () async {
    await service.start();
    await service.dispose();
    await service.dispose();

    expect(port.calls.where((c) => c == 'dispose'), hasLength(1));
  });
}

/// Fails setIcon and destroy.
class _FailBoth extends _Port {
  @override
  Future<void> setIcon(String path) async => throw StateError('icon failed');

  @override
  Future<void> destroy() async => throw StateError('destroy failed');
}
