import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_service.dart';

class FakeWindowPort implements WindowPort {
  final closes = StreamController<void>.broadcast();
  final calls = <String>[];
  bool failInit = false;

  @override
  Stream<void> get closeRequests => closes.stream;

  @override
  Future<void> init() async {
    calls.add('init');
    if (failInit) throw StateError('init failed');
  }

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late FakeWindowPort port;
  late WindowService service;

  setUp(() {
    port = FakeWindowPort();
    service = WindowService(port: port);
  });

  test('closing the window hides it instead of quitting', () async {
    await service.start();

    port.closes.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(port.calls, ['init', 'hide']);
  });

  test('show brings the window back', () async {
    await service.start();

    await service.show();

    expect(port.calls, ['init', 'show']);
  });

  test('a window setup failure is logged, not thrown', () async {
    port.failInit = true;

    await service.start();

    // The port can still set the window up later (M1.10c), so a close
    // request after a failed init still hides the window.
    port.closes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(port.calls, ['init', 'hide']);
  });

  test('dispose stops handling close and disposes the port once', () async {
    await service.start();
    await service.dispose();
    await service.dispose();

    port.closes.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(port.calls, ['init', 'dispose']);
  });
}
