// M1.10c tester (re-check): WindowService around a failing hide and a
// failing dispose, on a fake port.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_service.dart';

class _Port implements WindowPort {
  final _closes = StreamController<void>.broadcast();
  final calls = <String>[];
  int hideFailures = 0;
  bool disposeFails = false;
  Completer<void>? initGate;

  @override
  Stream<void> get closeRequests => _closes.stream;

  void requestClose() => _closes.add(null);

  @override
  Future<void> init() async {
    calls.add('init');
    await initGate?.future;
  }

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> hide() async {
    calls.add('hide');
    if (hideFailures > 0) {
      hideFailures--;
      throw StateError('SECRET native text');
    }
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _closes.close();
    if (disposeFails) throw StateError('SECRET native text');
  }
}

void main() {
  late List<String> logs;

  setUp(() {
    logs = [];
    final old = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = old);
  });

  test('three failing hides on three close requests: three log lines, no '
      'uncaught error, and a show then a good close still work', () async {
    final port = _Port()..hideFailures = 3;
    final service = WindowService(port: port);
    await service.start();

    port
      ..requestClose()
      ..requestClose()
      ..requestClose();
    await pumpEventQueue();
    await service.show();
    port.requestClose();
    await pumpEventQueue();

    expect(logs, hasLength(3));
    expect(logs.join(), isNot(contains('SECRET')));
    expect(port.calls, ['init', 'hide', 'hide', 'hide', 'show', 'hide']);
    await service.dispose();
  });

  test('a dispose whose port throws is logged without the error text and '
      'does not throw; a second dispose does nothing', () async {
    final port = _Port()..disposeFails = true;
    final service = WindowService(port: port);
    await service.start();

    await service.dispose();
    await service.dispose();

    expect(logs, hasLength(1));
    expect(logs.single, isNot(contains('SECRET')));
    expect(port.calls.where((c) => c == 'dispose'), hasLength(1));
  });

  test('dispose while init is still waiting: no close listener is left, '
      'and the late close request hides nothing', () async {
    final port = _Port()..initGate = Completer<void>();
    final service = WindowService(port: port);
    final starting = service.start();
    await service.dispose();
    port.initGate!.complete();
    await starting;

    expect(port.calls, ['init', 'dispose']);
  });
}
